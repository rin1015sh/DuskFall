# 몬스터 도트 그림 직접 그리기(새 그림) → assets/pixel_monsters/<원본 그림 이름>.webp
# 변환본(assets/pixel_actors)보다 먼저 쓴다(actor_view). 규격: 그림 1화소 = 화면 1도트, 키 = 42 × 크기 배율(작은 = 34),
# 발바닥은 그림 아래에서 4도트 위(actor_view의 발 기준), 앞쪽 대각선(오른쪽 아래를 봄) — 왼쪽은 게임이 좌우 반전.
# 그리기: 부위를 도형(타원·다각형·굵은 선)으로 잡고, 도형마다 입체 법선(타원 = 공, 막대 = 원통)으로 북서쪽 빛을 받아
#   재질 색 계단(4단)으로 끊는다 → 바깥 1도트 테두리 + 재질 경계 어두운 선 → 눈·이빨 같은 세부는 점으로 찍는다.
# 캐릭터 도트 그림(cutout_rig 도트 모드)·지형 장식과 같은 빛 방향·테두리 규칙.
# 사용: python3 tools/draw_monsters.py   필요: numpy, Pillow
import math, os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "pixel_monsters")
LIGHT = np.array([-0.55, -0.6, 0.58])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# 재질 색 계단: [그늘, 어둠, 본색, 밝음] (+ 테두리용 가장 어두운 색)
RAMPS = {
    "skin": ["#2f4a1f", "#4f7428", "#77a03a", "#a6c95a"],
    "skin_b": ["#3a3f1c", "#5d6a2a", "#86933c", "#b4bd62"],  # 두목: 누런 녹색
    "leather": ["#2e1d14", "#4a2f1e", "#6b4429", "#8e6038"],
    "cloth": ["#4a3a2a", "#6e5a40", "#927a58", "#b49c74"],
    "metal": ["#3a3e46", "#626872", "#9097a2", "#c8ced6"],
    "rust": ["#3e2a1e", "#6a4426", "#93603a", "#b88552"],
    "wood": ["#3a2414", "#5a3a20", "#7a5230", "#9a6c40"],
    "gold": ["#5a3a10", "#8f6418", "#c8962a", "#f0cf62"],
    "bone": ["#6a5e48", "#9a8c6c", "#c8bc98", "#ece2c4"],
    "red": ["#4a1414", "#7a2020", "#a8302a", "#d0503c"],
}
OUTLINE = {k: None for k in RAMPS}


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


