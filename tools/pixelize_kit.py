# 던전 에셋 키트 → 도트 그림 변환(assets/dungeon_kit/*.webp → assets/pixel_kit/*.webp).
# 1칸 64px 그림을 1칸 32도트로: 조각(kit.json frames)마다
#   1) 쿠와하라 필터(경계는 살리고 붓 터치·작은 점을 넓은 색 덩어리로)
#   2) 2×2 평균으로 반 크기(미리 곱한 알파) → 알파는 반 넘으면 불투명, 옅은 어두운 반투명(드리운 그림자)은
#      그림자 한 단계(SHADOW_A), 나머지는 투명(가장자리 반투명 없음)
#   3) 살짝 색 다듬기(채도 조금 올리고 어두운 쪽은 푸르게·밝은 쪽은 따뜻하게)
#   4) 시트마다 k-평균(Oklab) 팔레트로 색 줄이기
#   5) 외톨이 점(같은 색 이웃이 없는 점) 지우기 — 가장 많은 이웃 색으로
#   6) 2배 가장 가까운 점 확대로 원래 크기(게임 코드의 좌표·크기 그대로, 2×2 화소 = 1도트)
# 바닥·벽처럼 이어 까는 시트는 조각 가장자리를 둘러 감아(wrap) 처리해 이음매가 생기지 않게 한다.
# 사용: python3 tools/pixelize_kit.py [시트 이름 ...]   (없으면 전부)   필요: numpy, Pillow
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "dungeon_kit")
DST = os.path.join(ROOT, "assets", "pixel_kit")
WRAP = {"floors", "wall_faces", "wall_tops", "cliff_drops"}
COLORS = {"floors": 48, "wall_faces": 32, "wall_tops": 24}  # 그 밖 40
SHADOW_A = 0.45
SHADOW_RGB = np.array([0.04, 0.035, 0.06])
KUWAHARA_R = 2
rng = np.random.default_rng(7)


def to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(l):
    l = np.clip(l, 0, 1)
    return np.where(l <= 0.0031308, 12.92 * l, 1.055 * l ** (1 / 2.4) - 0.055)


M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])


def oklab(rgb):
    return np.cbrt(to_lin(rgb) @ M1.T) @ M2.T


def from_oklab(lab):
    return to_srgb(((lab @ np.linalg.inv(M2).T) ** 3) @ np.linalg.inv(M1).T)


def integral(a):
    s = np.zeros((a.shape[0] + 1, a.shape[1] + 1) + a.shape[2:])
    s[1:, 1:] = a.cumsum(0).cumsum(1)
    return s


def box(s, y0, x0, h, w):
    # 적분 영상 s에서 (y0..y0+h, x0..x0+w) 창의 합 — y0·x0은 배열
    return s[y0 + h, x0 + w] - s[y0, x0 + w] - s[y0 + h, x0] + s[y0, x0]


def kuwahara(rgba, r, wrap):
    # 미리 곱한 RGBA에 4사분면 쿠와하라. 분산은 밝기 + 알파로 잰다.
    h, w, _ = rgba.shape
    p = np.pad(rgba, ((r, r), (r, r), (0, 0)), mode="wrap" if wrap else "edge")
    lum = (p[..., :3] @ np.array([0.299, 0.587, 0.114])) + p[..., 3]
    S, S2, SC = integral(lum), integral(lum * lum), integral(p)
    yy, xx = np.mgrid[0:h, 0:w]
    n = (r + 1) * (r + 1)
    best_v = np.full((h, w), np.inf)
    out = np.zeros_like(rgba)
    for dy in (0, r):
        for dx in (0, r):
            y0, x0 = yy + dy, xx + dx  # 패드 좌표: 창 왼쪽 위 = (y + dy, x + dx), 크기 r+1
            m = box(S, y0, x0, r + 1, r + 1) / n
            v = box(S2, y0, x0, r + 1, r + 1) / n - m * m
            c = box(SC, y0, x0, r + 1, r + 1) / n
            better = v < best_v
            best_v = np.where(better, v, best_v)
            out[better] = c[better]
    return out


def process_frame(img, wrap):
    # img: float RGBA(0~1) 조각 → 반 크기 미리 곱한 RGBA
    h, w, _ = img.shape
    pm = img.copy()
    pm[..., :3] *= pm[..., 3:4]
    k = kuwahara(pm, KUWAHARA_R, wrap)
    h2, w2 = h // 2, w // 2
    k = k[: h2 * 2, : w2 * 2].reshape(h2, 2, w2, 2, 4).mean((1, 3))
    a = k[..., 3]
    rgb = np.where(a[..., None] > 1e-4, k[..., :3] / np.maximum(a[..., None], 1e-4), 0)
    shadow = (a > 0.12) & (a <= 0.5) & ((rgb @ np.array([0.299, 0.587, 0.114])) < 0.25)
    out_a = np.where(a > 0.5, 1.0, np.where(shadow, SHADOW_A, 0.0))
    return np.concatenate([np.clip(rgb, 0, 1), out_a[..., None]], -1)


def grade(lab):
    # 채도 조금 올리고 어두운 쪽은 푸르게, 밝은 쪽은 따뜻하게(도트 그림 색 계단 느낌)
    lab = lab.copy()
    lab[..., 1:] *= 1.08
    t = np.clip((lab[..., 0] - 0.55) / 0.35, -1, 1)
    chroma = np.clip(np.hypot(lab[..., 1], lab[..., 2]) / 0.04, 0, 1)  # 회색·흰색은 색을 틀지 않는다
    lab[..., 1] += 0.004 * t * chroma
    lab[..., 2] += 0.014 * t * chroma
    return lab


