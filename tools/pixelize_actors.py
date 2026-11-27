# 몬스터 그림 → 도트 그림(assets/actors/... → assets/pixel_actors/<이름>.webp). 원본은 같은 이름의 큰 그림(assets/monsters — 에셋팩 반실사 원화)을 쓴다.
# 화면 키 = actor_view.BODY_PX(84px) × 크기 배율(SIZE_K). 변환본은 키 84 × 배율 화소로 만들어 그림 1화소 = 화면 1px
# = 지형 도트의 절반(몬스터만 촘촘한 도트 — 2026-11-27 결정, 도트 화면 버퍼가 그 절반 크기로 그린다).
# 순서: 목표 도트 크기로 축소(큰 원본은 2배 축소 → 쿠와하라 → 2×2 평균, 테두리 1도트 자리 남김) → 대비 키우기(평균 밝기 유지)·채도 조금 올림
#   (작고 밝은 강조색 — 눈·보석·불빛 — 은 축소해도 살린다) → 명암 테(왼쪽 위 밝게·오른쪽 아래 어둡게, 북서쪽 빛) → 그림마다 k-평균 팔레트(Oklab) → 바깥 1도트 테두리(그 몬스터의 가장 어두운 색)
#   → 알파는 반 넘으면 불투명(반투명 가장자리 없음). 외톨이 점 지우기는 하지 않는다(작고 가는 그림의 세부 선이 얼룩이 된다).
# 같은 그림을 크기가 다른 몬스터가 쓰면 가장 큰 크기 기준.
# 사용: python3 tools/pixelize_actors.py   필요: numpy, Pillow
import glob, json, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelize_kit as pk  # 같은 폴더의 키트 변환 도구(쿠와하라·팔레트·외톨이 점)

ROOT = pk.ROOT
DST = os.path.join(ROOT, "assets", "pixel_actors")
DOT_BODY = 84.0  # BODY_PX 84 — 몬스터는 지형 도트보다 2배 촘촘하게(그림 1화소 = 지형 도트 절반 = 확대 1에서 화면 1px)
SIZE_K = {"tiny": 0.5, "small": 0.8, "medium": 1.0, "large": 1.7, "huge": 2.4}
COLORS = 28


HIRES = os.path.join(ROOT, "assets", "monsters")  # 같은 에셋팩의 큰 원본(반실사, 260~600px) — 게임 그림(assets/actors/monsters)은 이걸 작게 줄인 것