class Sprite:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.mat = np.full((h, w), "", dtype=object)
        self.lit = np.zeros((h, w))  # 빛 받은 정도(0~1)
        self.pri = np.zeros((h, w), dtype=int)  # 그린 순서(경계선은 뒤에 있는 쪽에)
        self.n = 0
        self.dots = []  # 세부 점(색 직접)

    def _mask(self, draw_fn):
        m = Image.new("L", (self.w, self.h), 0)
        draw_fn(ImageDraw.Draw(m))
        return np.asarray(m) > 0

    def _put(self, mask, mat, litfn):
        self.n += 1
        ys, xs = np.nonzero(mask)
        for y, x in zip(ys, xs):
            self.mat[y, x] = mat
            self.lit[y, x] = litfn(x + 0.5, y + 0.5)
            self.pri[y, x] = self.n

    def ellipse(self, cx, cy, rx, ry, mat, bias=0.0):
        mask = self._mask(lambda d: d.ellipse([cx - rx, cy - ry, cx + rx - 1, cy + ry - 1], fill=255))
        def lit(x, y):
            nx, ny = (x - cx) / rx, (y - cy) / ry
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            return float(np.dot([nx, ny, nz], LIGHT)) + bias
        self._put(mask, mat, lit)

    def limb(self, pts, width, mat, bias=0.0):
        # 굵은 선(원통): 선에 수직인 쪽으로 법선
        mask = self._mask(lambda d: (d.line(pts, fill=255, width=width), [d.ellipse([p[0] - width / 2 + 0.5, p[1] - width / 2 + 0.5, p[0] + width / 2 - 0.5, p[1] + width / 2 - 0.5], fill=255) for p in pts]))
        segs = list(zip(pts[:-1], pts[1:]))
        def lit(x, y):
            best, bn = 1e9, (0.0, 0.0)
            for (ax, ay), (bx, by) in segs:
                vx, vy = bx - ax, by - ay
                L2 = vx * vx + vy * vy or 1.0
                t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / L2))
                px, py = ax + vx * t, ay + vy * t
                d = math.hypot(x - px, y - py)
                if d < best:
                    best, bn = d, (x - px, y - py)
            r = max(width / 2, 0.5)
            nx, ny = bn[0] / r, bn[1] / r
            nz = math.sqrt(max(0.0, 1 - min(1.0, nx * nx + ny * ny)))
            return float(np.dot([nx, ny, nz], LIGHT)) + bias
        self._put(mask, mat, lit)

    def poly(self, pts, mat, bias=0.0, curve=0.35):
        # 다각형(옷·칼날): 평평하되 가운데에서 바깥으로 살짝 둥글게
        mask = self._mask(lambda d: d.polygon(pts, fill=255))
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        rx, ry = max((max(xs) - min(xs)) / 2, 1), max((max(ys) - min(ys)) / 2, 1)
        def lit(x, y):
            nx, ny = (x - cx) / rx * curve, (y - cy) / ry * curve
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            return float(np.dot([nx, ny, nz], LIGHT)) + bias
        self._put(mask, mat, lit)

    def dot(self, x, y, col):
        self.dots.append((x, y, col))

    def render(self):
        img = np.zeros((self.h, self.w, 4), dtype=np.uint8)
        solid = self.mat != ""
        for y in range(self.h):
            for x in range(self.w):
                m = self.mat[y, x]
                if not m:
                    continue
                ramp = RAMPS[m]
                v = self.lit[y, x]
                k = 3 if v > 0.86 else (2 if v > 0.55 else (1 if v > 0.22 else 0))
                c = hexc(ramp[k])
                # 재질 경계: 뒤에 있는(먼저 그린) 쪽 화소를 어둡게 — 부위가 겹친 자리에 선
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < self.h and 0 <= xx < self.w and solid[yy, xx] and self.pri[yy, xx] > self.pri[y, x] and self.mat[yy, xx] != m:
                        c = hexc(ramp[0]) * 0.8
                        break
                img[y, x, :3] = c.clip(0, 255)
                img[y, x, 3] = 255
        # 바깥 테두리 1도트: 이웃 재질의 그늘 색을 더 어둡게
        out = img.copy()
        for y in range(self.h):
            for x in range(self.w):
                if solid[y, x]:
                    continue
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < self.h and 0 <= xx < self.w and solid[yy, xx]:
                        out[y, x, :3] = (hexc(RAMPS[self.mat[yy, xx]][0]) * 0.45).clip(0, 255)
                        out[y, x, 3] = 255
                        break
        for x, y, col in self.dots:
            if 0 <= x < self.w and 0 <= y < self.h:
                out[y, x, :3] = hexc(col)
                out[y, x, 3] = 255
        return out


# ---------- 고블린 ----------
# 작은 크기: 키 34(발바닥은 아래에서 4도트 위 → 줄 29), 앞쪽 대각선(오른쪽을 봄). 큰 머리·뾰족한 귀·구부정한 몸.

def goblin_body(s, skin="skin", tunic="leather", loin="cloth"):
    # 뒤쪽 다리·팔(먼 쪽)
    s.limb([(12, 22), (11, 26), (11, 28)], 3, skin, -0.15)
    s.ellipse(11, 29, 2.2, 1.2, "leather", -0.2)  # 먼 발
    s.limb([(10, 15), (8, 19), (8, 22)], 3, skin, -0.2)  # 먼 팔
    s.ellipse(8, 23, 1.6, 1.6, skin, -0.2)
    # 몸통(구부정) + 허리 천
    s.poly([(9, 14), (17, 13), (19, 18), (17, 22), (10, 22), (8, 18)], tunic)
    s.poly([(10, 21), (17, 21), (16, 25), (13, 26), (11, 24)], loin, -0.05)
    s.limb([(9, 21), (17, 21)], 1, "leather", 0.1)  # 허리띠
    # 앞쪽 다리
    s.limb([(15, 23), (16, 26), (16, 28)], 3, skin)
    s.ellipse(17, 29, 2.6, 1.3, "leather")  # 앞 발(오른쪽으로)
    # 머리: 먼 귀 → 머리 → 앞 귀
    s.poly([(10, 7), (3, 3), (5, 6), (9, 10)], skin, -0.15, 0.6)
    s.ellipse(13.5, 9, 6, 6, skin)  # 머리(턱까지 한 덩어리)
    s.poly([(17, 5), (25, 1), (23, 5), (18, 9)], skin, 0.05, 0.6)
    s.poly([(17, 8), (21, 10), (19, 11), (17, 11)], skin, 0.1, 0.5)  # 매부리코


