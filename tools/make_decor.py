# 바닥 장식 도트 그림(새 그림) 만들기 → assets/pixel_decor/decor.png + kit.json(던전 키트와 같은 형식).
# 1칸 32도트 규격: 도트 단위로 그린 뒤 2배 확대(2×2 화소 = 1도트, 키트 px_per_tile 64와 같은 좌표).
# 색은 도트 변환한 바닥(assets/pixel_kit/floors.webp)의 풀·돌 색에서 뽑아 바닥과 어울리게 한다.
# 장식: tuft(풀 덤불 a~f), flowers(꽃 덤불 a~d), pebble(돌멩이 a~c), leaf(잎 부스러기 a~b — 눕힌 무늬).
# ruin_stone.png: 폐허 벽 윗돌 블록 재질(돌·이끼 — map_view._ruin_cap).
# 사용: python3 tools/make_decor.py   필요: numpy, Pillow
import json, os, random
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "pixel_decor")
R = random.Random(11)


def ramp_from(sheet, rect, n):
    # 그림 영역의 색을 밝기순으로 n단계(분위수 평균)
    x, y, w, h = rect
    a = np.asarray(sheet.crop((x, y, x + w, y + h)).convert("RGB"), dtype=float).reshape(-1, 3)
    lum = a @ np.array([0.299, 0.587, 0.114])
    order = np.argsort(lum)
    chunks = np.array_split(a[order], n)
    return [tuple(int(v) for v in c.mean(0)) for c in chunks]


def shade(c, k):
    return tuple(int(max(0, min(255, v * k))) for v in c)


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


floors = Image.open(os.path.join(ROOT, "assets", "pixel_kit", "floors.webp"))
GRASS = ramp_from(floors, (1280, 1280, 512, 256), 6)  # ground_meadow a·b
COBBLE = ramp_from(floors, (1024, 0, 512, 256), 6)
G_OUT = shade(GRASS[0], 0.55)
G = [GRASS[1], GRASS[2], GRASS[3], mix(GRASS[4], (225, 230, 140), 0.25), mix(GRASS[5], (240, 240, 170), 0.35)]
S_OUT = shade(COBBLE[0], 0.6)
S = [COBBLE[1], COBBLE[3], COBBLE[4], mix(COBBLE[5], (235, 230, 215), 0.3)]
PETALS = [((236, 226, 186), (196, 176, 128)), ((226, 196, 92), (176, 136, 52)), ((206, 150, 168), (150, 96, 120)), ((170, 170, 214), (112, 110, 160))]


def canvas(w, h):
    return np.zeros((h, w, 4), dtype=np.uint8)


def put(img, x, y, c):
    h, w, _ = img.shape
    if 0 <= x < w and 0 <= y < h:
        img[y, x, :3] = c
        img[y, x, 3] = 255


def outline_bottom(img, col):
    # 바닥에 닿는 아래쪽·옆 가장자리에만 어두운 테(위로 솟은 잎끝은 테 없이 밝게)
    h, w, _ = img.shape
    a = img[..., 3] > 0
    out = img.copy()
    for y in range(h):
        for x in range(w):
            if a[y, x]:
                continue
            nb = [(x, y - 1), (x - 1, y), (x + 1, y)]
            if any(0 <= nx < w and 0 <= ny < h and a[ny, nx] and ny >= h * 0.45 for nx, ny in nb):
                out[y, x, :3] = col
                out[y, x, 3] = 255
    return out


