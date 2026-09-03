#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
locate.py —— 截图中待改文字的 OCR 定位

用 macOS Vision 框架做 OCR，返回每个文本块的像素坐标。
同时支持「字形源搜索」：找出图中哪些位置含有你需要的字符，供后续克隆使用。

依赖:
    pip install pyobjc-framework-Vision pyobjc-framework-Quartz pillow

用法:
    # 列出全部文本
    python3 locate.py shot.png

    # 只看某个词附近
    python3 locate.py shot.png --filter 990.83

    # 限定纵向范围（只看列标题行）
    python3 locate.py shot.png --y0 360 --y1 385

    # 搜索字形源：图中哪些位置有 1/0/8 这三个字符
    python3 locate.py shot.png --find-glyphs 108

    # 搜索中文字形源（含中文识别）
    python3 locate.py shot.png --cn --find-glyphs 单总价
"""
import argparse
import sys

try:
    from Foundation import NSURL
    import Vision
    from Quartz import CIImage
    from PIL import Image
except ImportError as e:
    sys.exit("缺少依赖，请先执行:\n"
             "  pip install pyobjc-framework-Vision pyobjc-framework-Quartz pillow\n"
             "原始错误: %s" % e)


def ocr(path, languages=("en-US",), accurate=True):
    """返回 [(x, y, w, h, text, confidence), ...]，坐标为像素，原点左上角"""
    ci = CIImage.imageWithContentsOfURL_(NSURL.fileURLWithPath_(path))
    if ci is None:
        sys.exit("无法加载图片: %s" % path)

    handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(ci, None)
    req = Vision.VNRecognizeTextRequest.alloc().init()
    req.setRecognitionLevel_(
        Vision.VNRequestTextRecognitionLevelAccurate if accurate
        else Vision.VNRequestTextRecognitionLevelFast)
    req.setUsesLanguageCorrection_(False)
    req.setRecognitionLanguages_(list(languages))

    ok, err = handler.performRequests_error_([req], None)
    if not ok:
        sys.exit("OCR 失败: %s" % err)

    im = Image.open(path)
    W, H = im.size
    out = []
    for obs in req.results():
        c = obs.topCandidates_(1)[0]
        bb = obs.boundingBox()          # 归一化，原点左下角
        out.append((
            bb.origin.x * W,                              # x
            (1 - bb.origin.y - bb.size.height) * H,       # y（转左上角原点）
            bb.size.width * W,                            # w
            bb.size.height * H,                           # h
            c.string(),
            float(c.confidence()),
        ))
    return out


def is_cjk(s):
    return any('\u4e00' <= ch <= '\u9fff' for ch in s)


def main():
    ap = argparse.ArgumentParser(
        description="截图文字 OCR 定位（macOS Vision）",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", help="图片路径")
    ap.add_argument("--cn", action="store_true",
                    help="启用中文识别（默认关闭；中文界面必须开启，否则识别为乱码）")
    ap.add_argument("--filter", help="只显示包含该文本的结果")
    ap.add_argument("--y0", type=float, help="只看 y >= 此值的结果")
    ap.add_argument("--y1", type=float, help="只看 y <= 此值的结果")
    ap.add_argument("--find-glyphs", metavar="CHARS",
                    help="字形源搜索：找出图中含有这些字符的位置（克隆字形用）")
    ap.add_argument("--min-conf", type=float, default=0.0, help="置信度下限")
    args = ap.parse_args()

    langs = ("zh-Hans", "en-US") if args.cn else ("en-US",)
    items = ocr(args.image, langs)

    if args.filter:
        items = [i for i in items if args.filter in i[4]]
    if args.y0 is not None:
        items = [i for i in items if i[1] >= args.y0]
    if args.y1 is not None:
        items = [i for i in items if i[1] <= args.y1]
    items = [i for i in items if i[5] >= args.min_conf]

    im = Image.open(args.image)
    print("图片: %s  (%d x %d)" % (args.image, im.size[0], im.size[1]))

    # ---------- 字形源搜索 ----------
    if args.find_glyphs:
        wanted = set(args.find_glyphs)
        print("\n字形源搜索：目标字符 %s" % " ".join(sorted(wanted)))
        print("=" * 78)
        hits = 0
        for x, y, w, h, t, c in items:
            found = wanted & set(t)
            if found:
                hits += 1
                print("  x=%-5.0f y=%-5.0f w=%-4.0f h=%-4.0f conf%.2f  %r  → 含 %s"
                      % (x, y, w, h, c, t, "".join(sorted(found))))
        if not hits:
            print("  未找到。建议：--cn 开启中文识别，或放宽 --min-conf")
        else:
            print("\n  提示：优先选与目标文字「同一行」的源（y 接近），"
                  "同行通常同字号同渲染，克隆后字形完全一致。")
        return

    # ---------- 常规列出 ----------
    print("=" * 78)
    if not items:
        print("无结果")
        return
    for x, y, w, h, t, c in items:
        mark = " [中文]" if is_cjk(t) else ""
        print("  x=%-5.0f y=%-5.0f w=%-4.0f h=%-4.0f conf%.2f  %r%s"
              % (x, y, w, h, c, t, mark))
    print("=" * 78)
    print("共 %d 条。注意：OCR 文本框常把相邻字段合并，"
          "精确边界请用 analyze.py 做列投影切分。" % len(items))


if __name__ == "__main__":
    main()
