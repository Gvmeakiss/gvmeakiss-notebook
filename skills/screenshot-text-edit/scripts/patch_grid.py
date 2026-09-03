#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
patch_grid.py —— 在参考截图上批量替换「列表/表格」数据区

典型场景：用户给一张系统界面的列表截图 + 一份 Excel/CSV，
要求"把这张图里的清单内容换成这份数据"。

做法：以参考图为底板（其余像素原样保留），只擦除列表区并重绘。
绝不自作主张放大、锐化、模糊或压缩——清晰度以参考图为准。

步骤：先用 locate.py / analyze.py 实测下面这些参数。

用法:
    python3 patch_grid.py --ref 界面.png --data 数据.csv --out 结果.png \
        --head-top 148 --data-top 169 --erase-bottom 1080 --row-h 19 --font-size 12

    # 查看某字号下的建议列宽（检查长标题是否会溢出压到下一列）
    python3 patch_grid.py --measure 数据.csv --font-size 12
"""
import argparse
import csv
import sys
from collections import Counter

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("缺少依赖: pip install pillow")

CN_FONT_CANDIDATES = (
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
)

# 数值型列右对齐（按列名匹配，可按需扩展）
NUM_HINTS = ("数量", "金额", "净价", "净价值", "总计", "合计", "号码", "代码",
             "编号", "凭证", "订单号", "项目", "单价", "余额", "数量(基本计量单位)")


def load_font(size):
    for p in CN_FONT_CANDIDATES:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


def is_num_col(name):
    return any(h in name for h in NUM_HINTS)


def measure(csv_path, font_size):
    """输出各列在指定字号下的标题宽/数据宽/建议列宽，用于检查溢出"""
    img = Image.new("RGB", (8, 8))
    d = ImageDraw.Draw(img)
    f = load_font(font_size)
    with open(csv_path, encoding="utf-8-sig") as fh:
        rows = list(csv.reader(fh))
    hdr, body = rows[0], rows[1:]
    print("%-36s %8s %8s %10s" % ("列标题", "标题宽", "数据宽", "建议列宽"))
    total = 0
    for i, h in enumerate(hdr):
        tw = d.textlength(h, font=f)
        dw = max([d.textlength(str(r[i]), font=f) for r in body] or [0])
        w = int(max(tw, dw)) + 18
        total += w
        print("%-36s %8.0f %8.0f %10d" % (h, tw, dw, w))
    print("\n内容总宽约 %dpx（不含左起始偏移）" % total)
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="参考图上批量替换列表数据区",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref")
    ap.add_argument("--data")
    ap.add_argument("--out")
    ap.add_argument("--head-top", type=int, help="列标题行上沿 y")
    ap.add_argument("--data-top", type=int, help="首行数据上沿 y")
    ap.add_argument("--erase-bottom", type=int,
                    help="擦除下界（必须盖住原数据最后一行，否则底部会残留）")
    ap.add_argument("--draw-bottom", type=int, help="绘制下界（留出状态栏空间）")
    ap.add_argument("--row-h", type=int, default=19)
    ap.add_argument("--font-size", type=int, default=12)
    ap.add_argument("--x0", type=int, default=11, help="首列左起始 x")
    ap.add_argument("--measure", help="只测量列宽，传 CSV 路径")
    args = ap.parse_args()

    if args.measure:
        return measure(args.measure, args.font_size)

    for k in ("ref", "data", "out", "head_top", "data_top", "erase_bottom"):
        if getattr(args, k) is None:
            ap.error("缺少 --%s（先用 locate.py/analyze.py 实测）" % k.replace("_", "-"))
    draw_bottom = args.draw_bottom or args.erase_bottom - 4

    im = Image.open(args.ref).convert("RGB")
    W, H = im.size
    d = ImageDraw.Draw(im)
    px = im.load()
    print("参考图 %dx%d，按原尺寸输出（不做缩放/锐化/模糊）" % (W, H))

    # 背景色：区域内颜色频率众数（四角易落在网格线上，不可靠）
    cnt = Counter()
    for y in range(args.head_top, args.erase_bottom, 2):
        for x in range(int(W * 0.75), W - 2, 2):
            cnt[px[x, y]] += 1
    bg = cnt.most_common(1)[0][0]
    print("背景色: %s" % (bg,))

    d.rectangle([0, args.head_top, W, args.erase_bottom], fill=bg)
    print("已擦除列表区 y %d~%d" % (args.head_top, args.erase_bottom))

    with open(args.data, encoding="utf-8-sig") as f:
        rows = list(csv.reader(f))
    header, body = rows[0], rows[1:]
    font = load_font(args.font_size)

    # 列宽按实际渲染宽度算，避免长标题溢出压到下一列
    widths = []
    for i, h in enumerate(header):
        tw = d.textlength(h, font=font)
        dw = max([d.textlength(str(r[i]), font=font) for r in body[:120]] or [0])
        widths.append(int(max(tw, dw)) + 18)

    xs, x = [], args.x0
    for w in widths:
        xs.append(x)
        x += w
    print("列起点: %s   内容右边界 %d / 图宽 %d" % (xs, xs[-1] + widths[-1], W))
    if xs[-1] + widths[-1] > W:
        print("   ⚠ 内容超出图宽，右侧列会被截断——考虑缩小字号或减少列")

    # 列标题
    for h, hx in zip(header, xs):
        d.text((hx + 2, args.head_top + 3), h, font=font, fill=(0, 0, 0))

    # 数据行
    y, shown = args.data_top, 0
    for r in body:
        if y + args.font_size + 2 > draw_bottom:
            break
        for v, hx, h, w in zip(r, xs, header, widths):
            if is_num_col(h):
                tx = hx + w - d.textlength(v, font=font) - 4   # 数值右对齐
            else:
                tx = hx + 2
            d.text((tx, y), v, font=font, fill=(0, 0, 0))
        y += args.row_h
        shown += 1

    print("绘制 %d 行（数据共 %d 行，超出可视区截断）" % (shown, len(body)))
    im.save(args.out)
    print("✓ 已保存: %s (%dx%d)" % (args.out, W, H))
    return 0


if __name__ == "__main__":
    sys.exit(main())
