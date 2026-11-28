// DuskFall: 냉기 범위 둘레에 솟는 얼음 조각(바닥 판 fx_floor 냉기 고리와 같이 쓴다). 우리 게임 색 계단(물·얼음 색), 빛무리 없이 단계 음영.
// Ice shards for DuskFall's cold area effects: three jagged shards punch up out of the floor, hold with a glint, then crack and
// drop as glittering bits. Flat stepped shading (lit left, shadowed right) in the game's own ice ramp, no soft glow.
import { fit, rand, clamp, smooth, seg } from "../../core/index.js";

export const meta = {
  name: "Ice shard",
  desc: "Three jagged ice shards punch up out of the floor, hold with a glint, then crack and fall apart into glittering bits.",
  tags: ["ice", "cold", "spike", "duskfall", "once"],
  size: [40, 44],
  origin: [20, 38],
  duration: 1.4,
  loop: false,
  fps: 30,
  bg: "ground",
  options: {
    palette: ["#10202e", "#24506e", "#4c8cb0", "#9cd0e6", "#e6f6ff"],
    seed: 3,
  },
};

// shards: x, height, half width, lean
const SHARDS = [[-7, 20, 3.2, -3], [1, 28, 4, 1], [8, 16, 3, 4]];

export function draw(p, t, o) {
  const I = fit(o.palette, 5), S = o.seed;
  const grow = smooth(0, 0.16, t), crack = seg(t, 0.75, 1.1), gone = seg(t, 0.95, 1.4);
  // 바닥 서리는 게임의 바닥 판(fx_floor.gdshader)이 카메라 각도로 그린다 — 여기선 솟는 조각만
  for (let i = 0; i < SHARDS.length; i++) {
    const [x0, h0, w0, lean] = SHARDS[i];
    const h = h0 * grow * (1 - crack * 0.6), w = w0;
    if (h < 1 || gone >= 1) continue;
    const drop = crack * crack * 10;
    // a shard: lit left face, mid, dark right edge, white edge glint
    for (let r = 0; r < h; r++) {
      const u = r / h, half = w * (1 - u), cx = x0 + lean * u, y = -r + drop * u;
      for (let dx = -Math.ceil(half); dx <= Math.ceil(half); dx++) {
        if (Math.abs(dx) > half + 0.3) continue;
        const side = dx / Math.max(half, 0.5);
        let c = side < -0.35 ? I[3] : side > 0.45 ? I[1] : I[2];
        if (dx === Math.round(-half) || (r === Math.floor(h) - 1)) c = I[4];
        if (crack > 0 && rand(S, i, r, dx) < crack * 0.7) continue;  // cracking away
        p.px(cx + dx, y, c);
      }
    }
    // glint running up the lit edge
    const gy = -h * clamp(seg(t, 0.2, 0.55));
    if (t > 0.2 && t < 0.6) p.px(x0 - w * (1 + gy / h) + lean * (-gy / h), gy, I[4]);
  }
  // falling glitter when they break
  if (crack > 0) {
    for (let k = 0; k < 10; k++) {
      const x = (rand(S, k, 1) - 0.5) * 22, y0 = -rand(S, k, 2) * 22, vy = 18 + rand(S, k, 3) * 20;
      const y = Math.min(0, y0 + vy * (t - 0.75) * (t - 0.75) * 6);
      if (rand(S, k, 4) > gone) p.px(x, y, k % 3 ? I[3] : I[4]);
    }
  }
}
