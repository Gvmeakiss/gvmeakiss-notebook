# 截图文字高保真修改工具包

不改源系统，只改图片 —— 用**字形克隆**替换截图中的文字/数字，字形像素级一致，看不出修改痕迹。

适用于 SAP/ERP 截图、报表、台账、单据、各类后台界面截图。

---

## 为什么不用字体重绘

跨平台字体渲染必然有差异，字小的时候尤其明显，一眼就假。

**字形克隆**的思路是：截图里通常已经有你需要的字符（数字 0-9 在金额、编号、日期里几乎必然出现）。
从**同行同字号**的已有文本中克隆字形来拼新内容，于是字形 100% 一致。

三者对比：

| 方式 | 保真度 | 适用 |
|---|---|---|
| 克隆图中已有的字 | ⭐⭐⭐ 像素级一致 | 图中存在该字（优先） |
| 克隆反白高亮区的字 | ⭐⭐⭐ 像素级一致 | 深色背景+浅色文字的选中标签 |
| 字体渲染 | ⭐⭐ 接近 | 图中确实没有该字时的兜底 |

---

## 目录结构

```
screenshot-text-edit/
├── SKILL.md                    # Skill 定义（AI 加载用，含完整方法论）
├── README.md                   # 本文件
└── scripts/
    ├── locate.py               # 第 1 步：OCR 定位 + 字形源搜索
    ├── analyze.py              # 第 2 步：字符边界/步进/背景色/点阵判断
    ├── edit.py                 # 第 3 步：字形克隆替换（JSON 配置驱动）
    ├── edits.example.json      # 配置示例
    └── verify.py               # 第 4 步：差分验证 + OCR 回读
```

## 环境准备

```bash
pip install pyobjc-framework-Vision pyobjc-framework-Quartz pillow
```

- OCR 走 macOS Vision 框架，故**脚本为 macOS 专用**
- 微信/QQ 容器目录有沙箱限制，先把图 `cp` 到工作区再处理

---

## 四步工作流

### 1️⃣ 定位

```bash
python3 scripts/locate.py shot.png                     # 列出全部文本块及坐标
python3 scripts/locate.py shot.png --cn                # 中文界面必须加 --cn
python3 scripts/locate.py shot.png --find-glyphs 108   # 搜索字形源：哪些位置有 1/0/8
```

`--find-glyphs` 是关键一步，它决定最终质量。**优先选与目标同一行**（y 接近）的源。

### 2️⃣ 分析

OCR 的文本框常把相邻字段合并，不能直接拿来覆盖。用列投影切出逐字符边界：

```bash
python3 scripts/analyze.py shot.png --x0 840 --x1 900 --y0 380 --y1 402
python3 scripts/analyze.py shot.png --x0 840 --x1 900 --y0 380 --y1 402 --dump
```

输出字符块边界、**步进 pitch**、文字垂直范围、背景色、是否点阵字。

### 3️⃣ 替换

```bash
python3 scripts/edit.py shot.png --config my_edits.json --out result.png
python3 scripts/edit.py shot.png --config my_edits.json --dry-run   # 先预演
```

配置示例（完整版见 `scripts/edits.example.json`）：

```json
{
  "edits": [{
    "name": "净价 9.17 -> 10",
    "x": 776, "bottom": 397, "old_len": 4,
    "new": "10", "pitch": 8,
    "bg": [234, 237, 240],
    "glyph_y": [386, 400],
    "glyphs": {
      "1": {"type": "clone", "x": 210, "width": 8},
      "0": {"type": "clone", "x": 218, "width": 8}
    }
  }]
}
```

### 4️⃣ 验证

```bash
python3 scripts/verify.py orig.png result.png \
    --safe "相邻字段:905,915,365,380" \
    --expect-new 1080 --expect-gone 990.83 \
    --compare compare.png --region 840,905,380,402
```

- **差异区域**：应一一对应预期改动
- **安全区**：不该动的区域差异必须为 0
- **OCR 回读**：新值出现、旧值消失

---

## 改中文：三个要点

中文比数字难，因为图中往往**没有**你要的字。

**1. OCR 要显式启用中文**，否则 Vision 把中文识别成乱码（`ІГ`、`卧项目`）：

```bash
python3 scripts/locate.py shot.png --cn
```

**2. 反白高亮标签是宝库**。选中态的标签页是深色背景+浅色文字，字形形状与正常文字一致，只是颜色反了。
提取浅色像素即可得到可用字形：

```bash
python3 scripts/analyze.py shot.png --x0 80 --x1 136 --y0 255 --y1 272 --light --per-char
```

**3. 实在没有的字才渲染**，且要看**墨迹量**而非差异像素：

```
原图平均每字墨迹 48  →  渲染落在 45~60/字 才合适
```

差异像素数对汉字没有判别力（不同字体天然就有 20~30% 差异）。墨迹量接近 = 笔画粗细接近 = 风格一致。

另外：**笔画数 > 10 的复杂字不要做细化**，11px 下会把结构压成一团糊。宁可保留 2px 笔画。

---

## 常见坑

| 现象 | 原因 | 解决 |
|---|---|---|
| 字符切不开，整列都有计数 | 统计了浅灰网格线（204/229/249） | 脚本已只统计深色像素（RGB和<400） |
| 整块连成一片 | 扫描范围含进边框 | 缩小 `--x0/--x1` 避开边框 |
| 背景色采到 204/229 | 采样点落在网格线上 | 脚本改用频率统计，并会警告四角不一致 |
| 中文全是乱码 | Vision 未启用中文 | 加 `--cn` |
| 渲染的字太粗/太细 | 参数照抄但未校验 | 比对墨迹量（原图 vs 渲染） |
| 复杂字糊成一团 | 做了细化 | 去掉细化，保留 2px 笔画 |

---

## 已知限制

- 仅 macOS（依赖 Vision OCR）
- 字体渲染的中文与原图可能存在细微字形差异，无法完全消除（缺 Windows 点阵字体）
- 需要原图分辨率足够（建议 ≥ 1x，字高 ≥ 10px）；字太小则字形提取不可靠

## 脱敏提醒

业务截图常含客户名称、订单号、金额、人名。外发或提交到公开仓库前：

- 案例描述中的真实公司名一律泛化
- 订单号用占位符或虚构值
- **原图不要随代码提交**，只提交脚本和方法
