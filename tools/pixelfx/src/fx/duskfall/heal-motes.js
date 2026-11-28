// DuskFall: 회복 빛 점. 캐릭터 키(약 50도트)에 맞춘 작은 효과 — 발밑에서 작은 십자·점 빛이 몸을 따라 떠오르다 사라진다.
// Healing motes sized for DuskFall's characters: small crosses and dots of green-gold light rise from the feet up the
// body, twinkle and fade. Stepped colours from the game's heal ramp, no soft glow (the game's light layer adds it).
import { fit, rand, clamp, seg } from "../../core/index.js";

export const meta = {
  name: "Heal motes",
  desc: "Small crosses and dots of soft green light rise from the feet up a character's body, twinkle and fade.",
  tags: ["heal", "holy", "buff", "duskfall", "once"],
  size: [36, 64],
  origin: [18, 58],
  duration: 1.3,
  loop: false,
  fps: 30,
  bg: "ground",
  options: { palette: ["#0e2a1c", "#1e5a34", "#3e9a54", "#86d48a", "#d8f6c8"], seed: 4 },
};

export function draw(p, t, o) {
  const H = fit(o.palette, 5), S = o.seed;
  for (let i = 0; i < 12; i++) {
    const born = rand(S, i, 0) * 0.55, age = t - born;
    if (age < 0) continue;
    const life = 0.55 + rand(S, i, 1) * 0.35;
    const k = age / life;
    if (k >= 1) continue;
    const x = (rand(S, i, 2) - 0.5) * 20 + Math.sin(age * 6 + i) * 1.2;
    const y = -2 - rand(S, i, 3) * 6 - age * (34 + rand(S, i, 4) * 18);
    const c = k < 0.35 ? H[4] : k < 0.7 ? H[3] : H[2];
    if (i % 3 === 0 && k < 0.75) {
      // 작은 십자
      p.px(x, y, c); p.px(x - 1, y, H[3]); p.px(x + 1, y, H[3]); p.px(x, y - 1, H[3]); p.px(x, y + 1, H[3]);
    } else if ((Math.floor(age * 12 + i) & 3) !== 0) {
      p.px(x, y, c);
    }
  }
  // 발밑 짧은 빛 고리(바닥 납작 타원 — 게임 시점 세로 0.78이라 반지름 9×7)
  const g = seg(t, 0, 0.35), f = 1 - seg(t, 0.35, 0.8);
  if (f > 0) p.ellipse(0, 0, 4 + 6 * g, 3 + 4.5 * g, H[3], (d) => (d > 0.8 ? f : 0));
}
