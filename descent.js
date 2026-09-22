// Descent window: a simplified simulation on bestiary numbers, drawn on a canvas.
(function () {
  const { EL, BEASTS, ORDER, drawBeast, drawHero, fit, reduced } = RM;
  const $ = (id) => document.getElementById(id);

  // Ranks, relics, skills and modifiers use the game's own English localization.
  const RANKS = [
    { name: 'Ragged', mult: 1.0, bag: 8 },
    { name: 'Veteran', mult: 1.35, bag: 10 },
    { name: 'Blade', mult: 1.8, bag: 12 },
    { name: 'Legend', mult: 2.4, bag: 16 },
  ];
  const ELEMS = ['physical', 'fire', 'cold', 'lightning', 'voidType'];
  const SKILL = { physical: 'Sunder', fire: 'Ember Burst', cold: 'Glacier Shard', lightning: 'Storm Call', voidType: 'Rift' };
  const WEAPON = { physical: 'two', fire: 'one', cold: 'shield', lightning: 'one', voidType: 'two' };
  const BOSSES = ['ash_lord', 'void_devourer', 'storm_sovereign', 'frost_patriarch'];
  const MOBS = ORDER.filter((id) => !BEASTS[id].boss);
  const WEIGHT = { scavenger: 30, bonebreaker: 18, ash_eater: 18, frost_warden: 12, void_whisperer: 10, blood_leech: 10, stone_fist: 9, rot_howler: 7, grave_swarm: 24, cinderling: 12, forge_smith: 8, rime_horror: 12, frost_maw: 10, sparkling: 22, storm_warden: 8, arc_leech: 10, void_reaper: 9, mana_eater: 8, rift_shade: 9 };
  const SOURCED = { ash_lord: ['Ashen Covenant', 'Ember Conduit'], void_devourer: ['Seal of a Thousand Eyes', 'Void Conduit'], storm_sovereign: ['Seal of Haste', 'Storm Conduit'], frost_patriarch: ['Hide of Prisms', 'Rime Conduit'] };
  const KINDS = ['Weapon', 'Off-hand', 'Helmet', 'Body Armor', 'Gloves', 'Boots', 'Ring', 'Amulet'];
  const RARITY = [
    { name: 'Common', c: '#C4B6A8' },
    { name: 'Uncommon', c: '#7FB069' },
    { name: 'Rare', c: '#4F8FC7' },
    { name: 'Relic', c: '#C7643F' },
  ];
  // Floor modifiers from floor_modifiers.json: one cost, one reward.
  const MODS = {
    heat: { name: 'Swelter', minus: '−30 fire resistance', plus: '+15% Fire damage dealt', danger: 2 },
    hunger: { name: 'Hunger', minus: 'HP regeneration does not work', plus: '+40% loot', danger: 3 },
    vice: { name: 'The Vice', minus: 'Cooldowns +25%', plus: 'Bosses give double Echo', danger: 1 },
    abundance: { name: 'Abundance', minus: 'Enemies hit 20% harder', plus: '+50% loot quantity', danger: 3 },
    chill: { name: 'Bitter Cold', minus: '−30 cold resistance', plus: 'Cooldowns −15%', danger: 2 },
    void_rot: { name: 'Void Rot', minus: '−30 void resistance', plus: '+1 chest rarity rank', danger: 2 },
  };

  const G = 1.09;            // enemy growth per floor
  const HERO_INT = 0.8;      // auto-attack interval
  const SKILL_CD = 4.5;
  const BASE_SPEED = 1.6;    // game seconds per real second
  const FORK_WAIT = 12;      // real seconds of waiting at a fork
  const REST = 0.35;         // rest between floors, share of max HP

  const rnd = Math.random;
  const randInt = (a, b) => a + Math.floor(rnd() * (b - a + 1));
  const fmt = (n) => Math.round(n).toLocaleString('en-US');

  let record = 0;
  try { record = parseInt(localStorage.getItem('riftmark.record') || '0', 10) || 0; } catch (e) { record = 0; }

  const S = {
    rank: 2, elem: 'fire', phase: 'idle', running: false, speed: 1, contract: 0,
    floor: 1, wave: 0, waves: 3, foes: [], fx: [], hero: null, gold: 0, echo: 0, kills: 0,
    bag: [], relics: [], path: null, pathLeft: 0, phaseT: 0, linger: 0, scroll: 0, visT: 0,
    forkLeft: 0, fork: null, deathT: 0, startFloor: 1, explodeLogged: false,
  };

  // --- Path effects ---
  const P = () => S.path || { minus: null, plus: [] };
  const dmgMult = (f) => {
    const p = P(); let m = 1;
    if (p.minus === 'abundance') m *= 1.2;
    if (p.minus === 'heat' && f.b.dmg === 'fire') m *= 1.3;
    if (p.minus === 'chill' && f.b.dmg === 'cold') m *= 1.3;
    if (p.minus === 'void_rot' && f.b.dmg === 'voidType') m *= 1.3;
    return m;
  };
  const cdMult = () => (P().minus === 'vice' ? 1.25 : 1) * (P().plus.includes('chill') ? 0.85 : 1);
  const heroBonus = () => (P().plus.includes('heat') && S.elem === 'fire' ? 1.15 : 1);
  const lootMult = () => (P().plus.includes('hunger') ? 1.4 : 1) * (P().plus.includes('abundance') ? 1.5 : 1);

  // --- Log ---
  const logEl = $('log');
  function log(html) {
    const li = document.createElement('li');
    li.innerHTML = `<span class="t">F${S.floor}</span>${html}`;
    logEl.prepend(li);
    while (logEl.children.length > 6) logEl.lastElementChild.remove();
  }

  // --- Waves ---
  function pickMob() {
    let tot = 0; for (const id of MOBS) tot += WEIGHT[id];
    let r = rnd() * tot;
    for (const id of MOBS) { r -= WEIGHT[id]; if (r <= 0) return id; }
    return MOBS[0];
  }
  function makeFoe(id, s, big) {
    const b = BEASTS[id];
    const max = 11 * b.hp * s * (big ? 1.4 : 1);
    return { id, b, big, max, hp: max, dps: 1.6 * b.dps * s * (big ? 1.2 : 1), as: b.as, atk: (0.4 + rnd() * 0.8) / b.as,
      dead: false, deadT: 0, flash: 0, lunge: 0, ramp: b.traits.includes('rampUp'), px: 0, py: 0, ph: 0 };
  }
  function matchup(b) {
    const r = b.res[S.elem] || 0;
    const what = S.elem === 'physical' ? 'physical damage' : EL[S.elem].name;
    if (r < 0) return ` — <span class="c-good">weak to ${what} (+${-r}%)</span>`;
    if (r > 0) return ` — <span class="c-bad">resists ${what} (−${r}%)</span>`;
    return '';
  }
  function spawnWave(silent) {
    const f = S.floor, s = Math.pow(G, f - 1);
    S.explodeLogged = false;
    if (f % 5 === 0 && S.wave === S.waves - 1) {
      const id = BOSSES[(f / 5 - 1) % 4], big = f % 10 === 0;
      S.foes = [makeFoe(id, s, big)];
      if (!silent) log(`<span class="c-bad">${big ? 'Big boss' : 'Boss'}:</span> <span class="c-ink">${BEASTS[id].name}</span>${matchup(BEASTS[id])}`);
    } else {
      const id = pickMob(), b = BEASTS[id];
      const n = Math.min(4, randInt(b.packMin, b.packMax));
      S.foes = Array.from({ length: n }, () => makeFoe(id, s, false));
      if (!silent && S.wave === 0) log(`${b.name} ×${n}${matchup(b)}`);
    }
  }

  // --- Combat ---
  const rank = () => RANKS[S.rank];
  function addNum(x, y, txt, c, size) { S.fx.push({ kind: 'num', x, y, txt, c, size: size || 13, life: 0, max: 0.9 }); }
  function hit(f, dmg, crit) {
    f.hp -= dmg; f.flash = 0.09;
    addNum(f.px + (rnd() - 0.5) * 16, f.py, fmt(dmg) + (crit ? '!' : ''), EL[S.elem].c, crit ? 17 : 13);
    if (f.hp <= 0 && !f.dead) kill(f);
  }
  function kill(f) {
    f.dead = true; f.deadT = 0; S.kills++;
    if (f.id === 'cinderling' && S.phase === 'fight') {
      const dmg = (f.dps / f.as) * 1.2;
      if (!S.explodeLogged) { log(`A Cinderling explodes as it dies — <span class="c-bad">−${fmt(dmg)} HP</span>`); S.explodeLogged = true; }
      hurtHero(dmg);
    }
    if (f.b.boss) {
      S.echo += 3 * (P().plus.includes('vice') ? 2 : 1);
      if (rnd() < 0.14) {
        const name = SOURCED[f.id][randInt(0, 1)];
        S.relics.push(name);
        store({ name, r: 3 });
        log(`<span class="c-relic">Relic: ${name}</span> — only ${f.b.name.replace(/^The /, 'the ')} drops it`);
      }
    }
  }
  function hurtHero(dmg) {
    const H = S.hero; if (S.phase === 'dead') return;
    H.hp -= dmg; H.flash = 0.1;
    addNum(W0.hx, W0.hy, '−' + fmt(dmg), '#F08A6C', 12);
    if (H.hp <= 0) die();
  }
  function heroHitOn(f) {
    const r = f.b.res[S.elem] || 0;
    const crit = rnd() < 0.15;
    return [14 * rank().mult * HERO_INT * (1 - r / 100) * heroBonus() * (crit ? 2 : 1), crit];
  }
  function castSkill(alive) {
    S.fx.push({ kind: 'arc', life: 0, max: 0.55, c: EL[S.elem].c, name: SKILL[S.elem] });
    for (const f of alive) {
      if (f.dead) continue;
      const r = f.b.res[S.elem] || 0;
      hit(f, 14 * rank().mult * HERO_INT * 1.1 * (1 - r / 100) * heroBonus(), false);
    }
  }

  function update(dt) {
    const H = S.hero;
    if (S.phase === 'walk') {
      S.phaseT += dt; S.scroll += dt * 150;
      if (S.phaseT >= 0.9) { S.phase = 'fight'; S.phaseT = 0; }
    } else if (S.phase === 'fight') {
      S.phaseT += dt;
      const alive = S.foes.filter((f) => !f.dead);
      if (!alive.length) { S.linger += dt; if (S.linger > 0.45) waveCleared(); return; }
      H.atk -= dt;
      if (H.atk <= 0) { H.atk += HERO_INT; const [d, c] = heroHitOn(alive[0]); hit(alive[0], d, c); H.lunge = 1; }
      H.skill -= dt;
      if (H.skill <= 0) { H.skill += SKILL_CD * cdMult(); castSkill(alive); }
      for (const f of alive) {
        if (f.dead) continue;
        if (f.id === 'rot_howler') for (const o of alive) if (o !== f && !o.dead) o.hp = Math.min(o.max, o.hp + o.max * 0.03 * dt);
        f.atk -= dt;
        if (f.atk <= 0) {
          f.atk += 1 / f.as; f.lunge = 1;
          const ramp = f.ramp ? 1 + 0.08 * S.phaseT : 1;
          hurtHero((f.dps / f.as) * ramp * dmgMult(f) * (0.85 + rnd() * 0.3));
          if (S.phase !== 'fight') return;
        }
      }
    } else if (S.phase === 'rest') {
      S.phaseT += dt;
      if (S.phaseT >= 0.7) nextFloor();
    }
  }

  function waveCleared() {
    S.linger = 0;
    if (S.wave < S.waves - 1) { S.wave++; spawnWave(); S.phase = 'walk'; S.phaseT = 0; }
    else floorCleared();
  }
  function store(item) {
    if (S.bag.length < rank().bag) { S.bag.push(item); return true; }
    return false;
  }
  function floorCleared() {
    const s = Math.pow(G, S.floor - 1), boss = S.floor % 5 === 0;
    S.gold += 9 * s * lootMult() * (boss ? 3 : 1);
    S.echo += 1;
    let r = rnd() < 0.55 ? 0 : rnd() < 0.67 ? 1 : 2;
    if (boss) r = Math.max(1, r);
    r = Math.min(2, r + (P().plus.includes('void_rot') ? 1 : 0));
    const name = `${RARITY[r].name} ${KINDS[randInt(0, KINDS.length - 1)]}`;
    if (store({ name, r })) log(`Floor chest: <span style="color:${RARITY[r].c}">${name}</span>`);
    else { S.gold += 6 * s; log(`Backpack full: <span style="color:${RARITY[r].c}">${name}</span> — turned into gold`); }
    if (P().minus === 'hunger') log('<span class="c-bad">Hunger:</span> no rest');
    else S.hero.hp = Math.min(S.hero.max, S.hero.hp + S.hero.max * REST);
    S.phase = 'rest'; S.phaseT = 0; S.foes = S.foes.filter((f) => !f.dead || f.deadT < 0.6);
  }
  function nextFloor() {
    S.floor++; S.wave = 0;
    if (S.path && --S.pathLeft <= 0) S.path = null;
    if (S.floor % 5 === 0) openFork();
    else { spawnWave(); S.phase = 'walk'; S.phaseT = 0; }
  }

  // --- Fork ---
  const forkEl = $('fork');
  function openFork() {
    const ids = Object.keys(MODS).sort(() => rnd() - 0.5).slice(0, 2);
    S.fork = ids; S.phase = 'fork'; S.forkLeft = FORK_WAIT;
    const [a, b] = ids.map((id) => MODS[id]);
    forkEl.innerHTML = `
      <div class="fork-top">The path splits before floor ${S.floor} <span id="forkSec">${FORK_WAIT} s</span></div>
      <div class="fork-opts">
        <button type="button" class="fork-opt" data-i="0"><b>${a.name}</b><span class="minus">${a.minus}</span><span class="plus">${a.plus}</span></button>
        <button type="button" class="fork-opt" data-i="1"><b>${b.name}</b><span class="minus">${b.minus}</span><span class="plus">${b.plus}</span></button>
        <button type="button" class="fork-opt bold" data-i="2"><b>A third path — only while you’re here</b><span class="plus">${a.plus} · ${b.plus}</span><span>Both rewards, no cost at all</span></button>
      </div>
      <div class="fork-timer"><i id="forkBar"></i></div>
      <p class="muted-note">In the game: 45 s while you play, 10 min while you’re away — then the standing order.</p>`;
    forkEl.hidden = false;
  }
  forkEl.addEventListener('click', (e) => {
    const btn = e.target.closest('.fork-opt');
    if (btn && S.phase === 'fork') chooseFork(+btn.dataset.i, false);
  });
  function chooseFork(i, byOrder) {
    const [a, b] = S.fork;
    if (i === 2) { S.path = { minus: null, plus: [a, b] }; log(`<span class="c-gold">Third path:</span> ${MODS[a].plus}, ${MODS[b].plus}`); }
    else {
      const id = S.fork[i]; S.path = { minus: id, plus: [id] };
      log(byOrder
        ? `No answer — follows the standing order: <span class="c-ink">${MODS[id].name}</span>`
        : `Path: <span class="c-ink">${MODS[id].name}</span> — <span class="c-good">${MODS[id].plus}</span>`);
    }
    S.pathLeft = 5; S.fork = null; forkEl.hidden = true;
    spawnWave(); S.phase = 'walk'; S.phaseT = 0;
  }

  // --- Death and report ---
  const reportEl = $('report');
  function die() {
    const H = S.hero; H.hp = 0;
    S.phase = 'dead'; S.deathT = 0; S.running = false;
    const prev = record;
    record = Math.max(record, S.floor);
    try { localStorage.setItem('riftmark.record', String(record)); } catch (e) { /* record just isn't kept */ }
    S.echo += Math.round(S.floor * 0.4);
    log(`<span class="c-bad">${rank().name} fell on floor ${S.floor}.</span> The haul waits at the Outpost.`);
    const rope = Math.max(1, Math.floor(record * 0.15));
    const isRecord = S.floor > prev;
    setTimeout(() => {
      reportEl.innerHTML = `
        <div class="report-card" role="dialog" aria-label="Contract report">
          <p class="rig-kicker">Contract #${S.contract} closed</p>
          <h3>Fell on floor ${S.floor}</h3>
          <dl>
            <dt>Gold</dt><dd class="c-gold">${fmt(S.gold)}</dd>
            <dt>Echo</dt><dd class="c-echo">+${S.echo}</dd>
            <dt>Kills</dt><dd>${fmt(S.kills)}</dd>
            <dt>Backpack</dt><dd>${S.bag.length} / ${rank().bag}</dd>
            <dt>Record</dt><dd>${record}${isRecord ? ' <span class="c-ember">new</span>' : ''}</dd>
          </dl>
          ${S.relics.length ? `<p class="sub"><span class="c-relic">Relic:</span> ${S.relics.join(', ')}</p>` : ''}
          <p class="sub">The rope will lower the next one straight to floor ${rope}. Change the rank or damage type and send again.</p>
          <div class="actions"><button type="button" class="btn btn-primary btn-sm" id="againBtn">Hire the next one</button></div>
        </div>`;
      reportEl.hidden = false;
      $('againBtn').addEventListener('click', start);
      syncControls();
    }, reduced ? 0 : 1100);
    syncControls();
  }

  // --- Start ---
  function newHero() {
    const m = rank().mult;
    return { max: 100 * m, hp: 100 * m, atk: 0.3, skill: 1.5, lunge: 0, flash: 0 };
  }
  function start() {
    S.contract++;
    S.startFloor = Math.max(1, Math.floor(record * 0.15));
    Object.assign(S, { floor: S.startFloor, wave: 0, waves: 3, fx: [], gold: 0, echo: 0, kills: 0, bag: [], relics: [], path: null, pathLeft: 0, fork: null, linger: 0, phaseT: 0, running: true });
    S.hero = newHero();
    forkEl.hidden = true; reportEl.hidden = true;
    logEl.innerHTML = '';
    log(S.startFloor > 1
      ? `<span class="c-ink">${rank().name}</span> heads down. The rope reaches straight to floor ${S.startFloor}.`
      : `<span class="c-ink">${rank().name}</span> heads into the rift.`);
    spawnWave(); S.phase = 'walk'; S.phaseT = 0;
    syncControls();
  }

  // --- Controls ---
  const rankSeg = $('rankSeg'), elemSeg = $('elemSeg'), sendBtn = $('sendBtn'), speedBtn = $('speedBtn');
  rankSeg.innerHTML = RANKS.map((r, i) => `<button type="button" data-i="${i}" aria-pressed="${i === S.rank}">${r.name}<span style="color:var(--ink-faint)">×${r.mult.toFixed(2)}</span></button>`).join('');
  elemSeg.innerHTML = ELEMS.map((e) => `<button type="button" data-e="${e}" style="--c:${EL[e].c}" aria-pressed="${e === S.elem}"><i class="dot"></i>${EL[e].name}</button>`).join('');
  rankSeg.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b || S.running) return;
    S.rank = +b.dataset.i; if (!S.hero || S.phase === 'idle') S.hero = newHero(); syncControls();
  });
  elemSeg.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b || S.running) return;
    S.elem = b.dataset.e; syncControls();
  });
  sendBtn.addEventListener('click', () => { if (!S.running) start(); });
  speedBtn.addEventListener('click', () => {
    S.speed = S.speed === 1 ? 6 : 1;
    speedBtn.setAttribute('aria-pressed', String(S.speed > 1));
    speedBtn.textContent = S.speed > 1 ? 'Normal speed' : 'Fast-forward ×6';
  });
  function syncControls() {
    rankSeg.querySelectorAll('button').forEach((b) => { b.setAttribute('aria-pressed', String(+b.dataset.i === S.rank)); b.disabled = S.running; });
    elemSeg.querySelectorAll('button').forEach((b) => { b.setAttribute('aria-pressed', String(b.dataset.e === S.elem)); b.disabled = S.running; });
    sendBtn.disabled = S.running;
    sendBtn.textContent = S.running ? 'Mercenary descending' : S.contract ? 'Hire the next one' : 'Send a mercenary';
    $('rigWho').textContent = `${rank().name} · ${EL[S.elem].name}`;
    $('rigKicker').textContent = `Contract #${Math.max(1, S.contract)} · descent window`;
  }
  RM.sendMercenary = () => {
    $('rig').scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'center' });
    if (!S.running) start();
  };

  // --- HUD ---
  const hud = { floor: $('floorNum'), waves: $('waves'), hpText: $('hpText'), hpBar: $('hpBar'), gold: $('goldText'), kills: $('killText'), bag: $('bag'), bagText: $('bagText') };
  const cache = {};
  function set(key, el, val, prop) { if (cache[key] !== val) { cache[key] = val; if (prop) el.style[prop] = val; else el.textContent = val; } }
  function drawHud() {
    const H = S.hero;
    set('floor', hud.floor, String(S.floor));
    const wv = `${S.wave}|${S.phase}|${S.floor}`;
    if (cache.wv !== wv) {
      cache.wv = wv;
      hud.waves.innerHTML = Array.from({ length: S.waves }, (_, i) => {
        const boss = S.floor % 5 === 0 && i === S.waves - 1;
        const on = i < S.wave || (i === S.wave && S.phase !== 'idle') || S.phase === 'rest';
        return `<i class="${on ? (boss ? 'boss' : 'on') : ''}"></i>`;
      }).join('');
    }
    set('hp', hud.hpText, `${fmt(Math.max(0, H.hp))} / ${fmt(H.max)}`);
    set('hpw', hud.hpBar, `${Math.max(0, (H.hp / H.max) * 100).toFixed(1)}%`, 'width');
    set('hpc', hud.hpBar, H.hp / H.max < 0.3 ? '#F08A6C' : '#8CCB6E', 'background');
    set('gold', hud.gold, fmt(S.gold));
    set('kills', hud.kills, fmt(S.kills));
    const bagKey = S.bag.length + '/' + rank().bag;
    if (cache.bag !== bagKey) {
      cache.bag = bagKey;
      hud.bagText.textContent = `${S.bag.length} / ${rank().bag}`;
      hud.bag.innerHTML = Array.from({ length: rank().bag }, (_, i) => {
        const it = S.bag[i];
        return it ? `<i style="background:${RARITY[it.r].c};border-color:${RARITY[it.r].c}"></i>` : '<i></i>';
      }).join('');
    }
  }

  // --- Scene ---
  const canvas = $('scene');
  const W0 = { hx: 0, hy: 0 };
  function prng(seed) {
    return () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  function profile(n, seed, rough) {
    const r = prng(seed), a = []; let v = 0.5;
    for (let i = 0; i < n; i++) { v = Math.max(0, Math.min(1, v + (r() - 0.5) * rough)); a.push(v); }
    return a;
  }
  const ridgeFar = profile(48, 7, 0.45), ridgeNear = profile(40, 19, 0.6), ceil = profile(56, 31, 0.9);
  const embers = Array.from({ length: 30 }, (_, i) => { const r = prng(100 + i); return { x: r(), y: r(), v: 0.015 + r() * 0.04, s: 0.6 + r() * 1.6, a: 0.25 + r() * 0.5, w: r() * 6 }; });

  function band(ctx, W, base, prof, off, amp, color, down) {
    const n = 24, step = W / (n - 2), start = Math.floor(off / step);
    ctx.fillStyle = color; ctx.beginPath();
    ctx.moveTo(0, base);
    for (let i = 0; i <= n; i++) {
      const x = i * step - (off % step);
      const v = prof[(start + i) % prof.length];
      const spike = down && i % 2 ? 0.35 : 1;
      ctx.lineTo(x, down ? base + v * amp * spike : base - v * amp - amp * 0.15);
    }
    ctx.lineTo(W, base); ctx.closePath(); ctx.fill();
  }

  function draw(rdt) {
    const { ctx, w: W, h: Hh } = fit(canvas);
    const gy = Math.round(Hh * 0.82);
    ctx.clearRect(0, 0, W, Hh);
    const g = ctx.createLinearGradient(0, 0, 0, Hh);
    g.addColorStop(0, '#1D1512'); g.addColorStop(0.7, '#120D0B'); g.addColorStop(1, '#0B0807');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, Hh);
    const glow = ctx.createRadialGradient(W * 0.62, -Hh * 0.15, 0, W * 0.62, -Hh * 0.15, Hh * 1.05);
    glow.addColorStop(0, 'rgba(232,128,79,0.16)'); glow.addColorStop(1, 'rgba(232,128,79,0)');
    ctx.fillStyle = glow; ctx.fillRect(0, 0, W, Hh);
    band(ctx, W, gy, ridgeFar, S.scroll * 0.2, Hh * 0.42, '#1B1411');
    band(ctx, W, gy, ridgeNear, S.scroll * 0.5, Hh * 0.2, '#161110');
    band(ctx, W, 0, ceil, S.scroll * 0.35, Hh * 0.2, '#0D0A09', true);
    ctx.fillStyle = '#0F0B0A'; ctx.fillRect(0, gy, W, Hh - gy);
    ctx.fillStyle = '#3A2D27'; ctx.fillRect(0, gy, W, 1);
    ctx.fillStyle = '#231A16';
    for (let i = 0; i < 14; i++) {
      const x = (((i * 131.7 - S.scroll) % W) + W) % W, y = gy + 6 + ((i * 37) % Math.max(1, Hh - gy - 10));
      ctx.fillRect(x, y, 3 + (i % 3) * 2, 2);
    }
    // embers
    for (const e of embers) {
      if (!reduced) { e.y -= e.v * rdt; if (e.y < -0.02) { e.y = 1.02; e.x = Math.random(); } }
      const x = (e.x * W + Math.sin(S.visT * 0.8 + e.w) * 8) % W;
      ctx.globalAlpha = e.a * (0.4 + 0.6 * e.y);
      ctx.fillStyle = '#E8804F';
      ctx.beginPath(); ctx.arc(x, e.y * gy, e.s, 0, Math.PI * 2); ctx.fill();
    }
    ctx.globalAlpha = 1;

    // mercenary
    const H = S.hero;
    const hh = Math.min(Hh * 0.36, W * 0.2);
    const hx = W * 0.2 + H.lunge * W * 0.03;
    W0.hx = hx; W0.hy = gy - hh * 1.08;
    shadow(ctx, hx, gy, hh * 0.3);
    drawHero(ctx, hx, gy, hh, S.visT, { accent: EL[S.elem].c, weapon: WEAPON[S.elem], flash: H.flash > 0, dead: S.phase === 'dead', alpha: S.phase === 'dead' ? Math.max(0.45, 1 - S.deathT) : 1 });

    // enemies
    const L = W * 0.46, R = W * 0.95;
    const mobH = Math.min(Hh * 0.28, W * 0.16);
    let hs = S.foes.map((f) => (f.b.boss ? Math.min(Hh * (f.big ? 0.6 : 0.52), W * 0.3) : mobH));
    const gap = 10;
    let widths = S.foes.map((f, i) => hs[i] * (f.b.aspect + 0.12));
    let total = widths.reduce((a, b) => a + b, 0) + gap * Math.max(0, S.foes.length - 1);
    if (total > R - L) { const k = (R - L) / total; hs = hs.map((v) => v * k); widths = widths.map((v) => v * k); total = R - L; }
    const walkOff = S.phase === 'walk' ? Math.pow(1 - Math.min(1, S.phaseT / 0.9), 2) * W * 0.6 : 0;
    let cur = L + (R - L - total) / 2;
    S.foes.forEach((f, i) => {
      const fw = widths[i], fh = hs[i];
      const cx = cur + fw / 2 + walkOff - f.lunge * W * 0.02; cur += fw + gap;
      if (f.dead && f.deadT > 0.7) return;
      const bob = reduced ? 0 : Math.sin(S.visT * 3 + i * 1.7) * 1.2;
      f.px = cx; f.py = gy - fh * 1.05; f.ph = fh;
      if (f.b.boss && !f.dead) {
        const rg = ctx.createRadialGradient(cx, gy - fh * 0.5, 0, cx, gy - fh * 0.5, fh * 0.9);
        rg.addColorStop(0, hexA(EL[f.b.dmg].c, 0.22)); rg.addColorStop(1, hexA(EL[f.b.dmg].c, 0));
        ctx.fillStyle = rg; ctx.fillRect(cx - fh, gy - fh * 1.5, fh * 2, fh * 1.6);
      }
      shadow(ctx, cx, gy, fw * 0.4);
      drawBeast(ctx, f.id, cx, gy + (f.dead ? f.deadT * 8 : bob), fh, S.visT + i, { dead: f.dead, flash: f.flash > 0, alpha: f.dead ? Math.max(0, 1 - f.deadT / 0.7) : 1 });
      if (!f.dead) {
        const bw = Math.max(26, Math.min(fw * 0.8, 90)), by = gy - fh * 1.14 - 8;
        ctx.fillStyle = '#281F1B'; ctx.fillRect(cx - bw / 2, by, bw, 4);
        ctx.fillStyle = f.b.boss ? '#F08A6C' : '#C9735A'; ctx.fillRect(cx - bw / 2, by, bw * Math.max(0, f.hp / f.max), 4);
      }
    });

    // effects
    ctx.textAlign = 'center';
    S.fx = S.fx.filter((fx) => (fx.life += rdt) < fx.max);
    for (const fx of S.fx) {
      const p = fx.life / fx.max;
      if (fx.kind === 'num') {
        ctx.globalAlpha = 1 - p * p;
        ctx.font = `600 ${fx.size}px "IBM Plex Mono", ui-monospace, monospace`;
        ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(12,9,8,0.85)';
        ctx.strokeText(fx.txt, fx.x, fx.y - p * 26); ctx.fillStyle = fx.c; ctx.fillText(fx.txt, fx.x, fx.y - p * 26);
      } else {
        ctx.globalAlpha = 1 - p;
        ctx.strokeStyle = fx.c; ctx.lineWidth = 2 + 7 * (1 - p); ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(W * 0.44 + p * 30, gy - Hh * 0.5); ctx.quadraticCurveTo(W * 0.8, gy - Hh * 0.56, W * 0.96, gy - Hh * 0.04); ctx.stroke();
        ctx.font = '600 12px "IBM Plex Mono", ui-monospace, monospace';
        ctx.fillStyle = fx.c; ctx.fillText(fx.name, hx, gy - hh * 1.3 - p * 12);
      }
    }
    ctx.globalAlpha = 1;

    if (S.phase === 'dead') {
      ctx.fillStyle = `rgba(12,9,8,${Math.min(0.45, S.deathT * 0.5)})`; ctx.fillRect(0, 0, W, Hh);
    }
  }
  function shadow(ctx, x, y, r) {
    ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.beginPath(); ctx.ellipse(x, y + 2, Math.max(1, r), Math.max(1, r * 0.16), 0, 0, Math.PI * 2); ctx.fill();
  }
  function hexA(hex, a) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
  }

  // --- Frame loop ---
  let last = performance.now();
  function frame(now) {
    const rdt = Math.min(0.05, (now - last) / 1000); last = now;
    const H = S.hero;
    if (S.running || !reduced) S.visT += rdt;
    H.lunge = Math.max(0, H.lunge - rdt * 7); H.flash = Math.max(0, H.flash - rdt);
    for (const f of S.foes) { f.lunge = Math.max(0, f.lunge - rdt * 6); f.flash = Math.max(0, f.flash - rdt); if (f.dead) f.deadT += rdt; }
    if (S.phase === 'fork') {
      S.forkLeft -= rdt;
      const bar = $('forkBar'), sec = $('forkSec');
      if (bar) bar.style.width = `${Math.max(0, (S.forkLeft / FORK_WAIT) * 100)}%`;
      if (sec) sec.textContent = `waiting for you · ${Math.max(0, Math.ceil(S.forkLeft))} s`;
      if (S.forkLeft <= 0) {
        const [a, b] = S.fork;
        chooseFork(MODS[a].danger <= MODS[b].danger ? 0 : 1, true);
      }
    } else if (S.phase === 'dead') {
      S.deathT += rdt;
    } else if (S.running) {
      let dt = rdt * BASE_SPEED * S.speed;
      while (dt > 0 && S.running && S.phase !== 'fork') { const step = Math.min(0.05, dt); update(step); dt -= step; }
    }
    draw(rdt);
    drawHud();
    requestAnimationFrame(frame);
  }

  // At rest before launch: the mercenary and the first wave are already on stage.
  S.hero = newHero();
  spawnWave(true);
  S.foes.forEach((f) => (f.atk = 1));
  syncControls();
  requestAnimationFrame((t) => { last = t; frame(t); });
  if (!reduced) setTimeout(() => { if (!S.running && S.contract === 0) start(); }, 700);
})();