def goblin_face(s, eye="#f2d23a"):
    ink = "#1a2010"
    s.dot(14, 8, eye); s.dot(15, 8, ink)  # 앞 눈(노란 눈 + 눈동자)
    s.dot(11, 8, eye); s.dot(12, 8, ink)  # 먼 눈
    s.dot(14, 7, ink); s.dot(15, 7, ink); s.dot(16, 6, ink)  # 찌푸린 눈썹
    s.dot(11, 7, ink)
    s.dot(20, 10, "#c8e07a")  # 코끝 빛
    s.dot(13, 12, ink); s.dot(14, 12, ink); s.dot(15, 12, ink); s.dot(16, 11, ink)  # 비죽 웃는 입
    s.dot(14, 13, "#ece2c4"); s.dot(16, 12, "#ece2c4")  # 송곳니


def goblin():
    s = Sprite(28, 34)
    goblin_body(s)
    # 앞 팔: 녹슨 단검을 아래로
    s.limb([(17, 15), (20, 18), (21, 21)], 3, "skin", 0.05)
    s.ellipse(21, 22, 1.7, 1.7, "skin")
    s.limb([(21, 23), (23, 24), (26, 26)], 2, "metal", 0.1)  # 녹슨 칼날
    s.dot(24, 25, "#93603a")
    s.limb([(20, 22), (22, 22)], 1, "wood")
    goblin_face(s)
    return s


def goblin_swordsman():
    s = Sprite(28, 34)
    goblin_body(s, tunic="leather", loin="red")
    # 먼 손 방패(둥근 나무 방패)
    s.ellipse(7, 20, 3.4, 4, "wood", 0.05)
    s.dot(6, 19, "#c8ced6")
    # 투구(쇠 사발)
    s.ellipse(13.5, 5.5, 6.2, 3.4, "metal", 0.1)
    s.limb([(8, 7), (19, 7)], 1, "metal", -0.1)
    # 앞 팔: 굽은 칼(언월도)을 위로
    s.limb([(17, 15), (20, 17), (22, 15)], 3, "skin", 0.05)
    s.ellipse(22, 14, 1.7, 1.7, "skin")
    s.limb([(22, 13), (23, 9), (25, 5), (27, 3)], 2, "metal", 0.15)  # 칼날
    s.limb([(21, 14), (23, 14)], 1, "gold")  # 코등이
    goblin_face(s, "#f0a030")
    return s


def goblin_trap_king():
    s = Sprite(30, 34)
    goblin_body(s, skin="skin_b", tunic="red", loin="leather")
    # 망토 깃(어깨 털)
    s.ellipse(13, 14.5, 5, 1.6, "bone", -0.1)
    # 왕관(삐뚤어진 금관)
    s.poly([(9, 5), (18, 4), (18, 1), (16, 3), (14, 0), (12, 3), (10, 1), (9, 4)], "gold", 0.1, 0.4)
    s.dot(14, 2, "#d0503c")
    # 앞 팔: 덫 갈고리 창(긴 자루)
    s.limb([(17, 15), (20, 18), (22, 17)], 3, "skin_b", 0.05)
    s.ellipse(22, 17, 1.8, 1.8, "skin_b")
    s.limb([(23, 28), (23, 3)], 1, "wood", 0.1)
    s.poly([(22, 3), (26, 1), (24, 4), (27, 6), (23, 6)], "metal", 0.15, 0.3)  # 갈고리 날
    goblin_face(s, "#ff6a30")
    return s


ART = {"goblin": goblin, "goblin_swordsman": goblin_swordsman, "goblin_trap_king": goblin_trap_king}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ART.items():
        img = fn().render()
        dst = os.path.join(OUT, name + ".webp")
        Image.fromarray(img, "RGBA").save(dst, lossless=True, quality=100, method=4)
        imp = dst + ".import"
        if not os.path.exists(imp):
            with open(imp, "w") as fh:
                fh.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n')
        print(name, img.shape[1], "x", img.shape[0])


if __name__ == "__main__":
    main()
