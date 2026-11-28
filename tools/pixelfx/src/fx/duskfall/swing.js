// DuskFall: 무기 공격 자국(캐릭터 크기 — 약 44도트). 강철 색 계단, 빛무리 없이 단계.
// Weapon strike marks sized for DuskFall: slash (a crescent sweep with a trailing smear), thrust (a streak that shoots
// forward with a tip glint), blunt (an impact star and a dust ring), claw (three tearing marks).
import { fit, rand, seg } from "../../core/index.js";

export const meta = {
  name: "Swing",
  desc: "Weapon strike marks: a crescent slash with a trailing smear, a thrust streak with a tip glint, a blunt impact star, or three claw tears.",
  tags: ["melee", "weapon", "duskfall", "once"],
  size: [56, 56],
  origin: [28, 34],
  duration: 0.4,
  loop: false,
  fps: 30,
  bg: "ground",
  options: { palette: ["#1a1c22", "#3a404c", "#6c7486", "#b4bccb", "#eef2f6"], style: "slash", seed: 1 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 5), st = o.style, k = seg(t, 0, 0.4);
  if (st === "slash") {
    // 위 왼쪽에서 아래 오른쪽으로 쓸어내리는 초승달: 앞머리 밝게, 꼬리로 갈수록 어둡게, 끝나면 옅어진다
    const head = Math.min(1, k * 2.4), tail = Math.max(0, k * 2.4 - 0.8);
    for (let s = 0; s <= 40; s++) {
      const u = s / 40;
      if (u > head || u < tail) continue;
      const a = -2.5 + u * 2.4, r = 18, x = Math.cos(a) * r, y = -6 + Math.sin(a) * r * 0.85;
      const age = head - u, c = age < 0.12 ? C[4] : age < 0.3 ? C[3] : C[2];
      // 앞머리는 4도트 두께, 꼬리로 갈수록 가늘게(초승달)
      const th = Math.max(1, Math.round(4 * (1 - age * 1.6)));
      for (let w = 0; w < th; w++) { const f = 1 - w * 0.06; p.px(x * f, y * f + (1 - f) * -6, w === 0 ? c : w === th - 1 ? C[1] : C[2]); }
    }
  } else if (st === "thrust") {
    const len = 26 * Math.min(1, k * 3), fade = seg(k, 0.5, 1);
    for (let x = -14; x < -14 + len; x++) {
      const age = (-14 + len - x) / 26;
      if (age > 1 - fade) continue;
      p.px(x, -4, age < 0.15 ? C[4] : age < 0.4 ? C[3] : C[2]);
      if (age < 0.5) p.px(x, -3, C[2]), p.px(x, -5, C[2]);
    }
    if (k > 0.25 && k < 0.6) { const tx = -14 + len; p.px(tx + 1, -4, C[4]); p.px(tx, -6, C[3]); p.px(tx, -2, C[3]); }
  } else if (st === "blunt") {
    if (k < 0.15) p.circle(0, -4, 4, C[4]);
    const r = 4 + 10 * Math.pow(k, 0.5);
    for (let i = 0; i < 8; i++) {
      const a = i * Math.PI / 4 + 0.2, l = i % 2 ? 0.6 : 1;
      if (k < 0.7) p.line(Math.cos(a) * r * 0.5, -4 + Math.sin(a) * r * 0.5 * 0.8, Math.cos(a) * r * l, -4 + Math.sin(a) * r * l * 0.8, k < 0.3 ? C[4] : C[3]);
    }
    if (k > 0.2 && k < 0.9) p.ellipse(0, 6, 6 + 10 * k, (6 + 10 * k) * 0.4, C[2], (dd) => (dd > 0.85 ? 1 : 0));
  } else {
    for (let i = 0; i < 3; i++) {
      const ox = (i - 1) * 6, d = Math.min(1, k * 3 - i * 0.15), fade = seg(k, 0.55, 1);
      for (let s = 0; s < 18 * d; s++) {
        const age = (18 * d - s) / 18;
        if (age > 1 - fade) continue;
        p.px(ox - 7 + s * 0.8, -14 + s, age < 0.2 ? C[4] : C[3]); if (age < 0.6) p.px(ox - 6 + s * 0.8, -14 + s, C[1]);
      }
    }
  }
}
