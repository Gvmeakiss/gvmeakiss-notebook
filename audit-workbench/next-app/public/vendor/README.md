# 本地 Excel 依赖

- 项目：SheetJS Community Edition
- 固定版本：0.20.3
- 许可：Apache-2.0，全文见 `LICENSE.sheetjs.txt`
- 获取日期：2026-09-07
- 官方独立脚本说明：https://docs.sheetjs.com/docs/getting-started/installation/standalone/
- 原始脚本：https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js
- 原始许可：https://cdn.sheetjs.com/xlsx-0.20.3/package/LICENSE

应用只加载本目录的脚本；上述网址为开发追溯资料，运行时不访问。

SHA-256：

```text
cc015130aa8521e7f088f88898eba949ccdcbfb38df0bd129b44b7273c3a6f41  xlsx.full.min.js
4d2a38ac35cda06a555c84074a819d413339cd3691b822cae50f8f322fe01f64  LICENSE.sheetjs.txt
```

升级时从官方来源获取脚本及许可，更新版本与校验和，并复跑 Excel 及浏览器测试，不要将 CDN 引用加入 index.html。