def tuft(w, h, blades, dark=False):
    # 끝이 뾰족한 잎(밑동 2~3도트 → 끝 1도트)을 겹친 덤불. 아래는 어둡고 위로 갈수록 밝게, 잎 왼쪽 가장자리는 빛.
    img = canvas(w + 4, h + 2)
    base_y = h
    cx = (w + 4) / 2
    order = list(range(blades))
    order.sort(key=lambda i: abs(i - (blades - 1) / 2), reverse=True)  # 바깥 잎 먼저, 가운데 잎이 앞에
    for i in order:
        t = (i + 0.5) / blades
        bx = cx + (t - 0.5) * w * 0.7 + R.uniform(-0.5, 0.5)
        lean = (t - 0.5) * R.uniform(2.0, 3.2) + R.uniform(-0.5, 0.5)
        bh = h * R.uniform(0.6, 1.0) * (1.0 - abs(t - 0.5) * 0.7)
        wb = R.choice([2, 2, 3])
        rows = max(3, int(round(bh)))
        for r in range(rows):
            f = r / (rows - 1)
            width = max(1, int(round(wb * (1.0 - f) + 0.3)))
            xc = bx + lean * f * f * 1.6
            y = base_y - r
            k = min(4, int(f * 4.8))
            if dark:
                k = max(0, k - 1)
            x0 = int(round(xc - width / 2))
            for dx in range(width):
                c = G[k]
                if dx == 0 and width > 1:
                    c = G[min(4, k + 1)]
                elif dx == width - 1 and width > 1:
                    c = G[max(0, k - 1)]
                put(img, x0 + dx, y, c)
    # 밑동 아래 한 줄 그늘(가운데만, 옅게)
    a = img[..., 3] > 0
    xs = [x for x in range(img.shape[1]) if a[base_y, x]]
    if xs:
        lo, hi = xs[0], xs[-1]
        for x in xs:
            if lo < x < hi:
                put(img, x, base_y + 1, G[0])
    return img


