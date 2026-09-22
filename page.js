// Bestiary, build, Brand, lairs and the depth rail.
(function () {
  // ==========================================================================
  // ССЫЛКА НА ИГРУ В GOOGLE PLAY — единственное, что правится руками.
  //
  // Пока строка пустая, на сайте стоит «Coming to Google Play». Впишите адрес
  // страницы игры — кнопки на первом экране и в финале станут рабочими:
  //
  //   const PLAY_URL = 'https://play.google.com/store/apps/details?id=com.riftgame.rift_app';
  // ==========================================================================
  const PLAY_URL = '';

  for (const [linkId, soonId] of [['playTop', 'playTopSoon'], ['playEnd', 'playEndSoon']]) {
    const link = document.getElementById(linkId), soon = document.getElementById(soonId);
    if (!link || !soon || !PLAY_URL) continue;
    link.href = PLAY_URL;
    link.rel = 'noopener';
    link.hidden = false;
    soon.remove();
  }
  const { EL, TRAITS, BEASTS, ORDER, drawBeast, fit, reduced } = RM;
  const $ = (id) => document.getElementById(id);
  const ELEMS = ['physical', 'fire', 'cold', 'lightning', 'voidType'];
  const s = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  const hexA = (hex, a) => { const n = parseInt(hex.slice(1), 16); return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`; };
  document.documentElement.lang = 'en';
  const mid = (name) => name.replace(/^The /, 'the ');

  // Portrait scene: elemental glow, ground, figure.
  function portrait(canvas, id, t, opts) {
    const { ctx, w, h } = fit(canvas);
    const b = BEASTS[id], c = EL[b.dmg].c;
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#17110F'; ctx.fillRect(0, 0, w, h);
    const gy = h * (opts.ground || 0.86);
    const rg = ctx.createRadialGradient(w / 2, gy - h * 0.3, 0, w / 2, gy - h * 0.3, Math.max(w, h) * 0.6);
    rg.addColorStop(0, hexA(c, opts.glow || 0.16)); rg.addColorStop(1, hexA(c, 0));
    ctx.fillStyle = rg; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#0F0B0A'; ctx.fillRect(0, gy, w, h - gy);
    ctx.fillStyle = '#3A2D27'; ctx.fillRect(0, gy, w, 1);
    if (opts.motes) {
      ctx.fillStyle = c;
      for (let i = 0; i < 14; i++) {
        const k = ((i * 0.137 + t * (0.02 + (i % 4) * 0.008)) % 1);
        ctx.globalAlpha = 0.5 * (1 - k);
        ctx.beginPath(); ctx.arc(w * ((i * 0.618) % 1), gy - k * gy, 1 + (i % 3) * 0.6, 0, Math.PI * 2); ctx.fill();
      }
      ctx.globalAlpha = 1;
    }
    const size = Math.min(h * (opts.scale || 0.66), (w * 0.78) / (b.aspect + 0.25));
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath(); ctx.ellipse(w / 2, gy + 2, size * 0.36, size * 0.05, 0, 0, Math.PI * 2); ctx.fill();
    drawBeast(ctx, id, w / 2, gy, size, t);
  }

  // ---------------- Bestiary ----------------
  const filterEl = $('beastFilter'), tilesEl = $('tiles'), dossier = $('dossier');
  let filter = 'all', selected = 'cinderling';
  const counts = {}; ELEMS.forEach((e) => (counts[e] = ORDER.filter((id) => BEASTS[id].dmg === e).length));
  filterEl.innerHTML = `<button type="button" data-f="all" aria-pressed="true">All<span style="color:var(--ink-faint)">${ORDER.length}</span></button>` +
    ELEMS.map((e) => `<button type="button" data-f="${e}" style="--c:${EL[e].c}" aria-pressed="false"><i class="dot"></i>${EL[e].name}<span style="color:var(--ink-faint)">${counts[e]}</span></button>`).join('');
  tilesEl.innerHTML = ORDER.map((id) => {
    const b = BEASTS[id];
    return `<button type="button" class="tile" data-id="${id}" style="--c:${EL[b.dmg].c}" aria-pressed="${id === selected}">
      <canvas aria-hidden="true"></canvas>
      <span class="nm">${b.name}</span>
      <span class="rl"><i class="dot"></i>${b.boss ? EL[b.dmg].name : b.role}${b.boss ? '<span class="tag-boss">boss</span>' : ''}</span>
    </button>`;
  }).join('');
  const tiles = [...tilesEl.querySelectorAll('.tile')].map((el) => ({ el, id: el.dataset.id, canvas: el.querySelector('canvas') }));

  filterEl.addEventListener('click', (e) => {
    const btn = e.target.closest('button'); if (!btn) return;
    filter = btn.dataset.f;
    filterEl.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', String(b === btn)));
    tiles.forEach((t) => (t.el.hidden = filter !== 'all' && BEASTS[t.id].dmg !== filter));
    const firstVisible = tiles.find((t) => !t.el.hidden);
    if (firstVisible && BEASTS[selected].dmg !== filter && filter !== 'all') select(firstVisible.id);
    paintStatic();
  });
  tilesEl.addEventListener('click', (e) => { const t = e.target.closest('.tile'); if (t) select(t.dataset.id); });

  function resRows(b) {
    const pct = (v) => ((v + 50) / 120) * 100, zero = pct(0);
    return ELEMS.map((e) => {
      const v = b.res[e] || 0;
      const left = v < 0 ? pct(v) : zero, width = Math.abs(pct(v) - zero);
      const color = v < 0 ? 'var(--good)' : EL[e].c;
      const label = v === 0 ? '0' : (v > 0 ? '+' : '−') + Math.abs(v) + '%';
      return `<div class="res-row"><span>${EL[e].name}</span><span class="res-track"><i style="left:${left}%;width:${width}%;--c:${color}"></i></span><span class="val">${label}</span></div>`;
    }).join('');
  }
  function select(id) {
    selected = id;
    const b = BEASTS[id];
    tiles.forEach((t) => t.el.setAttribute('aria-pressed', String(t.id === id)));
    const traits = b.traits.length
      ? b.traits.map((k) => `<div class="trait"><b>${TRAITS[k][0]}</b><span>${TRAITS[k][1]}</span></div>`).join('')
      : `<p class="muted-note">No traits — ${b.boss ? 'it wins on health and damage' : 'it wins by numbers'}.</p>`;
    dossier.innerHTML = `
      <canvas id="dosCanvas" aria-hidden="true"></canvas>
      <div class="dossier-body">
        <div style="display:grid;gap:10px">
          <p class="eyebrow"><span class="depth">${b.boss ? 'Boss · every 5th floor' : b.role}</span></p>
          <h3>${b.name}</h3>
          <div class="meta">
            <span><i class="dot" style="--c:${EL[b.dmg].c}"></i>Deals ${EL[b.dmg].name}</span>
            <span>Health ×${b.hp}</span>
            <span>Damage ×${b.dps}</span>
            <span>${b.as} attacks/s</span>
            ${b.boss ? '' : `<span>Pack ${b.packMin}–${b.packMax}</span>`}
          </div>
        </div>
        <p class="note">${b.note}</p>
        <div class="res">
          ${resRows(b)}
          <div class="res-legend"><span>← weakness</span><span>resistance →</span></div>
        </div>
        <div class="traits">${traits}</div>
      </div>`;
    paintStatic();
  }

  // ---------------- Build ----------------
  const ICON = {
    helmet: '<path d="M5 15a7 7 0 0 1 14 0v4H5z"/><path d="M12 8V4M9 15h6"/>',
    amulet: '<path d="M6 3c0 5 3 8 6 9 3-1 6-4 6-9"/><path d="M12 12l3 4-3 5-3-5z"/>',
    ring: '<circle cx="12" cy="15" r="6"/><path d="M12 4l2.5 2.5L12 9 9.5 6.5z"/>',
    weapon: '<path d="M20 4v3L10 17l-3-3L17 4z"/><path d="M5.5 12.5l6 6M7.5 16.5 4 20"/>',
    armor: '<path d="M8 3 4 6v5l3 1v9h10v-9l3-1V6l-4-3c-1 2-2.5 3-4 3S9 5 8 3z"/>',
    offhand: '<path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z"/><path d="M12 7v10"/>',
    gloves: '<path d="M7 20v-5l-2.5-3.5L6 10l2 2V6a1.3 1.3 0 0 1 2.6 0v4V5a1.3 1.3 0 0 1 2.6 0v5V6a1.3 1.3 0 0 1 2.6 0v8c0 2.5-1 4.5-2.8 6z"/><path d="M7 17h8.8"/>',
    boots: '<path d="M8 3h5v10l6 3c1 .5 1.5 1.5 1.5 2.5V21H6V13z"/><path d="M6 17h14.5"/>',
  };
  const SLOTS = [['helmet', 'Helmet'], ['amulet', 'Amulet'], ['ring', 'Ring'], ['weapon', 'Weapon'], ['armor', 'Body Armor'], ['offhand', 'Off-hand'], ['gloves', 'Gloves'], ['boots', 'Boots'], ['ring', 'Ring']];
  const SOURCE = { ash_lord: 'fire', void_devourer: 'voidType', storm_sovereign: 'lightning', frost_patriarch: 'cold' };
  const RELICS = [
    ['Ashen Covenant', 'weapon', 'Burning can crit and stacks up to five times. Direct Fire damage −50%.', 'ash_lord'],
    ['Reaper’s Edge', 'weapon', 'An enemy below 18% health dies instantly. Damage −30%.'],
    ['Split Counterweight', 'offhand', 'Two-handed weapons can be held in one hand. Maximum HP −40%.'],
    ['Endless Censer', 'offhand', 'Abilities cost no mana. Cooldowns take twice as long.'],
    ['Crown of Obsession', 'helmet', 'Only one active ability is available. Its cooldown is −70% and it strikes the whole wave.'],
    ['Mask of Inevitability', 'helmet', 'Every hit is a critical strike. Base damage −45%.'],
    ['Glass Crown', 'helmet', '+70% to all damage. Maximum HP −55%.'],
    ['Horn of the Hunt', 'helmet', 'Bosses give twice as much. Every other enemy has +35% HP.'],
    ['Skin of Despair', 'armor', 'Maximum HP −65%. Anything that needs you below X% HP is always on. Life leech doubled.'],
    ['Hide of Prisms', 'armor', 'Armor does not work at all. +45 to all resistances.', 'frost_patriarch'],
    ['Accursed Pact', 'armor', 'Every hit you take grants +5% damage until the end of the wave, up to eight times.'],
    ['Counter of Moments', 'gloves', 'All counted effects trigger twice as often. Critical strikes are unavailable.'],
    ['Gauntlet of First Blood', 'gloves', 'The first blow against a wave lands three times as hard. Everything after it, −25%.'],
    ['Boots of the Descent', 'boots', 'One wave fewer per floor. Gold and items of common and uncommon rarity are not picked up.'],
    ['Tireless Boots', 'boots', 'The mercenary does not rest between floors. One wave fewer per floor.'],
    ['Rope of the Deep', 'boots', 'You start the descent 10 floors further down. Maximum HP −30%.'],
    ['Seal of a Thousand Eyes', 'ring', 'Curses last until the end of the floor and carry over to new waves. Damage to uncursed enemies −60%.', 'void_devourer'],
    ['Blood Oath', 'ring', 'Only leech heals you — no rest, no regeneration. Life leech ×3.'],
    ['Seal of Haste', 'ring', 'Cooldowns are half as long. Mana costs twice as much.', 'storm_sovereign'],
    ['Twin Rings', 'ring', 'Both rings give double. The amulet does not work.'],
    ['Charm of Silence', 'amulet', 'Every ability slot holds two passive abilities. Active abilities are unavailable.'],
    ['Ember Conduit', 'amulet', 'All damage becomes Fire, +30%. Fire resistance −50.', 'ash_lord'],
    ['Rime Conduit', 'amulet', 'All damage becomes Cold, +30%. Cold resistance −50.', 'frost_patriarch'],
    ['Storm Conduit', 'amulet', 'All damage becomes Lightning, +30%. Lightning resistance −50.', 'storm_sovereign'],
    ['Void Conduit', 'amulet', 'All damage becomes Void, +30%. Void resistance −50.', 'void_devourer'],
  ];
  const dollEl = $('doll'), relicsEl = $('relics');
  const nOf = (kind) => RELICS.filter((r) => r[1] === kind).length;
  dollEl.innerHTML = SLOTS.map(([kind, name], i) =>
    `<button type="button" class="slot" data-i="${i}" aria-pressed="${i === 1}"><svg viewBox="0 0 24 24" aria-hidden="true">${ICON[kind]}</svg><span class="sn">${name}</span><span class="sc">${s(nOf(kind), 'relic', 'relics')}</span></button>`
  ).join('');
  function showSlot(i) {
    const [kind, name] = SLOTS[i];
    dollEl.querySelectorAll('.slot').forEach((el) => el.setAttribute('aria-pressed', String(+el.dataset.i === i)));
    const list = RELICS.filter((r) => r[1] === kind);
    $('relicsTitle').textContent = name;
    $('relicsCount').textContent = s(list.length, 'relic', 'relics');
    relicsEl.innerHTML = list.map(([rname, , text, src]) => `
      <div class="relic">
        <div class="relic-name"><i></i>${rname}</div>
        <p>${text}</p>
        ${src ? `<span class="src" style="--c:${EL[SOURCE[src]].c}">Dropped only by ${mid(BEASTS[src].name)}</span>` : ''}
      </div>`).join('');
  }
  dollEl.addEventListener('click', (e) => { const el = e.target.closest('.slot'); if (el) showSlot(+el.dataset.i); });

  // ---------------- Brand of the Abyss ----------------
  const DEPTH = [39, 36, 32, 29, 27, 24], ECHO = [40, 42, 41, 40, 41, 39], OPENS = [0, 40, 60, 80, 100, 125];
  const range = $('brandRank');
  function brand() {
    const r = +range.value;
    $('brandNum').textContent = r;
    $('bDmg').textContent = `+${25 * r}%`;
    $('bLoot').textContent = `+${12 * r}%`;
    $('bEcho').textContent = `+${24 * r}%`;
    const cols = DEPTH.map((d, i) => `<div class="bcol${i === r ? ' on' : ''}"><span>${d}</span><i style="height:${(d / 40) * 100}px"></i></div>`).join('');
    const echo = ECHO.map((e, i) => `<div class="bcell${i === r ? ' on' : ''}">${e}</div>`).join('');
    const ranks = DEPTH.map((_, i) => `<div class="bcell${i === r ? ' on' : ''}">${i}</div>`).join('');
    $('bchart').innerHTML = `<span class="lab">Depth</span>${cols}<span class="lab">Echo per run</span>${echo}<span class="lab">Rank</span>${ranks}`;
    const lost = DEPTH[0] - DEPTH[r];
    $('brandVerdict').textContent = r === 0
      ? 'No Brand: a median of 39 floors and 40 Echo per descent. Each rank costs about three floors and barely moves the Echo.'
      : `Rank ${r} unlocks at a record of ${OPENS[r]}. Median depth ${DEPTH[r]} — ${s(lost, 'floor', 'floors')} shallower — and ${ECHO[r]} Echo per descent vs 40: a choice, not a tax.`;
  }
  range.addEventListener('input', brand);

  // ---------------- Lairs ----------------
  const WARDENS = [
    { name: 'Warden of the Ashen Halls', boss: 'ash_lord', quote: 'Ramps up and heals from what it deals: drag it out and you burn.', might: '5', weak: 'cold', key: 'the Rime Conduit',
      skills: [['Ash Rampart', 'heavy blow · 1.5 s wind-up'], ['Funeral Heat', 'burn · 0.8 s wind-up'], ['Second Flame', 'enrage below 30% HP']] },
    { name: 'Keeper of the Hollow Burrows', boss: 'void_devourer', quote: 'Eats mana and resistances: a build on active skills goes silent.', might: '5', weak: 'lightning', key: 'the Storm Conduit',
      skills: [['Maw of the Void', 'heavy blow · 1.8 s wind-up'], ['Hush', 'silence · 0.6 s wind-up'], ['Rend', 'exposes defenses · 1 s wind-up']] },
    { name: 'Warden of the Storm Reach', boss: 'storm_sovereign', quote: 'Answers every blow.', might: '3.5', weak: 'voidType', key: 'the Void Conduit',
      skills: [['Chain Lightning', 'heavy blow · 1 s wind-up'], ['Thunder Aegis', 'shield · 0.5 s wind-up'], ['The Sky Falls', 'enrage']] },
    { name: 'Patriarch of the Frozen Vault', boss: 'frost_patriarch', quote: 'Slows you, then hardens: too slow, and it can no longer be killed.', might: '5.5', weak: 'fire', key: 'the Ember Conduit',
      skills: [['Ice Prison', 'stun · 1.2 s wind-up'], ['Ice Shell', 'shield · 0.6 s wind-up'], ['Avalanche', 'heavy blow · 2.5 s wind-up']] },
  ];
  $('lairsGrid').innerHTML = WARDENS.map((w) => `
    <article class="lair">
      <canvas data-boss="${w.boss}" aria-hidden="true"></canvas>
      <div class="lair-body">
        <div style="display:grid;gap:6px"><h3>${w.name}</h3><span class="was">in the abyss — ${mid(BEASTS[w.boss].name)}</span></div>
        <blockquote>${w.quote}</blockquote>
        <ul class="skills">${w.skills.map(([n, k]) => `<li><b>${n}</b><span>${k}</span></li>`).join('')}</ul>
        <div class="lair-foot">
          <span class="pill weak" style="--c:${EL[w.weak].c}"><i class="dot"></i>Falls to ${w.key}</span>
          <span class="pill">Lair might ×${w.might}</span>
        </div>
      </div>
    </article>`).join('');
  const lairCanvases = [...document.querySelectorAll('#lairsGrid canvas')];
  $('ladder').innerHTML = [1, 2, 3, 4, 5].map((n) => `<span style="margin-top:${(n - 1) * 8}px">circle ${n}<b>${150 + 15 * (n - 1)}</b></span>`).join('') +
    '<span style="margin-top:40px">…<b>∞</b></span>' +
    '<p class="formula">Circle N sits at floor 150 + 15 × (N − 1). The offering costs 60 floors’ worth of income at the circle’s depth. The first win over a guardian grants 2 passive points; the first win of each circle drops the boss’s item.</p>';

  // ---------------- Portrait rendering ----------------
  const vis = { bestiary: true, lairs: true };
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((es) => es.forEach((e) => (vis[e.target.id] = e.isIntersecting)), { rootMargin: '120px' });
    io.observe($('bestiary')); io.observe($('lairs'));
  }
  function paintBestiary(t) {
    for (const tl of tiles) if (!tl.el.hidden) portrait(tl.canvas, tl.id, t + tl.id.length, { ground: 0.84, scale: 0.62, glow: 0.1 });
    const dc = $('dosCanvas');
    if (dc) portrait(dc, selected, t, { ground: 0.86, scale: 0.68, glow: 0.2, motes: !reduced });
  }
  function paintLairs(t) {
    lairCanvases.forEach((c, i) => portrait(c, c.dataset.boss, t + i, { ground: 0.88, scale: 0.7, glow: 0.24, motes: !reduced }));
  }
  function paintStatic() { paintBestiary(clock); paintLairs(clock); }
  let clock = 0, prev = performance.now();
  function loop(now) {
    const dt = Math.min(0.05, (now - prev) / 1000); prev = now;
    clock += dt;
    if (vis.bestiary) paintBestiary(clock);
    if (vis.lairs) paintLairs(clock);
    requestAnimationFrame(loop);
  }

  // ---------------- Depth rail ----------------
  const sections = [...document.querySelectorAll('main > section[data-depth]')];
  const rail = { fill: $('railFill'), read: $('railRead'), num: $('railNum'), ticks: $('railTicks') };
  let anchors = [], maxScroll = 1;
  function measure() {
    maxScroll = Math.max(1, document.documentElement.scrollHeight - innerHeight);
    anchors = sections.map((sec) => ({ y: sec.getBoundingClientRect().top + scrollY, d: sec.dataset.depth, mark: sec.dataset.mark }));
  }
  function layoutRail() {
    measure();
    rail.ticks.innerHTML = anchors.filter((a) => a.mark).map((a) => `<div class="rail-tick" style="top:${Math.min(100, (Math.max(0, a.y - 72) / maxScroll) * 100)}%"><span>${a.mark}</span></div>`).join('') +
      '<div class="rail-tick" style="top:100%"><span>∞</span></div>';
    updateRail();
  }
  function updateRail() {
    // Sections move whenever the page height changes (filter, fork, report), so measure every time.
    measure();
    const f = Math.min(1, scrollY / maxScroll);
    rail.fill.style.height = `${f * 100}%`;
    rail.read.style.top = `${f * 100}%`;
    const probe = scrollY + 80;
    let depth = 1;
    for (let i = 0; i < anchors.length; i++) {
      const a = anchors[i], b = anchors[i + 1];
      if (probe < a.y) break;
      if (a.d === '∞') { depth = '∞'; break; }
      if (!b) { depth = +a.d; break; }
      if (probe >= b.y) continue;
      const k = (probe - a.y) / (b.y - a.y);
      // Past the lairs the depth keeps going: circles continue toward the Echo of the Deep.
      depth = Math.floor(+a.d + (b.d === '∞' ? 60 : +b.d - +a.d) * k);
      break;
    }
    if (scrollY >= maxScroll - 4) depth = '∞';
    rail.num.textContent = depth;
  }
  let railQueued = false;
  addEventListener('scroll', () => { if (!railQueued) { railQueued = true; requestAnimationFrame(() => { railQueued = false; updateRail(); }); } }, { passive: true });
  addEventListener('resize', () => { layoutRail(); if (reduced) paintStatic(); });
  addEventListener('load', layoutRail);
  if ('ResizeObserver' in window) new ResizeObserver(() => layoutRail()).observe(document.querySelector('main'));
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(layoutRail);

  // ---------------- Buttons ----------------
  $('heroSend').addEventListener('click', () => RM.sendMercenary());
  $('endSend').addEventListener('click', () => RM.sendMercenary());

  select(selected);
  showSlot(1);
  brand();
  layoutRail();
  paintStatic();
  if (!reduced) requestAnimationFrame((t) => { prev = t; loop(t); });
})();
