// DuskFall: 작은 상태 이상 고리 효과(캐릭터 머리·몸 둘레, 약 24×40도트). bubbles(중독 — 몸 따라 오르는 거품), wisps(저주 — 검은 연기 가닥),
// flakes(느려짐 — 천천히 내리는 서리 조각), sparks(기절은 pixelfx, 여기선 쓰지 않음). 색 계단 5단.
import { fit, rand, wrap } from "../../core/index.js";

export const meta = {
  name: "Status loop",
  desc: "A small status loop around a character: rising bubbles, curling dark wisps or slowly falling frost flakes.",
  tags: ["status", "duskfall", "loop"],
  size: [32, 56],
  origin: [16, 50],
  duration: 2,
  loop: true,
  fps: 30,
  bg: "ground",
  options: { palette: ["#0e1a0c", "#22401a", "#4a7a26", "#90c040", "#d8f080"], style: "bubbles", seed: 5 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 5), S = o.seed, st = o.style, D = meta.duration;
  const N = st === "flakes" ? 11 : 10;
  for (let i = 0; i < N; i++) {
    const ph = wrap(t / D + rand(S, i), 1), x0 = (rand(S, i, 1) - 0.5) * 18;
    if (st === "bubbles") {
      const y = -4 - ph * 40, x = x0 + Math.sin(ph * 9 + i) * 1.5, r = ph < 0.8 ? 1 : 0;
      if (ph > 0.9) continue;
      if (r) { p.px(x, y, C[3]); p.px(x + 1, y, C[2]); p.px(x, y - 1, C[4]); p.px(x + 1, y - 1, C[3]); } else p.px(x, y, C[4]);
    } else if (st === "wisps") {
      for (let s = 0; s < 5; s++) {
        const pp = ph - s * 0.03; if (pp < 0) continue;
        const y = -6 - pp * 38, x = x0 * 0.7 + Math.sin(pp * 7 + i) * 3;
        p.px(x, y, s === 0 ? C[3] : s < 3 ? C[2] : C[1]);
      }
    } else {
      const y = -48 + ph * 44, x = x0 + Math.sin(ph * 5 + i) * 2;
      if (ph > 0.92) continue;
      p.px(x, y, C[4]); if (i % 2) { p.px(x - 1, y, C[3]); p.px(x + 1, y, C[3]); }
    }
  }
}