def kmeans(L, k, it=25):
    q = np.round(L / np.array([0.015, 0.01, 0.01])).astype(np.int64)
    keys, inv, cnt = np.unique(q, axis=0, return_inverse=True, return_counts=True)
    inv = inv.ravel()
    U = np.zeros((len(keys), 3))
    np.add.at(U, inv, L)
    U /= cnt[:, None]
    w = cnt ** 0.6
    k = min(k, len(U))
    C = U[rng.choice(len(U), k, replace=False, p=w / w.sum())]
    for _ in range(it):
        d = ((U[:, None, :] - C[None]) ** 2 * np.array([2.0, 1, 1])).sum(-1)
        idx = d.argmin(1)
        for j in range(k):
            m = idx == j
            if m.any():
                C[j] = (U[m] * w[m, None]).sum(0) / w[m].sum()
    return C


def nearest(L, C):
    d = ((L[:, None, :] - C[None]) ** 2 * np.array([2.0, 1, 1])).sum(-1)
    return d.argmin(1)


def cleanup(idx, alpha, wrap, passes=2):
    # 같은 색 8이웃이 하나도 없는 불투명 점 → 이웃에서 가장 많은 색
    h, w = idx.shape
    for _ in range(passes):
        p = np.pad(idx, 1, mode="wrap" if wrap else "edge")
        pa = np.pad(alpha, 1, mode="wrap" if wrap else "constant")
        neigh = [p[1 + dy: 1 + dy + h, 1 + dx: 1 + dx + w] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
        na = [pa[1 + dy: 1 + dy + h, 1 + dx: 1 + dx + w] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
        same = sum(((n == idx) & (a > 0)).astype(int) for n, a in zip(neigh, na))
        lonely = (same == 0) & (alpha > 0)
        if not lonely.any():
            break
        stack = np.stack(neigh, -1)
        valid = np.stack(na, -1) > 0
        ys, xs = np.nonzero(lonely)
        for y, x in zip(ys, xs):
            v = stack[y, x][valid[y, x]]
            if len(v):
                vals, c = np.unique(v, return_counts=True)
                idx[y, x] = vals[c.argmax()]
    return idx


def frames_of(kit, sheet):
    out = set()
    for a in kit["assets"].values():
        if a.get("sheet") != sheet:
            continue
        for v in a.get("variants", {}).values():
            for f in v.get("frames", []):
                out.add(tuple(int(x) for x in f[:4]))
    return sorted(out)


def convert(kit, name):
    spec = kit["sheets"][name]
    src = Image.open(os.path.join(ROOT, spec["path"].replace("res://", ""))).convert("RGBA")
    S = np.asarray(src, dtype=np.float64) / 255
    H, W, _ = S.shape
    wrap = name in WRAP
    small = []
    for (x, y, w, h) in frames_of(kit, name):
        x2, y2 = min(x + w, W), min(y + h, H)
        if x2 - x < 2 or y2 - y < 2:
            continue
        small.append(((x, y, x2 - x, y2 - y), process_frame(S[y:y2, x:x2], wrap)))
    if not small:
        return
    # 시트 팔레트
    samples = np.concatenate([f[..., :3][f[..., 3] > 0.99] for _, f in small])
    if len(samples) > 400000:
        samples = samples[rng.choice(len(samples), 400000, replace=False)]
    C = kmeans(grade(oklab(samples)), COLORS.get(name, 40))
    pal = np.clip(from_oklab(C), 0, 1)
    out = np.zeros_like(S)
    for (x, y, w, h), f in small:
        alpha = f[..., 3]
        lab = grade(oklab(f[..., :3].reshape(-1, 3)))
        idx = nearest(lab, C).reshape(alpha.shape)
        solid = (alpha > 0.99).astype(float)
        idx = cleanup(idx, solid, wrap)
        rgb = np.where((alpha > 0.99)[..., None], pal[idx], SHADOW_RGB)
        rgba = np.concatenate([rgb, alpha[..., None]], -1)
        big = rgba.repeat(2, 0).repeat(2, 1)
        bh, bw = min(big.shape[0], h), min(big.shape[1], w)
        out[y:y + bh, x:x + bw] = big[:bh, :bw]
        # 홀수 크기의 마지막 줄·칸은 옆 줄을 복제
        if bh < h:
            out[y + bh:y + h, x:x + bw] = big[bh - 1:bh, :bw]
        if bw < w:
            out[y:y + h, x + bw:x + w] = out[y:y + h, x + bw - 1:x + bw]
    os.makedirs(DST, exist_ok=True)
    dst = os.path.join(DST, name + ".webp")
    Image.fromarray((out * 255).round().astype(np.uint8), "RGBA").save(dst, lossless=True, quality=100, method=4)
    imp = dst + ".import"
    if not os.path.exists(imp):
        with open(imp, "w") as fh:
            fh.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n')
    print(name, len(small), "frames ->", os.path.relpath(dst, ROOT))


def main():
    kit = json.load(open(os.path.join(SRC, "kit.json")))
    names = sys.argv[1:] or list(kit["sheets"].keys())
    for n in names:
        convert(kit, n)


if __name__ == "__main__":
    main()
