#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
edit.py —— 高保真替换截图中的文字/数字（字形克隆法）

核心思路：不从字体重绘，而是从图里「已有的字」克隆字形来拼新内容。
这与原图同字号同渲染，字形像素级一致，肉眼无痕。

字形来源（按优先级）:
  1. clone        从本图同类文字克隆（数字/拼音等，同行最佳）
  2. clone_light  从反白高亮区克隆（深色背景+浅色文字，如选中的标签页）
  3. render       字体渲染（图中确实没有该字时的最后手段）

用法:
    python3 edit.py shot.png --config edits.json

配置示例见同目录 edits.example.json，或执行:
    python3 edit.py --show-example
"""
import argparse
import json
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("缺少依赖: pip install pillow")

TEXT_T = 400
LIGHT_T = 170

# macOS 上最接近 Windows SAP/ERP 界面中文点阵的字体
DEFAULT_CN_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
DEFAULT_CN_SIZE = 13
DEFAULT_CN_THRESH = 128


def is_dark(r, g, b):
    return (r + g + b) < TEXT_T


def is_light(r, g, b):
    return (r + g + b) / 3.0 > LIGHT_T


def trim(rows):
    """去掉四周空白，返回最小包围矩阵"""
    ys = [i for i, r in enumerate(rows) if any(r)]
    if not ys:
        return []
    xs = [x for x in range(len(rows[0])) for r in rows if r[x]]
    return [[r[x] for x in range(min(xs), max(xs) + 1)] for r in rows[min(ys):max(ys) + 1]]


def ink(rows):
    return sum(sum(r) for r in rows)


# ---------------- 字形获取 ----------------

def glyph_clone(px, x_start, y_top, y_bottom, width, light=False):
    """从原图克隆字形"""
    test = is_light if light else is_dark
    rows = []
    for y in range(y_top, y_bottom + 1):
        rows.append([1 if test(*px[x, y]) else 0 for x in range(x_start, x_start + width)])
    return rows


def glyph_render(ch, font_path, size, thresh, index=0, supersample=4):
    """字体渲染字形（二值化）"""
    S = supersample
    W, H = 60 * S, 30 * S
    img = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(img)
    try:
        f = ImageFont.truetype(font_path, int(round(size * S)), index=index)
    except Exception as e:
        sys.exit("字体加载失败 %s: %s" % (font_path, e))
    d.text((6 * S, 4 * S), ch, font=f, fill=0)
    if S > 1:
        img = img.resize((60, 30), Image.LANCZOS)
    p = img.load()
    return [[1 if p[x, y] < thresh else 0 for x in range(60)] for y in range(30)]


def resolve_glyph(ch, spec, px=None):
    """根据配置解析出一个字的字形矩阵"""
    kind = spec.get("type", "clone")
    if kind == "clone":
        x, yt, yb = spec["x"], spec["y_top"], spec["y_bottom"]
        w = spec.get("width", spec.get("pitch", 8))
        return glyph_clone(px, x, yt, yb, w, light=False)
    if kind == "clone_light":
        x, yt, yb = spec["x"], spec["y_top"], spec["y_bottom"]
        w = spec.get("width", spec.get("pitch", 12))
        return glyph_clone(px, x, yt, yb, w, light=True)
    if kind == "render":
        return glyph_render(
            ch,
            spec.get("font", DEFAULT_CN_FONT),
            spec.get("size", DEFAULT_CN_SIZE),
            spec.get("threshold", DEFAULT_CN_THRESH),
            spec.get("index", 0),
            spec.get("supersample", 4),
        )
    sys.exit("未知字形类型: %s" % kind)


# ---------------- 主流程 ----------------

EXAMPLE = {
    "_comment": "字段名说明见 SKILL.md；坐标用 locate.py + analyze.py 测得",
    "output": "edited.png",
    "edits": [
        {
            "name": "行项目净价 9.17 -> 10",
            "x": 776,
            "bottom": 397,
            "old_len": 4,
            "new": "10",
            "pitch": 8,
            "bg": [234, 237, 240],
            "glyph_y": [386, 400],
            "glyphs": {
                "1": {"type": "clone", "x": 210, "width": 8},
                "0": {"type": "clone", "x": 218, "width": 8}
            }
        },
        {
            "name": "抬头字段名 净价值 -> 总金额",
            "x": 329,
            "bottom": 158,
            "old_len": 3,
            "new": "总金额",
            "pitch": 12,
            "bg": [255, 255, 255],
            "glyph_y": [147, 158],
            "glyphs": {
                "总": {"type": "clone_light", "x": 109, "y_top": 256, "y_bottom": 273, "width": 13},
                "金": {"type": "render"},
                "额": {"type": "render"}
            }
        }
    ]
}


def main():
    ap = argparse.ArgumentParser(
        description="截图文字高保真替换（字形克隆法）",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", nargs="?", help="输入图片")
    ap.add_argument("--config", help="JSON 编辑配置")
    ap.add_argument("--out", help="输出路径（覆盖配置中的 output）")
    ap.add_argument("--show-example", action="store_true", help="打印配置示例")
    ap.add_argument("--dry-run", action="store_true", help="只打印将要执行的操作，不写文件")
    args = ap.parse_args()

    if args.show_example:
        print(json.dumps(EXAMPLE, ensure_ascii=False, indent=2))
        return
    if not args.image or not args.config:
        ap.error("需要 <image> 和 --config（或 --show-example）")

    with open(args.config, encoding="utf-8") as f:
        cfg = json.load(f)

    im = Image.open(args.image).convert("RGB")
    px = im.load()
    W, H = im.size
    out_path = args.out or cfg.get("output", "edited.png")

    print("=" * 78)
    print("输入: %s (%dx%d)   输出: %s" % (args.image, W, H, out_path))
    print("=" * 78)

    for ed in cfg["edits"]:
        name = ed.get("name", "未命名")
        x_start = ed["x"]
        bottom = ed["bottom"]
        pitch = ed["pitch"]
        old_len = ed.get("old_len", len(ed["new"]))
        new_text = ed["new"]
        bg = tuple(ed["bg"]) if ed.get("bg") else None
        g_y = ed.get("glyph_y")

        print("\n【%s】 %s" % (name, "（跳过：--dry-run）" if args.dry_run else ""))
        print("   位置 x=%d 底部 y=%d  步进 %d  原 %d 字符 → 新 %d 字符"
              % (x_start, bottom, pitch, old_len, len(new_text)))

        # 解析字形
        glyphs = {}
        for ch in set(new_text):
            spec = ed["glyphs"].get(ch)
            if spec is None:
                sys.exit("   ✗ 字符 %r 缺少字形定义" % ch)
            s = dict(spec)
            if "y_top" not in s and g_y:
                s["y_top"], s["y_bottom"] = g_y
            if "width" not in s:
                s["width"] = pitch
            g = trim(resolve_glyph(ch, s, px))
            if not g:
                sys.exit("   ✗ 字符 %r 提取到空字形，请检查坐标" % ch)
            glyphs[ch] = g
            print("   字形 %r  %-12s %dx%d 墨迹%d"
                  % (ch, s.get("type", "clone"), len(g[0]), len(g), ink(g)))

        if args.dry_run:
            continue

        # 擦除：宽度按原字符数，高度按字形高度
        gh = max(len(g) for g in glyphs.values())
        gy0 = bottom - gh + 1
        cur = x_start
        for i in range(old_len):
            for y in range(gy0, bottom + 1):
                for x in range(cur, min(cur + pitch, W)):
                    if 0 <= x < W and 0 <= y < H:
                        px[x, y] = bg
            cur += pitch
        print("   擦除 x %d~%d  y %d~%d  背景 %s" % (x_start, cur, gy0, bottom, bg))

        # 粘贴：每个字底部对齐到 bottom
        for i, ch in enumerate(new_text):
            g = glyphs[ch]
            h = len(g)
            y0 = bottom - h + 1
            tx = x_start + i * pitch
            for j, row in enumerate(g):
                for k, v in enumerate(row):
                    if v:
                        X, Y = tx + k, y0 + j
                        if 0 <= X < W and 0 <= Y < H:
                            px[X, Y] = (0, 0, 0)
        print("   写入 x %d~%d" % (x_start, x_start + pitch * len(new_text)))

    if not args.dry_run:
        im.save(out_path)
        print("\n✓ 已保存: %s" % out_path)
    else:
        print("\n(dry-run，未写入)")


if __name__ == "__main__":
    main()