def flowers(w, h, n, petal):
    img = tuft(w, h, max(3, w // 3))
    pc, ps = petal
    for _ in range(n):
        for _try in range(20):
            x = R.randrange(1, img.shape[1] - 2)
            y = R.randrange(0, max(1, img.shape[0] - 4))
            if img[y + 1, x, 3] > 0 or y < 2:
                put(img, x, y, pc)
                put(img, x + 1, y, pc)
                put(img, x, y + 1, ps)
                put(img, x + 1, y + 1, pc)
                break
    return img


def pebbles(n):
    img = canvas(14, 7)
    for i in range(n):
        w = R.randint(3, 5)
        h = R.randint(2, 3)
        x0 = 1 + i * 4 + R.randint(0, 1)
        y0 = 6 - h - R.randint(0, 1)
        for y in range(h):
            for x in range(w):
                if (x in (0, w - 1)) and (y in (0, h - 1)) and w > 3:
                    continue  # 모서리 둥글게
                c = S[2] if y == 0 else (S[1] if y < h - 1 else S[0])
                if y == 0 and x == 1:
                    c = S[3]
                put(img, x0 + x, y0 + y, c)
        for x in range(w):  # 아래 그늘
            put(img, x0 + x, y0 + h, S_OUT)
    return img


def leaves(n):
    img = canvas(16, 12)
    cols = [mix(G[1], (120, 90, 40), 0.5), mix(G[2], (150, 110, 50), 0.45), mix(G[0], (90, 60, 30), 0.4)]
    for _ in range(n):
        x, y = R.randrange(1, 14), R.randrange(1, 10)
        c = R.choice(cols)
        put(img, x, y, c)
        put(img, x + 1, y, c)
        if R.random() < 0.5:
            put(img, x, y + 1, shade(c, 0.75))
    return img


def ruin_stone():
    # 폐허 벽 윗돌 재질(64×32도트 = 가로 2칸): 왼쪽 칸 = 돌(결 무늬만 — 줄눈 없이, 블록 그물이 돌 모양을 만든다), 오른쪽 칸 = 이끼.
    # 둘 다 이어 깔아도 이음매 없는 잔무늬라 세계 좌표로 입혀도 반복이 드러나지 않는다.
    N = 32
    img = np.zeros((N, 2 * N, 4), dtype=np.uint8)
    img[..., 3] = 255
    yy, xx = np.mgrid[0:N, 0:N] / N * 2 * np.pi
    def pn(seed, f):
        r = random.Random(seed)
        v = np.zeros((N, N))
        for k in range(f):
            a, b = r.randint(1, 4), r.randint(1, 4)
            v += np.sin(a * xx + b * yy * r.choice([1, -1]) + r.uniform(0, 6.28)) / (k + 1)
        return v
    # 얼룩 덩어리(2~4도트)를 둘러 감아 찍는다 — 줄무늬 없는 돌결·이끼결
    def blobs(x0, base, cols, count):
        img[:, x0:x0 + N, :3] = base
        for _ in range(count):
            cx, cy, r = R.randrange(N), R.randrange(N), R.choice([1, 1, 2, 2, 3])
            c = R.choice(cols)
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if dx * dx + dy * dy <= r * r + R.choice([0, 1]):
                        img[(cy + dy) % N, x0 + (cx + dx) % N, :3] = c
    blobs(0, S[2], [S[1], S[1], S[3], mix(S[2], S[1], 0.5)], 70)
    blobs(N, G[2], [G[1], G[1], G[3], G[3], G[4]], 80)
    return img


def crop_alpha(img):
    a = img[..., 3] > 0
    ys, xs = np.nonzero(a)
    return img[: ys.max() + 1, xs.min(): xs.max() + 1]


ART = {
    "tuft": {"layer": "stand", "v": {"a": tuft(9, 7, 6), "b": tuft(13, 9, 9), "c": tuft(6, 6, 4), "d": tuft(11, 8, 8, dark=True), "e": tuft(17, 12, 12), "f": tuft(20, 13, 15, dark=True)}},
    "flowers": {"layer": "stand", "v": {"a": flowers(10, 6, 3, PETALS[0]), "b": flowers(12, 7, 4, PETALS[1]), "c": flowers(9, 6, 3, PETALS[2]), "d": flowers(9, 6, 3, PETALS[3])}},
    "pebble": {"layer": "stand", "v": {"a": pebbles(2), "b": pebbles(3), "c": pebbles(1)}},
    "leaf": {"layer": "decal", "v": {"a": leaves(7), "b": leaves(11)}},
}


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for aid, a in ART.items():
        for vn, img in a["v"].items():
            tiles.append((aid, vn, crop_alpha(img)))
    # 한 줄로 붙인다(도트 단위, 1도트 띄움) → 2배 확대
    W = sum(t[2].shape[1] + 1 for t in tiles) + 1
    H = max(t[2].shape[0] for t in tiles) + 2
    sheet = np.zeros((H, W, 4), dtype=np.uint8)
    assets = {}
    x = 1
    for aid, vn, img in tiles:
        h, w, _ = img.shape
        sheet[1:1 + h, x:x + w] = img
        # 원점(발) = 아래 가운데. 눕힌 무늬는 가운데.
        layer = ART[aid]["layer"]
        oy = h * 2 - 2 if layer == "stand" else h
        assets.setdefault(aid, {"sheet": "decor", "layer": layer, "cat": "decor", "tags": ["decor", "pixel"], "variants": {}})
        assets[aid]["variants"][vn] = {"frames": [[x * 2, 2, w * 2, h * 2, float(w), float(oy)]]}
        x += w + 1
    big = sheet.repeat(2, 0).repeat(2, 1)
    Image.fromarray(big, "RGBA").save(os.path.join(OUT, "decor.png"))
    stone = ruin_stone().repeat(2, 0).repeat(2, 1)
    Image.fromarray(stone, "RGBA").save(os.path.join(OUT, "ruin_stone.png"))
    kit = {
        "_comment": "바닥 장식 도트 그림(tools/make_decor.py가 만든다 — 손으로 고치지 않는다). 던전 키트와 같은 형식.",
        "version": 1, "px_per_tile": 64, "depth_k": 0.72,
        "sheets": {"decor": {"path": "res://assets/pixel_decor/decor.png", "size": [big.shape[1], big.shape[0]]}},
        "assets": assets,
    }
    with open(os.path.join(OUT, "kit.json"), "w") as f:
        json.dump(kit, f, ensure_ascii=False, indent=1)
    for name in ("decor.png", "ruin_stone.png"):
        imp = os.path.join(OUT, name + ".import")
        if not os.path.exists(imp):
            with open(imp, "w") as f:
                f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n')
    print("decor:", len(tiles), "그림", big.shape[1], "x", big.shape[0])


if __name__ == "__main__":
    main()
