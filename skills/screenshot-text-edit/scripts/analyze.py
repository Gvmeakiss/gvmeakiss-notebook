#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze.py —— 像素级分析：字符边界、步进、背景色、点阵特征

OCR 的文本框常把相邻字段合并，不能直接用来覆盖。
本工具做「列投影」切出逐字符边界，并采样背景色、判断是否为点阵字。

关键：只统计深色文字像素（RGB 和 < 400）。
     若统计「非背景像素」，浅灰网格线（204/229/249）会让每列都有计数，切分失败。

用法:
    # 分析一个区域
    python3 analyze.py shot.png --x0 840 --x1 900 --y0 380 --y1 402

    # 打印字符画，肉眼确认
    python3 analyze.py shot.png --x0 840 --x1 900 --y0 380 --y1 402 --dump

    # 反白区（深色背景 + 浅色文字，如高亮选中的标签页）
    python3 analyze.py shot.png --x0 78 --x1 140 --y0 253 --y1 272 --light

    # 逐字打印（中文字形提取前用）
    python3 analyze.py shot.png --x0 155 --x1 215 --y0 363 --y1 380 --per-char
"""
import argparse
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    sys.exit("缺少依赖: pip install pillow")

TEXT_T = 400      # 深色文字阈值（RGB 三通道之和）
LIGHT_T = 170     # 反白区浅色文字阈值（平均亮度）


def is_dark(r, g, b, threshold=TEXT_T):
    return (r + g + b) < threshold


def is_light(r, g, b, threshold=LIGHT_T):
    return (r + g + b) / 3.0 > threshold


def make_test(light, threshold):
    """返回像素判定函数：True 表示该像素属于「文字」"""
    if light:
        return lambda r, g, b: is_light(r, g, b, LIGHT_T)
    return lambda r, g, b: is_dark(r, g, b, threshold)


def blocks(prof, gap=0):
    """从投影切出连续区间；gap 为允许合并的空隙宽度"""
    out, cur = [], None
    for v, n in prof:
        if n > 0:
            cur = [v, v] if cur is None else [cur[0], v]
        else:
            if cur is not None:
                out.append(tuple(cur)); cur = None
    if cur:
        out.append(tuple(cur))
    merged = []
    for b in out:
        if merged and b[0] - merged[-1][1] <= gap:
            merged[-1] = (merged[-1][0], b[1])
        else:
            merged.append(b)
    return merged


def main():
    ap = argparse.ArgumentParser(
        description="截图像素分析：字符边界 / 步进 / 背景色 / 点阵特征",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("--x0", type=int, required=True)
    ap.add_argument("--x1", type=int, required=True)
    ap.add_argument("--y0", type=int, required=True)
    ap.add_argument("--y1", type=int, required=True)
    ap.add_argument("--light", action="store_true",
                    help="反白区域：文字为浅色，背景为深色")
    ap.add_argument("--deep-threshold", type=int, default=TEXT_T,
                    help="深色文字阈值，默认 400")
    ap.add_argument("--dump", action="store_true", help="打印字符画")
    ap.add_argument("--per-char", action="store_true", help="逐字打印")
    args = ap.parse_args()

    im = Image.open(args.image).convert("RGB")
    px = im.load()
    W, H = im.size
    x0, x1 = max(0, args.x0), min(W, args.x1)
    y0, y1 = max(0, args.y0), min(H, args.y1)

    test = make_test(args.light, args.deep_threshold)

    print("=" * 78)
    print("区域 x[%d,%d] y[%d,%d]  模式: %s"
          % (x0, x1, y0, y1, "反白(浅色文字)" if args.light else "常规(深色文字)"))
    print("=" * 78)

    # 列投影
    cp = [(x, sum(1 for y in range(y0, y1) if test(*px[x, y]))) for x in range(x0, x1)]
    cb = blocks(cp)
    print("\n字符列块:")
    for i, b in enumerate(cb):
        print("   #%-2d  x %4d ~ %4d   宽 %2d" % (i, b[0], b[1], b[1] - b[0] + 1))

    # 常见坑：扫描范围含边框/底纹时，所有列都有像素，整块连成一片切不开
    if len(cb) == 1 and (cb[0][1] - cb[0][0] + 1) > 0.8 * (x1 - x0):
        print("\n   ⚠ 整块连成一片、没切开。通常是因为扫描范围含进了边框或底纹，"
              "\n     导致每一列都有像素。请缩小 --x0/--x1 避开边框后重试。")

    if len(cb) >= 2:
        starts = [b[0] for b in cb]
        steps = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]
        if steps:
            cnt = Counter(steps)
            common, n = cnt.most_common(1)[0]
            print("\n>>> 字符步进: %d px  (出现 %d/%d 次%s)  %s"
                  % (common, n, len(steps),
                     "" if n == len(steps) else "，存在异常间隔 %s" % dict(cnt),
                     "← 等宽" if n == len(steps) else "← 非等宽，需逐字定位"))

    # 行投影
    rp = [(y, sum(1 for x in range(x0, x1) if test(*px[x, y]))) for y in range(y0, y1)]
    rb = blocks(rp)
    print("\n文字垂直范围:")
    for b in rb:
        print("   y %4d ~ %4d   高 %2d" % (b[0], b[1], b[1] - b[0] + 1))

    # 背景色：以「区域内出现频率最高的颜色」为准（比四角采样稳健，
    # 四角很容易落在网格线上而误判为 204/229/249 之类的浅灰）
    print("\n背景色（按出现频率）:")
    freq = Counter()
    for y in range(y0, y1):
        for x in range(x0, x1):
            freq[px[x, y]] += 1
    for col, n in freq.most_common(5):
        share = 100.0 * n / ((x1 - x0) * (y1 - y0))
        print("   %-18s %7d 次  (%.1f%%)" % (str(col), n, share))
    bg = freq.most_common(1)[0][0]
    print("   >>> 建议背景色: %s" % (bg,))

    corners = Counter(px[x, y] for x, y in
                      [(x0 + 1, y0 + 1), (x1 - 2, y0 + 1), (x0 + 1, y1 - 2), (x1 - 2, y1 - 2)])
    if len(corners) > 1 or list(corners)[0] != bg:
        print("   四角采样: %s" % dict(corners))
        print("   ⚠ 四角与频率统计不一致，四角很可能落在网格线上，以频率统计为准。")

    # 点阵判断：统计灰阶分布
    grays = Counter()
    for y in range(y0, y1):
        for x in range(x0, x1):
            v = sum(px[x, y]) / 3.0
            if v < 60:
                grays["core(<60)"] += 1
            elif v < 160:
                grays["mid(60-160)"] += 1
            elif v < 200:
                grays["edge(160-200)"] += 1
            else:
                grays["bg(>=200)"] += 1
    mid = grays.get("mid(60-160)", 0)
    core = grays.get("core(<60)", 1)
    print("\n点阵特征（灰阶分布）:")
    for k in ("core(<60)", "mid(60-160)", "edge(160-200)", "bg(>=200)"):
        print("   %-16s %6d" % (k, grays.get(k, 0)))
    ratio = mid / max(core, 1)
    print("   >>> 中间灰阶/核心 = %.2f  → %s"
          % (ratio,
             "二值点阵字（无抗锯齿），渲染时笔画应为 1px" if ratio < 0.35
             else "带抗锯齿的矢量渲染"))

    if args.dump:
        print("\n字符画:")
        for y in range(y0, y1):
            print("   |" + "".join("#" if test(*px[x, y]) else "." for x in range(x0, x1)) + "|")

    if args.per_char and cb:
        print("\n逐字:")
        for i, b in enumerate(cb):
            print("\n   第%d字 x[%d,%d]:" % (i + 1, b[0], b[1]))
            for y in range(y0, y1):
                line = "".join("#" if test(*px[x, y]) else " " for x in range(b[0], b[1] + 1))
                if line.strip():
                    print("     |" + line + "|")


if __name__ == "__main__":
    main()
