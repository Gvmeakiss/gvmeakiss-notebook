#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify.py —— 改完之后的验证：差分范围 + 边界安全 + OCR 回读

三件事:
  1. 差分：改动落在哪，有没有越界误伤相邻字段/网格线
  2. 安全区检查：指定「不该被改动」的区域，确认差异为 0
  3. OCR 回读：确认新值出现、旧值消失
     —— 中文改动尤其看这条：能高置信度识别出来，说明字形没糊

用法:
    python3 verify.py orig.png edited.png

    # 指定不该被改动的区域（格式 名称:x0,x1,y0,y1，可多次）
    python3 verify.py orig.png edited.png \
        --safe "相邻字段:905,915,365,380" \
        --safe "网格线:760,920,404,408"

    # 检查旧值是否残留、新值是否到位
    python3 verify.py orig.png edited.png --expect-new 1080 --expect-new "总金额" --expect-gone 990.83

    # 顺带生成放大对比图
    python3 verify.py orig.png edited.png --compare compare.png --region 840,905,380,402
"""
import argparse
import sys

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("缺少依赖: pip install pillow")


def run_ocr(path, cn=True):
    try:
        from Foundation import NSURL
        import Vision
        from Quartz import CIImage
    except ImportError:
        return None
    ci = CIImage.imageWithContentsOfURL_(NSURL.fileURLWithPath_(path))
    if ci is None:
        return None
    handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(ci, None)
    req = Vision.VNRecognizeTextRequest.alloc().init()
    req.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    req.setUsesLanguageCorrection_(False)
    req.setRecognitionLanguages_(["zh-Hans", "en-US"] if cn else ["en-US"])
    ok, _ = handler.performRequests_error_([req], None)
    if not ok:
        return None
    im = Image.open(path)
    W, H = im.size
    out = []
    for obs in req.results():
        c = obs.topCandidates_(1)[0]
        bb = obs.boundingBox()
        out.append((bb.origin.x * W, (1 - bb.origin.y - bb.size.height) * H,
                    c.string(), float(c.confidence())))
    return out


def main():
    ap = argparse.ArgumentParser(
        description="截图修改结果验证",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("original")
    ap.add_argument("edited")
    ap.add_argument("--safe", action="append", default=[],
                    help="不该被改动的区域，格式 名称:x0,x1,y0,y1（可多次）")
    ap.add_argument("--expect-new", action="append", default=[],
                    help="应出现的新文本（可多次）")
    ap.add_argument("--expect-gone", action="append", default=[],
                    help="应消失的旧文本（可多次）")
    ap.add_argument("--compare", help="生成放大对比图并保存到该路径")
    ap.add_argument("--region", action="append", default=[],
                    help="对比图裁切区域 x0,x1,y0,y1（配合 --compare，可多次）")
    args = ap.parse_args()

    A = Image.open(args.original).convert("RGB")
    B = Image.open(args.edited).convert("RGB")
    if A.size != B.size:
        sys.exit("尺寸不一致: %s vs %s" % (A.size, B.size))
    pa, pb = A.load(), B.load()
    W, H = A.size

    print("=" * 78)
    print("差分验证")
    print("=" * 78)
    print("差异包围盒: %s" % (ImageChops.difference(A, B).getbbox(),))

    pts = [(x, y) for y in range(H) for x in range(W) if pa[x, y] != pb[x, y]]
    print("差异像素总数: %d" % len(pts))

    if pts:
        rows = sorted(set(p[1] for p in pts))
        regions, cur = [], [rows[0], rows[0]]
        for y in rows[1:]:
            if y - cur[1] <= 2:
                cur[1] = y
            else:
                regions.append(tuple(cur)); cur = [y, y]
        regions.append(tuple(cur))
        print("\n差异区域（按行聚合）:")
        for (y0, y1) in regions:
            sel = [p for p in pts if y0 <= p[1] <= y1]
            sx = [p[0] for p in sel]
            print("   y %4d~%-4d   x %4d~%-4d   像素 %d" % (y0, y1, min(sx), max(sx), len(sel)))
        print("\n   请核对：每个区域都应对应一处预期改动，不应有意外区域。")

    if args.safe:
        print("\n" + "=" * 78)
        print("安全区检查（应全部为 0）")
        print("=" * 78)
        all_ok = True
        for s in args.safe:
            name, coords = s.rsplit(":", 1)
            x0, x1, y0, y1 = [int(v) for v in coords.split(",")]
            bad = sum(1 for y in range(y0, y1) for x in range(x0, x1) if pa[x, y] != pb[x, y])
            ok = bad == 0
            all_ok = all_ok and ok
            print("   %-30s 差异 %3d  %s" % (name, bad, "✓" if ok else "✗ 被误改!"))
        print("\n   结论: %s" % ("全部安全" if all_ok else "存在越界，请检查"))

    if args.expect_new or args.expect_gone:
        print("\n" + "=" * 78)
        print("OCR 回读")
        print("=" * 78)
        items = run_ocr(args.edited)
        if items is None:
            print("   跳过（未安装 Vision 依赖）")
        else:
            joined = " ".join(t for _, _, t, _ in items)
            for t in args.expect_new:
                hit = [i for i in items if t in i[2]]
                if hit:
                    best = max(hit, key=lambda i: i[3])
                    print("   ✓ 新值 %-12r 已出现  x=%.0f y=%.0f  conf%.2f"
                          % (t, best[0], best[1], best[3]))
                else:
                    print("   ✗ 新值 %-12r 未识别到" % t)
            for t in args.expect_gone:
                if t in joined:
                    print("   ✗ 旧值 %-12r 仍有残留" % t)
                else:
                    print("   ✓ 旧值 %-12r 已消失" % t)
            print("\n   提示：中文若能被高置信度(conf>0.9)识别出来，"
                  "说明字形清晰、没有因笔画过细或细化而糊掉。")

    if args.compare and args.region:
        print("\n" + "=" * 78)
        print("生成对比图")
        print("=" * 78)
        SCALE = 4
        tiles = []
        for r in args.region:
            x0, x1, y0, y1 = [int(v) for v in r.split(",")]
            ca, cb = A.crop((x0, y0, x1, y1)), B.crop((x0, y0, x1, y1))
            w, h = ca.size
            tiles.append((ca.resize((w * SCALE, h * SCALE), Image.NEAREST),
                          cb.resize((w * SCALE, h * SCALE), Image.NEAREST)))
        tw = max(t[0].size[0] for t in tiles)
        th = max(t[0].size[1] for t in tiles)
        cw, ch = tw * 2 + 30, (th + 24) * len(tiles)
        canvas = Image.new("RGB", (cw, ch), (32, 33, 36))
        for i, (ca, cb) in enumerate(tiles):
            y = i * (th + 24)
            canvas.paste(ca, (10, y))
            canvas.paste(cb, (20 + tw, y))
        canvas.save(args.compare)
        print("   已保存: %s  (左=原图 右=修改后，放大 %dx)" % (args.compare, SCALE))


if __name__ == "__main__":
    main()
