// DuskFall: 바닥 불 표면(칸 하나 = 32도트)용 낮은 불꽃. pixelfx의 불 혀·불씨(_lib, Sprite Fusion fire — MIT, Hugo Duprez)로 만든다.
// Low flames for a burning floor tile in DuskFall: five short tongues across one 32-px tile that rise and fall out of step,
// a scorch glow on the floor, embers drifting up. The tongue and ember recipes come from ./_lib.js (Sprite Fusion fire, MIT).
import { fit, mix, WHITE, clamp } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, looped, drift, ember, floorLight, flicker, BIG_LAYERS } from "./_lib.js";

export const meta = {
  name: "Ground flames",
  desc: "A burning floor tile: five short flame tongues spread across one tile, rising and falling out of step, a scorched glow on the floor and embers drifting up.",
  tags: ["fire", "surface", "ground", "burning", "loop"],
  size: [48, 44],
  origin: [24, 37],
  duration: 2,
  loop: true,
  fps: 30,
  bg: "ground",
  options: {
    palette: ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
    seed: 5,
  },
};

const D = meta.duration, NL = noiseFor(D);
// tongues: x across the tile, base height, half width
const TONGUES = [[-13, 9, 2.2], [-7, 15, 3], [-1, 19, 3.4], [5, 13, 2.8], [11, 8, 2.4], [15, 5, 1.6]];

export function draw(p, t, o) {
  const F = fit(o.palette, 9), H = hotFirst(F), S = o.seed;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const fl = flicker(N, S);
  const GLOW = mix(H[3], WHITE, 0.2);
  floorLight(p, 0, 0, 18, 4, GLOW, 0.32 * fl);
  p.glow(0, -6, 20 * fl, H[3], 0.3 * fl);
  // back row a step cooler and lower, then the front tongues
  for (let i = 0; i < TONGUES.length; i++) {
    const [x, h0, w] = TONGUES[i];
    const rise = 0.4 + 0.6 * (0.5 + 0.5 * N(1.5, S + i * 7));  // 혀마다 따로 솟았다 잦아든다
    const h = h0 * rise * fl;
    const sway = N(1, S + 40 + i) * 1.6;
    flameTongue(p, x + N(0.5, S + 60 + i) * 0.8, 0, h, w, sway, N, S * 13 + i * 5, H, BIG_LAYERS, 0.5, 1.0);  // 흰 심이 작은 층(바닥이 하얗게 뜨지 않게)
  }
  // embers drifting up off the flames
  looped(t, D, 7, S + 200, (r) => ({ x: r.range(-13, 13), vx: r.range(-3, 3), vy: -r.range(12, 20), life: r.range(0.8, 1.4), ph: r.range(0, 6.3), s: r.range(0.7, 1.1) }), (q, age) => {
    const [x, y] = drift(q.x, -6, q.vx, q.vy, age, 2, -4, 1, 1);
    ember(p, x, y, clamp(1 - age / q.life), q.s, [H[1], H[3], H[5]], q.ph);
  });
}
