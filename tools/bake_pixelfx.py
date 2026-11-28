# pixelfx(tools/pixelfx — patch-gg/pixelfx, MIT) 효과를 스프라이트 시트로 굽는다 → assets/pixel_fx/<이름>.png + .json
# 효과 목록·색 묶음은 tools/pixelfx_bake.json. 효과 1화소 = 그림 1도트(게임이 세계 1/32유닛으로 띄운다).
# 사용: python3 tools/bake_pixelfx.py [이름 ...]   (없으면 전부)   필요: Node 18+
import json, os, re, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(ROOT, "tools", "pixelfx")
DST = os.path.join(ROOT, "assets", "pixel_fx")
IMPORT = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n'


def palettes():
    src = open(os.path.join(PFX, "src", "core", "color.js"), encoding="utf-8").read()
    return {m.group(1): re.findall(r'"(#[0-9a-fA-F]+)"', m.group(2)) for m in re.finditer(r'^\s+(\w+): \[([^\]]*)\]', src, re.M)}


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def postprocess(path, ramp, clean):
    # clean: 반투명 빛무리(알파 반 미만) 지우고 나머지는 불투명 — 빛은 게임의 화면 빛 층이 맡는다
    # ramp: 밝기 순서대로 색 계단 5단에 끼운다(gradient map — 모양·명암은 그대로, 색은 우리 그림 색)
    im = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64)
    a = im[..., 3]
    solid = a >= 128 if clean else a > 0
    if ramp is not None and solid.any():
        L = (im[..., :3] @ np.array([0.299, 0.587, 0.114]))
        lo, hi = np.percentile(L[solid], [3, 99])
        u = np.clip((L - lo) / max(hi - lo, 1.0), 0, 0.999)
        idx = np.minimum((u * 5).astype(int), 4)
        cols = np.stack([hexrgb(h) for h in ramp])
        im[..., :3] = np.where(solid[..., None], cols[idx], im[..., :3])
    if clean:
        im[..., 3] = np.where(solid, 255, 0)
    Image.fromarray(im.round().astype(np.uint8), "RGBA").save(path)


def main():
    cfg = json.load(open(os.path.join(ROOT, "tools", "pixelfx_bake.json"), encoding="utf-8"))
    pal = palettes()
    names = sys.argv[1:] or list(cfg["fx"].keys())
    os.makedirs(DST, exist_ok=True)
    index = {}
    idx_path = os.path.join(DST, "index.json")
    if os.path.exists(idx_path):
        index = json.load(open(idx_path, encoding="utf-8"))
    for name in names:
        spec = cfg["fx"][name]
        opts = dict(spec.get("opts", {}))
        if isinstance(opts.get("palette"), str):
            opts["palette"] = pal[opts["palette"]]
        with tempfile.TemporaryDirectory() as tmp:
            cmd = ["node", "tools/render.mjs", spec["src"], "--sheet", "--no-actor", "--fps", str(spec.get("fps", cfg["fps"])), "--out", tmp]
            if opts:
                cmd += ["--opts", json.dumps(opts)]
            subprocess.run(cmd, cwd=PFX, check=True, stdout=subprocess.DEVNULL)
            base = os.path.join(tmp, spec["src"], spec["src"].split("/")[-1])
            out_png = os.path.join(DST, name + ".png")
            shutil.copy(base + ".png", out_png)
            ours = spec["src"].startswith("duskfall/") or "ground-flames" in spec["src"]
            rp = spec.get("ramp")
            postprocess(out_png, cfg.get("ramps", {}).get(rp, rp) if rp else None, not ours)
            meta = json.load(open(base + ".json", encoding="utf-8"))["meta"]["pixelfx"]
        imp = os.path.join(DST, name + ".png.import")
        if not os.path.exists(imp):
            open(imp, "w").write(IMPORT)
        index[name] = {"src": spec["src"], "fps": meta["fps"], "loop": meta["loop"], "frames": meta["frames"],
            "size": meta["frameSize"], "pivot": meta["pivot"], "columns": meta["columns"]}
        print(name, spec["src"], meta["frames"], "frames", meta["frameSize"])
    json.dump(index, open(idx_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
