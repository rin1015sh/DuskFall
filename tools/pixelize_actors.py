# 몬스터 그림 → 도트 그림(assets/actors/... → assets/pixel_actors/<이름>.webp).
# 화면 키 = actor_view.BODY_PX(84px) × 크기 배율(SIZE_K) = 도트 키 42 × 배율. 변환본은 그 도트 키로 만들어
# 그림 1화소 = 화면 1도트(2px)가 되게 한다(actor_view의 배율 공식이 그대로 2가 된다).
# 순서: 목표 도트 크기로 면적 평균 축소(원본이 작은 그림도 많다) → 그림마다 k-평균 팔레트(Oklab, 원래 색 그대로)
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
DOT_BODY = 42.0  # BODY_PX 84 / 화면 1도트 2px
SIZE_K = {"tiny": 0.5, "small": 0.8, "medium": 1.0, "large": 1.7, "huge": 2.4}
COLORS = 28


def convert(src_res, k):
    src = os.path.join(ROOT, src_res.replace("res://", ""))
    im = Image.open(src).convert("RGBA")
    th = max(8, int(round(DOT_BODY * k)))
    tw = max(4, int(round(im.width * th / im.height)))
    # 목표 도트 크기로 바로 면적 평균(미리 곱한 알파) — 원본이 작은 그림도 많아 늘렸다 줄이지 않는다
    a = np.asarray(im, dtype=np.float64) / 255
    a[..., :3] *= a[..., 3:4]
    small = Image.fromarray((a * 255).round().astype(np.uint8), "RGBA").resize((tw, th), Image.BOX)
    sm = np.asarray(small, dtype=np.float64) / 255
    al = sm[..., 3]
    rgb = np.where(al[..., None] > 1e-4, sm[..., :3] / np.maximum(al[..., None], 1e-4), 0)
    solid = al > 0.5
    lab = pk.oklab(np.clip(rgb, 0, 1).reshape(-1, 3))  # 몬스터는 원래 색 그대로(색 다듬기 없음)
    C = pk.kmeans(lab[solid.reshape(-1)], COLORS)
    pal = np.clip(pk.from_oklab(C), 0, 1)
    idx = pk.nearest(lab, C).reshape(th, tw)
    out = np.concatenate([pal[idx], solid[..., None].astype(float)], -1)
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
