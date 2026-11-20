# OpenCode 1.19.5 Linux 终端手册

一份单文件 H5 速查手册，面向 Linux 原生终端，不依赖 tmux。内容全部内置，浏览器离线打开即可。

## 打开

下载本目录的 [opencode-1.19.5-linux-handbook.html](./opencode-1.19.5-linux-handbook.html)，双击或用浏览器打开：

<pre><code>xdg-open opencode-1.19.5-linux-handbook.html</code></pre>

页面没有 CDN、外部字体、图片或脚本依赖；内网环境也能完整使用。

## 内容

- **日常动作速查**：新建对话 / 项目、切换与压缩会话、加载 Skill、中断生成、布置长任务、退出。
- **51 条默认快捷键**：按键 / 作用 / 说明三列，默认全部展开，支持搜索、分类筛选和打印 / PDF。
- **项目与会话**：项目切换、<code>opencode -c</code> / <code>-s</code>、<code>/new</code>、<code>/sessions</code>。
- **工具调用**：<code>@</code> 文件、<code>/</code> 命令、<code>!</code> shell，以及内置工具、权限、MCP 与自定义工具。
- **原生 Linux 终端**：剪贴板、<code>Ctrl+S</code> / <code>Ctrl+Q</code>、<code>Ctrl+Z</code> / <code>fg</code>、长任务保活与 headless 方案。
- 深色 / 浅色主题、移动端适配、页内搜索、打印样式。

## 版本与依据

- 面向 **OpenCode 1.19.5**；后续大版本（V2）可能调整 TUI 与键位。
- 行为与默认键位对照了 1.19.5 源码和 V1 文档；页末参考链接只是延伸资料，打不开不影响正文。
- 本手册为公开通用内容，不包含账号、订阅、节点或本机敏感配置。