def convert(src_res, k):
    src = os.path.join(ROOT, src_res.replace("res://", ""))
    hi = os.path.join(HIRES, os.path.basename(src))
    if os.path.exists(hi):
        src = hi  # 작게 줄여 뭉개진 그림 대신 큰 원본에서
    im = Image.open(src).convert("RGBA")
    th = max(8, int(round(DOT_BODY * k)))
    tw = max(4, int(round(im.width * th / im.height)))
    # 테두리 1도트 자리를 남기고(키는 th 그대로) 목표 도트 크기로 바로 면적 평균(미리 곱한 알파) — 원본이 작은 그림도 많아 늘렸다 줄이지 않는다
    ih, iw = th - 2, max(2, tw - 2)
    a = np.asarray(im, dtype=np.float64) / 255
    a[..., :3] *= a[..., 3:4]
    pre = Image.fromarray((a * 255).round().astype(np.uint8), "RGBA")
    if im.height >= ih * 4:
        # 큰 원본: 2배 크기로 면적 축소 → 쿠와하라(경계 살리고 붓 터치를 덩어리로, 지형 키트와 같은 방식) → 2×2 평균
        big = np.asarray(pre.resize((iw * 2, ih * 2), Image.BOX), dtype=np.float64) / 255
        small = pk.kuwahara(big, 1, False).reshape(ih, 2, iw, 2, 4).mean((1, 3))
    else:
        small = np.asarray(pre.resize((iw, ih), Image.BOX), dtype=np.float64) / 255
    # 강조색 살리기: 원본에서 밝고 진한 점(눈·보석·불빛 — Oklab 채도 0.08↑, 밝기 0.55↑)이 축소 칸을 15% 넘게 덮으면 그 칸은 강조색 평균으로
    src_a = np.asarray(im, dtype=np.float64) / 255
    slab = pk.oklab(np.clip(src_a[..., :3], 0, 1).reshape(-1, 3)).reshape(src_a.shape[0], src_a.shape[1], 3)
    acc = (np.hypot(slab[..., 1], slab[..., 2]) > 0.08) & (slab[..., 0] > 0.55) & (src_a[..., 3] > 0.5)
    if acc.any():
        cov = np.asarray(Image.fromarray((acc * 255).astype(np.uint8)).resize((iw, ih), Image.BOX), dtype=np.float64) / 255
        accrgb = np.zeros_like(src_a[..., :3]); accrgb[acc] = src_a[..., :3][acc]
        sumc = np.stack([np.asarray(Image.fromarray((accrgb[..., i] * 255).astype(np.uint8)).resize((iw, ih), Image.BOX), dtype=np.float64) / 255 for i in range(3)], -1)
        hit = (cov > 0.15) & (small[..., 3] > 0.3)
        small[..., :3] = np.where(hit[..., None], np.clip(sumc / np.maximum(cov[..., None], 1e-3), 0, 1) * small[..., 3:4], small[..., :3])
    sm = np.zeros((th, tw, 4))
    sm[1:1 + ih, 1:1 + iw] = small
    al = sm[..., 3]
    rgb = np.where(al[..., None] > 1e-4, sm[..., :3] / np.maximum(al[..., None], 1e-4), 0)
    solid = al > 0.5
    lab = pk.oklab(np.clip(rgb, 0, 1).reshape(-1, 3)).reshape(th, tw, 3)
    # 1) 대비: 평균 밝기는 지키고(어두운 몬스터는 어둡게) 밝기 폭만 키운다(5~95% 폭을 0.5까지, 최대 1.8배) + 살짝 밝게,
    #    채도 조금 올림 — 흐린 칠한 원본이 작게 줄면 바탕에 묻힌다
    L = lab[..., 0]
    lo, hi = np.percentile(L[solid], [5, 95]) if solid.any() else (0.0, 1.0)
    mean = float(L[solid].mean()) if solid.any() else 0.5
    gain = float(np.clip(0.5 / max(hi - lo, 1e-3), 1.0, 1.8))
    lab[..., 0] = np.where(solid, np.clip(mean + 0.04 + (L - mean) * gain, 0.05, 0.95), L)
    lab[..., 1:] *= 1.3
    # 2) 명암 테(북서쪽 빛): 윤곽 안쪽 왼쪽 위 1도트는 밝게, 오른쪽 아래 1도트는 어둡게 — 캐릭터 도트 그림과 같은 규칙
    def nb(dy, dx):
        return np.roll(np.roll(solid, dy, 0), dx, 1)
    edge_hi = solid & (~nb(1, 0) | ~nb(0, 1))  # 위나 왼쪽이 비었다
    edge_lo = solid & (~nb(-1, 0) | ~nb(0, -1)) & ~edge_hi  # 아래나 오른쪽이 비었다
    lab[..., 0] = np.where(edge_hi, lab[..., 0] + 0.05, lab[..., 0])  # 가는 몸은 테가 몸 대부분이라 약하게
    lab[..., 0] = np.where(edge_lo, lab[..., 0] - 0.06, lab[..., 0])
    flat = lab.reshape(-1, 3)
    C = pk.kmeans(flat[solid.reshape(-1)], COLORS)
    pal = np.clip(pk.from_oklab(C), 0, 1)
    idx = pk.nearest(flat, C).reshape(th, tw)
    out = np.concatenate([pal[idx], solid[..., None].astype(float)], -1)
    # 3) 바깥 테두리 1도트: 그림의 가장 어두운 색을 더 어둡게(검정 대신 그 몬스터 색)
    ring = ~solid & (nb(1, 0) | nb(-1, 0) | nb(0, 1) | nb(0, -1))
    dark = pal[np.argmin(C[:, 0])] * 0.45
    out[ring] = np.concatenate([dark, [1.0]])
    os.makedirs(DST, exist_ok=True)
    name = os.path.splitext(os.path.basename(src))[0]
    dst = os.path.join(DST, name + ".webp")
    Image.fromarray((out * 255).round().astype(np.uint8), "RGBA").save(dst, lossless=True, quality=100, method=4)
    imp = dst + ".import"
    if not os.path.exists(imp):
        with open(imp, "w") as fh:
            fh.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n')
    return name, (tw, th)


def main():
    use = {}
    for f in glob.glob(os.path.join(ROOT, "data", "monsters", "*.json")):
        m = json.load(open(f))
        img = m.get("art", {}).get("image")
        if img:
            use[img] = max(use.get(img, 0), SIZE_K.get(m.get("size", "medium"), 1.0))
    for img, k in sorted(use.items()):
        if os.path.exists(os.path.join(ROOT, img.replace("res://", ""))):
            print(*convert(img, k))


if __name__ == "__main__":
    main()
