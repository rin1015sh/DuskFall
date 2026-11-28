# pixelfx(tools/pixelfx — patch-gg/pixelfx, MIT) 효과를 스프라이트 시트로 굽는다 → assets/pixel_fx/<이름>.png + .json
# 효과 목록·색 묶음은 tools/pixelfx_bake.json. 효과 1화소 = 그림 1도트(게임이 세계 1/32유닛으로 띄운다).
# 사용: python3 tools/bake_pixelfx.py [이름 ...]   (없으면 전부)   필요: Node 18+
import json, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(ROOT, "tools", "pixelfx")
DST = os.path.join(ROOT, "assets", "pixel_fx")
IMPORT = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n'


def palettes():
    src = open(os.path.join(PFX, "src", "core", "color.js"), encoding="utf-8").read()
    return {m.group(1): re.findall(r'"(#[0-9a-fA-F]+)"', m.group(2)) for m in re.finditer(r'^\s+(\w+): \[([^\]]*)\]', src, re.M)}


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
            shutil.copy(base + ".png", os.path.join(DST, name + ".png"))
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
