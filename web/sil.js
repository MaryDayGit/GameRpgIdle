// Силуэты — порт app/lib/game/silhouettes.dart. Единичные координаты:
// y = 0 под ногами, y = 1 макушка, x от −0.5 до 0.5. Все враги смотрят влево.
(function () {
  const TAU = Math.PI * 2;
  const sin = Math.sin, cos = Math.cos;

  function sketch(ctx, fx, fy, h, t, body, accent) {
    const X = (x) => fx + x * h, Y = (y) => fy - y * h;
    const fill = (a) => (ctx.fillStyle = a ? accent : body);
    return {
      t,
      circle(x, y, r, a) { fill(a); ctx.beginPath(); ctx.arc(X(x), Y(y), Math.max(0.1, r * h), 0, TAU); ctx.fill(); },
      oval(x, y, w, hh, a) { fill(a); ctx.beginPath(); ctx.ellipse(X(x), Y(y), Math.max(0.1, w * h / 2), Math.max(0.1, hh * h / 2), 0, 0, TAU); ctx.fill(); },
      poly(pts, a) {
        fill(a); ctx.beginPath();
        pts.forEach((p, i) => (i ? ctx.lineTo(X(p[0]), Y(p[1])) : ctx.moveTo(X(p[0]), Y(p[1]))));
        ctx.closePath(); ctx.fill();
      },
      limb(x1, y1, x2, y2, w, a) {
        ctx.strokeStyle = a ? accent : body; ctx.lineWidth = Math.max(0.5, w * h); ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(X(x1), Y(y1)); ctx.lineTo(X(x2), Y(y2)); ctx.stroke();
      },
      ring(x, y, o, i, a) {
        fill(a); const cx = X(x), cy = Y(y);
        ctx.beginPath(); ctx.arc(cx, cy, o * h, 0, TAU); ctx.moveTo(cx + i * h, cy); ctx.arc(cx, cy, i * h, 0, TAU);
        ctx.fill('evenodd');
      },
    };
  }

  // --- Мобы ---
  function scavenger(s) {
    s.limb(-0.06, 0.24, -0.16, 0, 0.055); s.limb(0.06, 0.26, 0.02, 0, 0.055); s.limb(0.2, 0.28, 0.26, 0, 0.055);
    s.limb(0.3, 0.44, 0.48, 0.58, 0.035); s.oval(0.06, 0.4, 0.56, 0.4);
    for (let i = 0; i < 3; i++) { const x = -0.06 + i * 0.14; s.poly([[x - 0.05, 0.56], [x, 0.68 - i * 0.03], [x + 0.05, 0.56]]); }
    s.circle(-0.22, 0.44, 0.13);
    s.poly([[-0.28, 0.42], [-0.5, 0.34], [-0.26, 0.34]], true);
    s.circle(-0.24, 0.5, 0.028, true);
  }
  function bonebreaker(s) {
    s.limb(-0.1, 0.34, -0.14, 0, 0.1); s.limb(0.12, 0.34, 0.16, 0, 0.1);
    s.poly([[-0.34, 0.8], [0.34, 0.8], [0.2, 0.32], [-0.2, 0.32]]);
    s.circle(-0.02, 0.9, 0.1);
    s.limb(-0.3, 0.74, -0.44, 0.42, 0.07); s.limb(-0.44, 0.42, -0.5, 0.24, 0.14, true);
  }
  function ashEater(s) {
    const f = sin(s.t * 3.4) * 0.05;
    s.poly([[-0.22, 0], [0.22, 0], [0.12, 0.44 + f], [0.2 + f, 0.78], [0, 0.62], [-0.14 - f, 0.86 + f], [-0.1, 0.4]]);
    s.circle(0.02, 0.34, 0.1, true); s.circle(0.1 + f, 0.94, 0.035, true); s.circle(-0.16, 1.02 - f, 0.025, true);
  }
  function frostWarden(s) {
    s.poly([[-0.2, 0], [0.2, 0], [0.26, 0.7], [0, 0.84], [-0.26, 0.7]]);
    s.poly([[-0.14, 0.84], [0.14, 0.84], [0, 1]]);
    s.poly([[-0.26, 0.66], [-0.44, 0.52], [-0.42, 0.2], [-0.24, 0.14]], true);
    s.limb(0.2, 0.72, 0.34, 0.96, 0.05, true); s.circle(0, 0.88, 0.035, true);
  }
  function voidWhisperer(s) {
    const d = sin(s.t * 1.6) * 0.02, y = (v) => v + d;
    s.poly([[-0.26, y(0.2)], [-0.17, y(0.06)], [-0.08, y(0.22)], [0.02, y(0.02)], [0.12, y(0.22)], [0.22, y(0.08)], [0.26, y(0.24)], [0.18, y(0.62)], [-0.18, y(0.62)]]);
    s.circle(0, y(0.72), 0.15);
    s.poly([[-0.13, y(0.78)], [-0.04, y(1)], [0.1, y(0.8)]]);
    s.circle(-0.05, y(0.72), 0.055, true);
    s.limb(-0.16, y(0.58), -0.34, y(0.4), 0.045); s.circle(-0.36, y(0.38), 0.045, true);
  }
  function bloodLeech(s) {
    const n = 7, seg = (i) => { const k = i / (n - 1); return [0.34 - k * 0.62, 0.09 + sin(k * Math.PI) * 0.44]; };
    for (let i = 1; i < n; i++) { const a = seg(i - 1), b = seg(i); s.limb(a[0], a[1], b[0], b[1], 0.15 - i * 0.008); }
    for (let i = 0; i < n; i++) { const p = seg(i); s.circle(p[0], p[1], 0.095 - i * 0.006); }
    const hd = seg(n - 1); s.ring(hd[0], hd[1], 0.085, 0.042, true);
  }
  function stoneFist(s) {
    s.limb(-0.1, 0.3, -0.14, 0, 0.11); s.limb(0.14, 0.3, 0.18, 0, 0.11);
    s.oval(0.06, 0.52, 0.4, 0.46); s.circle(0.1, 0.86, 0.11);
    s.oval(-0.34, 0.44, 0.44, 0.44, true); s.limb(-0.1, 0.56, -0.26, 0.48, 0.1);
  }
  function rotHowler(s) {
    const f = sin(s.t * 2.6) * 0.04;
    s.limb(-0.06, 0.26, -0.12, 0, 0.07); s.limb(0.1, 0.26, 0.16, 0, 0.07);
    s.oval(0.04, 0.44, 0.34, 0.44); s.circle(-0.16, 0.74, 0.13);
    s.poly([[-0.26, 0.78], [-0.46 - f, 0.72], [-0.46 - f, 0.62], [-0.26, 0.68]], true);
    for (let i = 0; i < 3; i++) s.circle(-0.52 - i * 0.1 - f, 0.7, 0.03 + i * 0.01, true);
  }
  function graveSwarm(s) {
    for (let i = 0; i < 4; i++) {
      const x = -0.28 + i * 0.19, y = 0.1 + (i % 2 === 0 ? 0 : 0.12);
      s.oval(x, y + 0.16, 0.2, 0.16); s.circle(x - 0.1, y + 0.22, 0.055); s.limb(x, y + 0.1, x - 0.02, y, 0.03);
    }
  }
  function cinderling(s) {
    const f = sin(s.t * 5) * 0.05;
    s.limb(-0.06, 0.18, -0.1, 0, 0.035); s.limb(0.08, 0.18, 0.12, 0, 0.035);
    s.circle(0, 0.38, 0.22);
    s.poly([[-0.05, 0.6], [0.02 + f, 0.86 + f], [0.07, 0.6]], true);
    s.circle(-0.1, 0.42, 0.035, true);
  }
  function forgeSmith(s) {
    s.limb(-0.1, 0.3, -0.14, 0, 0.09); s.limb(0.12, 0.3, 0.16, 0, 0.09);
    s.oval(0.02, 0.52, 0.38, 0.44); s.circle(-0.06, 0.86, 0.1);
    s.limb(0.22, 0.62, 0.42, 0.78, 0.05);
    s.poly([[0.34, 0.9], [0.56, 0.9], [0.56, 0.7], [0.34, 0.7]], true);
  }
  function rimeHorror(s) {
    s.limb(-0.16, 0.2, -0.24, 0, 0.05); s.limb(0.02, 0.2, 0.06, 0, 0.05); s.limb(0.2, 0.2, 0.28, 0, 0.05);
    s.oval(0.02, 0.36, 0.62, 0.3); s.circle(-0.3, 0.42, 0.11);
    for (let i = 0; i < 4; i++) { const x = -0.2 + i * 0.16; s.poly([[x - 0.04, 0.5], [x, 0.72 - (i % 2 === 0 ? 0 : 0.08)], [x + 0.04, 0.5]], true); }
  }
  function frostMaw(s) {
    const f = sin(s.t * 2) * 0.05;
    s.limb(-0.08, 0.22, -0.14, 0, 0.07); s.limb(0.1, 0.22, 0.16, 0, 0.07);
    s.oval(0.1, 0.42, 0.4, 0.4);
    s.poly([[-0.1, 0.56], [-0.52, 0.62 + f], [-0.52, 0.34 - f]], true);
    for (let i = 0; i < 3; i++) s.poly([[-0.2 - i * 0.1, 0.56], [-0.24 - i * 0.1, 0.46], [-0.28 - i * 0.1, 0.56]]);
  }
  function sparkling(s) {
    const f = sin(s.t * 6) * 0.03;
    s.poly([[-0.14, 0], [0.02 + f, 0.3], [-0.06, 0.3], [0.14 + f, 0.62], [0, 0.34], [0.08, 0.34]], true);
    s.circle(-0.04, 0.44, 0.1); s.circle(-0.1, 0.48, 0.025, true);
  }
  function stormWarden(s) {
    s.limb(-0.08, 0.3, -0.12, 0, 0.09); s.limb(0.14, 0.3, 0.18, 0, 0.09);
    s.oval(0.1, 0.5, 0.34, 0.44); s.circle(0.04, 0.84, 0.1);
    s.poly([[-0.14, 0.86], [-0.4, 0.7], [-0.4, 0.28], [-0.14, 0.14]], true);
    s.poly([[-0.3, 0.62], [-0.2, 0.5], [-0.28, 0.5], [-0.18, 0.36]]);
  }
  function arcLeech(s) {
    const f = sin(s.t * 4.4) * 0.04;
    s.limb(-0.06, 0.24, -0.12, 0, 0.05); s.limb(0.1, 0.24, 0.16, 0, 0.05);
    for (let i = 0; i < 3; i++) s.oval(0.02, 0.34 + i * 0.16, 0.34 - i * 0.06, 0.12);
    s.circle(-0.14, 0.78, 0.09);
    for (let i = 0; i < 3; i++) s.circle(-0.3 - i * 0.09, 0.74 + f, 0.026, true);
  }
  function voidReaper(s) {
    s.limb(-0.06, 0.24, -0.12, 0, 0.06); s.limb(0.1, 0.24, 0.16, 0, 0.06);
    s.poly([[-0.22, 0.86], [0.22, 0.86], [0.14, 0.24], [-0.14, 0.24]]);
    s.circle(-0.02, 0.9, 0.1); s.limb(0.24, 0.3, 0.28, 0.88, 0.035);
    s.poly([[0.28, 0.88], [-0.02, 1.04], [0.1, 0.84]], true);
  }
  function manaEater(s) {
    const f = sin(s.t * 3) * 0.03;
    s.limb(-0.08, 0.26, -0.14, 0, 0.06); s.limb(0.1, 0.26, 0.16, 0, 0.06);
    s.oval(0.02, 0.46, 0.38, 0.44); s.circle(-0.04, 0.86, 0.1);
    s.oval(-0.16, 0.5 + f, 0.22, 0.22, true); s.circle(-0.34, 0.52, 0.04, true); s.circle(-0.46, 0.54, 0.025, true);
  }
  function riftShade(s) {
    const f = sin(s.t * 2.2) * 0.03;
    s.poly([[-0.24 - f, 0], [-0.06, 0.3], [-0.1, 0.86], [-0.3 - f, 0.56]]);
    s.poly([[0.24 + f, 0], [0.06, 0.3], [0.1, 0.86], [0.3 + f, 0.56]]);
    s.circle(0, 0.62, 0.05, true); s.circle(0, 0.4, 0.03, true);
  }
  // --- Боссы ---
  function ashLord(s) {
    s.poly([[0.11, 0.76], [0.44, 0.36], [0.34, 0.06], [0.2, 0.34]]);
    s.poly([[-0.11, 0.76], [-0.4, 0.38], [-0.3, 0.08], [-0.19, 0.36]]);
    s.poly([[-0.09, 0], [0.09, 0], [0.12, 0.72], [-0.12, 0.72]]);
    s.limb(0, 0.72, 0, 0.8, 0.07); s.circle(0, 0.88, 0.105);
    s.oval(-0.15, 0.72, 0.13, 0.09, true); s.oval(0.15, 0.72, 0.13, 0.09, true); s.limb(-0.1, 0.38, 0.1, 0.38, 0.045, true);
    for (let i = -1; i <= 1; i++) s.poly([[i * 0.075 - 0.032, 0.95], [i * 0.075, 1.06 + (i === 0 ? 0.05 : 0)], [i * 0.075 + 0.032, 0.95]], true);
    s.limb(-0.13, 0.62, -0.28, 0.4, 0.055);
    const e = sin(s.t * 2) * 0.04;
    s.circle(-0.31, 0.38 + e, 0.06, true); s.circle(0.3, 0.92 + e, 0.028, true);
  }
  function voidDevourer(s) {
    for (let i = 0; i < 5; i++) { const k = i / 4, sw = sin(s.t * 1.4 + i) * 0.06; s.limb(-0.3 + k * 0.6, 0.34, -0.44 + k * 0.88 + sw, 0, 0.05); }
    s.ring(0, 0.56, 0.34, 0.17);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU;
      s.poly([[cos(a) * 0.17, 0.56 + sin(a) * 0.17], [cos(a + 0.2) * 0.17, 0.56 + sin(a + 0.2) * 0.17], [cos(a + 0.1) * 0.07, 0.56 + sin(a + 0.1) * 0.07]], true);
    }
  }
  function stormSovereign(s) {
    const f = sin(s.t * 3.6) * 0.03;
    s.limb(-0.12, 0.32, -0.18, 0, 0.1); s.limb(0.16, 0.32, 0.22, 0, 0.1);
    s.poly([[-0.3, 0.84], [0.3, 0.84], [0.18, 0.3], [-0.18, 0.3]]);
    s.circle(-0.02, 0.92, 0.12);
    s.limb(-0.28, 0.78, -0.52, 0.9, 0.05); s.limb(0.28, 0.78, 0.52, 0.9, 0.05);
    for (let i = 0; i < 4; i++) { const x = -0.18 + i * 0.12; s.poly([[x - 0.03, 1.02], [x + 0.02, 1.02 + f], [x + 0.05, 1.02]], true); }
  }
  function frostPatriarch(s) {
    const f = sin(s.t * 1.6) * 0.03;
    s.limb(-0.14, 0.26, -0.2, 0.04, 0.1); s.limb(0.18, 0.26, 0.24, 0.04, 0.1);
    s.poly([[-0.34, 0.76], [0.34, 0.76], [0.2, 0.24], [-0.2, 0.24]]);
    s.circle(0, 0.86, 0.12); s.limb(0.3, 0.18, 0.34, 0.86, 0.04); s.circle(0.34, 0.9, 0.07, true);
    for (let i = 0; i < 3; i++) { const x = -0.26 + i * 0.24; s.poly([[x - 0.05, 0.76], [x, 0.9 + f - i * 0.04], [x + 0.05, 0.76]], true); }
  }
  // --- Герой: смотрит вправо ---
  function hero(s, weapon) {
    s.poly([[-0.1, 0.82], [-0.34, 0.24], [-0.16, 0.06], [-0.06, 0.6]]);
    s.limb(-0.06, 0.34, -0.12, 0, 0.07); s.limb(0.08, 0.34, 0.14, 0, 0.07);
    s.poly([[-0.16, 0.78], [0.16, 0.78], [0.11, 0.32], [-0.11, 0.32]]);
    s.circle(0.02, 0.88, 0.095);
    if (weapon === 'two') { s.limb(-0.26, 0.1, 0.34, 1.02, 0.055, true); s.limb(-0.06, 0.44, 0.1, 0.62, 0.05); }
    else if (weapon === 'shield') { s.limb(0.14, 0.66, 0.26, 0.52, 0.05); s.limb(0.26, 0.48, 0.32, 0.86, 0.04, true); s.oval(-0.18, 0.56, 0.2, 0.34, true); }
    else { s.limb(0.14, 0.66, 0.26, 0.52, 0.05); s.limb(0.26, 0.48, 0.34, 0.92, 0.045, true); }
  }

  const EL = {
    physical: { name: 'Physical', c: '#D6C9B6' },
    fire: { name: 'Fire', c: '#F0874F' },
    cold: { name: 'Cold', c: '#7CC8E6' },
    lightning: { name: 'Lightning', c: '#E8C95A' },
    voidType: { name: 'Void', c: '#B48EF2' },
  };

  const TRAITS = {
    slowsHero: ['Slows', 'Cuts the mercenary’s attack speed.'],
    shredResists: ['Shreds resistances', 'Strips part of your elemental protection for a while.'],
    lifesteal: ['Life leech', 'Heals from the damage it deals.'],
    rampUp: ['Ramp-up', 'Hits harder the longer the fight lasts.'],
    explodesOnDeath: ['Explodes on death', 'Strikes back as it dies — through armor and resistances.'],
    drainsMana: ['Drains mana', 'Takes mana with every hit: a build that lives on active skills loses its next cast.'],
    healsAllies: ['Heals allies', 'While it lives, the rest of the wave keeps getting back up.'],
    reflects: ['Reflects', 'Returns part of the damage — but never harder than its own blow.'],
    hardens: ['Hardens', 'Its armor grows as the fight goes on.'],
  };

  // id: [name, role, damage, resists, traits, hp, dps, attack speed, pack min, max, body, accent, width, draw, note]
  const RAW = [
    ['scavenger', 'Scavenger', 'Fodder', 'physical', {}, [], 0.6, 0.25, 1.4, 3, 5, '#8C6A4A', '#E0C08A', 1.0, scavenger, 'Low, hunched, jaw first. The meat of a wave — you know it because there are five of them.'],
    ['bonebreaker', 'Bonebreaker', 'Tank-damage', 'physical', {}, [], 1.8, 0.75, 0.5, 1, 2, '#9A8B72', '#D9C8A9', 0.92, bonebreaker, 'Shoulders wider than everything else, and a club. You see the heavy blow before it lands.'],
    ['ash_eater', 'Ash Eater', 'Fire', 'fire', { fire: 40, cold: -25 }, [], 0.9, 0.45, 1.0, 2, 4, '#C7643F', '#FFC46B', 0.48, ashEater, 'No body, only flame. The only one that visibly moves even at rest.'],
    ['frost_warden', 'Frost Warden', 'Armor', 'cold', { cold: 40 }, ['slowsHero'], 1.3, 0.35, 0.8, 1, 3, '#5E7E92', '#AEE0F0', 0.82, frostWarden, 'A pillar of armor and a shield. The silhouette promises armor before you see a single number.'],
    ['void_whisperer', 'Void Whisperer', 'Debuffer', 'voidType', { voidType: 35 }, ['shredResists'], 0.8, 0.4, 1.1, 2, 3, '#5B4A78', '#B9A0E8', 0.68, voidWhisperer, 'A hood with no legs. It hovers — the only figure that never touches the ground.'],
    ['blood_leech', 'Blood Leech', 'Scaler', 'physical', {}, ['lifesteal', 'rampUp'], 1.1, 0.4, 1.2, 2, 3, '#8E3A46', '#E0707F', 0.85, bloodLeech, 'A segmented arc, head stretched forward. The longer the fight, the more dangerous it gets.'],
    ['stone_fist', 'Stone Fist', 'Armor', 'physical', { fire: 17.5, lightning: -35 }, ['hardens'], 1.87, 0.504, 0.6, 1, 2, '#7C7468', '#CFC4B0', 1.05, stoneFist, 'One enormous hand. Hitting it with whatever you have is pointless — bring lightning.'],
    ['rot_howler', 'Rot Howler', 'Healer', 'physical', { voidType: 17.5, fire: -30 }, ['healsAllies'], 1.02, 0.216, 1.0, 1, 2, '#6B7A4A', '#BBD08A', 1.17, rotHowler, 'A gaping mouth and waves rolling out of it. While it lives, the pack doesn’t end.'],
    ['grave_swarm', 'Grave Swarm', 'Fodder', 'physical', {}, [], 0.34, 0.144, 1.8, 5, 8, '#6E6154', '#C2B39A', 0.9, graveSwarm, 'Not a figure but a handful of figures. There are always a lot of them.'],
    ['cinderling', 'Cinderling', 'Suicide', 'fire', { fire: 24.5, cold: -40 }, ['explodesOnDeath'], 0.595, 0.36, 1.2, 3, 5, '#D1712F', '#FFE08A', 0.7, cinderling, 'A burning ball on thin legs. You see the fuse before it blows for the first time.'],
    ['forge_smith', 'Ashen Smith', 'Armor', 'fire', { fire: 31.5, cold: -30 }, ['hardens'], 1.36, 0.396, 0.8, 1, 2, '#9A4A2E', '#FFB25B', 0.95, forgeSmith, 'A hammer, and an anvil for a shoulder. It hardens as the fight goes on.'],
    ['rime_horror', 'Rime Horror', 'Debuffer', 'cold', { cold: 28, fire: -35 }, ['slowsHero'], 0.85, 0.288, 0.9, 2, 4, '#6E8FA6', '#CDEBFA', 0.9, rimeHorror, 'Long, creeping, bristling with frost. It slows you — and looks slow itself.'],
    ['frost_maw', 'Frost Maw', 'Scaler', 'cold', { cold: 24.5, lightning: -25 }, ['rampUp'], 1.19, 0.324, 0.8, 1, 3, '#4E6B80', '#B6DCEF', 0.88, frostMaw, 'Almost all jaw. The longer the fight, the wider it opens.'],
    ['sparkling', 'Sparkling', 'Fodder', 'lightning', { lightning: 28, voidType: -30 }, [], 0.425, 0.252, 1.9, 3, 6, '#B89A2E', '#FFF07A', 0.6, sparkling, 'Small, fast, all zigzags. There are many, and they strike with lightning.'],
    ['storm_warden', 'Storm Warden', 'Reflector', 'lightning', { lightning: 31.5, cold: -25 }, ['reflects'], 1.275, 0.36, 0.9, 1, 2, '#7D7A3E', '#FFF3A0', 0.98, stormWarden, 'A shield as tall as the body. It reflects — and the shield says so.'],
    ['arc_leech', 'Arc Leech', 'Silencer', 'lightning', { lightning: 24.5, physical: -20 }, ['drainsMana'], 0.85, 0.288, 1.1, 2, 3, '#8A8340', '#FFEE8C', 0.8, arcLeech, 'A coil for a torso, with arcs coming off it.'],
    ['void_reaper', 'Void Reaper', 'Debuffer', 'voidType', { voidType: 28, lightning: -30 }, ['shredResists'], 1.105, 0.396, 0.9, 1, 3, '#4E3F70', '#C0A4F0', 0.78, voidReaper, 'A scythe and a hood.'],
    ['mana_eater', 'Witherer', 'Silencer', 'voidType', { voidType: 24.5, fire: -25 }, ['drainsMana', 'lifesteal'], 0.935, 0.252, 1.0, 2, 3, '#574670', '#B9A0E8', 0.84, manaEater, 'A funnel where the chest should be.'],
    ['rift_shade', 'Riven Shade', 'Reflector', 'voidType', { voidType: 21, physical: -25 }, ['reflects'], 0.765, 0.324, 1.2, 2, 4, '#433764', '#A98CE0', 0.66, riftShade, 'Two halves with a rift between them.'],
    ['ash_lord', 'Lord of Ash', 'Boss', 'fire', { fire: 40 }, [], 4.0, 0.8, 0.7, 1, 1, '#B4532F', '#FFD08A', 0.85, ashLord, 'Height, a crown and a cloak. A boss has to read by silhouette from the same distance as a regular pack.'],
    ['void_devourer', 'The Void Devourer', 'Boss', 'voidType', { voidType: 40 }, [], 6.5, 1.0, 0.6, 1, 1, '#4A3B6B', '#C7A6FF', 1.05, voidDevourer, 'A maw, not a body. The tentacles move — they are its silhouette.'],
    ['storm_sovereign', 'The Storm Sovereign', 'Boss', 'lightning', { lightning: 45, cold: -25 }, ['drainsMana', 'hardens'], 5.0, 0.9, 0.9, 1, 1, '#9C8F3A', '#FFF6B0', 1.2, stormSovereign, 'A crown of sparks, arms flung wide.'],
    ['frost_patriarch', 'The Frost Patriarch', 'Boss', 'cold', { cold: 50, fire: -30 }, ['slowsHero', 'healsAllies'], 5.5, 0.85, 0.7, 1, 1, '#4A6B84', '#CFEBFF', 1.0, frostPatriarch, 'Broad, crusted with ice, leaning on a staff. Heals its retinue.'],
  ];

  const BEASTS = {};
  const ORDER = [];
  for (const r of RAW) {
    BEASTS[r[0]] = {
      id: r[0], name: r[1], role: r[2], dmg: r[3], res: r[4], traits: r[5], hp: r[6], dps: r[7], as: r[8],
      packMin: r[9], packMax: r[10], body: r[11], accent: r[12], aspect: r[13], draw: r[14], note: r[15],
      boss: r[2] === 'Boss',
    };
    ORDER.push(r[0]);
  }

  // Рисует существо ногами в (fx, fy), ростом h пикселей.
  function drawBeast(ctx, id, fx, fy, h, t, o) {
    const b = BEASTS[id]; if (!b) return;
    o = o || {};
    const body = o.dead ? '#2A2422' : o.flash ? '#FFF1E2' : b.body;
    const accent = o.dead ? '#221D1B' : o.flash ? '#FFFFFF' : b.accent;
    ctx.save(); ctx.globalAlpha = o.alpha == null ? 1 : o.alpha;
    b.draw(sketch(ctx, fx, fy, h, t, body, accent));
    ctx.restore();
  }
  function drawHero(ctx, fx, fy, h, t, o) {
    o = o || {};
    ctx.save(); ctx.globalAlpha = o.alpha == null ? 1 : o.alpha;
    hero(sketch(ctx, fx, fy, h, t, o.dead ? '#2A2422' : o.flash ? '#FFD9CC' : '#D9C8A9', o.dead ? '#221D1B' : (o.accent || '#7FB069')), o.weapon || 'one');
    ctx.restore();
  }

  // Холст под плотность пикселей. Возвращает ширину и высоту в CSS-пикселях.
  function fit(canvas) {
    const r = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.max(1, Math.round(r.width)), h = Math.max(1, Math.round(r.height));
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    }
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w, h };
  }

  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  window.RM = { EL, TRAITS, BEASTS, ORDER, drawBeast, drawHero, fit, reduced };
})();
