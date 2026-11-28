// DuskFall: 맞는 자리 원소 터짐(캐릭터 몸 크기 — 지름 약 40도트). 색 계단 5단(palette, 어두움 → 밝음), 빛무리 없이 단계 음영.
// An elemental hit burst sized for DuskFall's characters: a 2-frame flash, then elements fly out by style —
// spark (fire), shard (cold), bolt (lightning), drop (acid/poison), wisp (necrotic), ray (radiant/crit), ring (thunder/force), rune (arcane).
import { fit, rand, clamp, seg } from "../../core/index.js";

export const meta = {
  name: "Hit burst",
  desc: "A small elemental hit: a short flash, then sparks, shards, forks, drops, wisps, rays, rings or runes fly out and fade.",
  tags: ["impact", "hit", "elemental", "duskfall", "once"],
  size: [56, 56],
  origin: [28, 34],
  duration: 0.6,
  loop: false,
  fps: 30,
  bg: "ground",
  options: { palette: ["#2a1410", "#5a2414", "#a8401c", "#ec8a34", "#ffd88a"], style: "spark", radius: 18, seed: 2 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 5), S = o.seed, R = o.radius, st = o.style;
  const k = seg(t, 0, 0.6);
  // flash: 둥근 빛(2장) → 링
  // 번쩍: 네 갈래 별(둥근 공이 아니라) → 다음 장 링
  if (t < 0.1) {
    const L = R * (t < 0.04 ? 0.5 : 0.7);
    p.line(-L, -2, L, -2, C[4]); p.line(0, -2 - L * 0.8, 0, -2 + L * 0.8, C[4]);
    p.line(-L * 0.4, -2 - L * 0.32, L * 0.4, -2 + L * 0.32, C[3]); p.line(-L * 0.4, -2 + L * 0.32, L * 0.4, -2 - L * 0.32, C[3]);
    p.circle(0, -2, 2, C[4]);
  } else if (t < 0.17) p.ring(0, -2, R * 0.45, 1, C[3]);
  const n = st === "ray" ? 8 : st === "ring" ? 0 : st === "rune" ? 6 : 12;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + rand(S, i) * 0.6, sp = 0.6 + rand(S, i, 1) * 0.5;
    const d = R * sp * Math.pow(k, 0.55), ca = Math.cos(a), sa = Math.sin(a) * 0.8;
    const x = ca * d, y = -2 + sa * d, life = 0.5 + rand(S, i, 2) * 0.4;
    if (k > life) continue;
    const c = k < life * 0.35 ? C[4] : k < life * 0.7 ? C[3] : C[2];
    if (st === "spark") {
      p.line(x - ca * 4, y - sa * 4, x, y, k < life * 0.5 ? C[3] : C[2]); p.px(x, y, c);
      if (k > 0.3) p.px(x, y + k * 4, C[2]);  // 떨어지는 불씨
    } else if (st === "shard") {
      p.line(x - ca * 2, y - sa * 2, x + ca, y + sa, C[3]); p.px(x + ca * 2, y + sa * 2, C[4]); p.px(x - sa, y + ca, C[2]);
    } else if (st === "bolt") {
      let px0 = 0, py0 = -2;
      for (let s = 1; s <= 3; s++) {
        const dd = d * s / 3, j = (rand(S, i, s, Math.floor(t * 20)) - 0.5) * 4;
        const x1 = ca * dd - sa * j, y1 = -2 + sa * dd + ca * j;
        p.line(px0, py0, x1, y1, s === 1 ? C[4] : c);
        px0 = x1; py0 = y1;
      }
    } else if (st === "drop") {
      const yy = y + k * k * 18;  // 튀었다 떨어진다
      p.rect(x, yy - 1, 2, 2, C[3]); p.px(x, yy - 1, c);
    } else if (st === "wisp") {
      const yy = y - k * 10, wx = x + Math.sin(k * 8 + i) * 2;
      p.px(wx, yy, c); p.px(wx, yy + 1, C[1]);
    } else if (st === "ray") {
      const d0 = R * 0.25 + d * 0.3;
      p.line(ca * d0, -2 + sa * d0, x * 1.1, y * 1.1, c);
    } else if (st === "rune") {
      p.rect(x - 1, y - 1, 3, 3, C[2]); p.px(x, y, c);
    }
  }
  if (st === "ring" || st === "rune") {
    const r1 = R * Math.pow(k, 0.5);
    if (k < 0.85) p.ellipse(0, -2, r1, r1 * 0.78, k < 0.4 ? C[4] : C[3], (dd) => (dd > 0.86 ? 1 : 0));
    if (st === "ring" && k > 0.15 && k < 0.95) { const r2 = r1 * 0.6; p.ellipse(0, -2, r2, r2 * 0.78, C[2], (dd) => (dd > 0.8 ? 1 : 0)); }
  }
}
