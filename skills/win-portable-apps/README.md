# Windows 便携软件安装：非管理员账户的软件部署方法论

在**没有 winget、没有管理员权限**的 Windows 上，把日常要用的软件装好并可用。
本目录来自一次真实部署：一台 Windows 10 机器，账户非管理员，最终装好 8 个程序、
配好开始菜单与快捷方式，并理清了文件关联的可行边界。

---

## 核心结论：便携版是非管理员账户的可行路线

| 路线 | 需要管理员 | 可用性 |
|---|---|---|
| **MSI / exe 安装程序** | **是** | 会失败或留下半成品安装 |
| winget（若已装） | 取决于包 | 本机没有 winget |
| Store 应用 | 不需要 | 但只能装商店里有的，且默认关联被系统锁定 |
| **便携版（解压即用）** | **否** | ✅ **本方案采用** |
| Scoop | 否 | ✅ 适合开发工具链，见 `win-dev-environment` |

便携版的三条硬优势：

1. **不需要管理员** —— 完全不写 `Program Files`、不跑 MSI
2. **卸载 = 删文件夹** —— 无注册表残留（除你自己建的快捷方式）
3. **配置留在自己目录里** —— 换机时拷走文件夹即可

---

## 脚本

### `scripts/check-software.ps1` — 软件清单（只读）

```powershell
pwsh -File scripts/check-software.ps1
pwsh -File scripts/check-software.ps1 -Json | Out-File software.json
pwsh -File scripts/check-software.ps1 -PortableRoot D:\PortableApps
```

按来源分四类盘点，这一点很关键 —— **便携版软件根本不出现在 Windows 的"应用和功能"里**，
所以只查系统列表会得出"什么都没装"的错误结论：

| 来源 | 发现方式 |
|---|---|
| 便携应用 | 扫描便携根目录，每个子目录找主程序 exe + 读文件版本信息 |
| Scoop | `scoop list` |
| MSI / 安装程序 | 三个 Uninstall 注册表分支 |
| PATH 覆盖 | 报告哪些便携目录已加入用户 PATH |

最后报告**文件关联状态**，并明确标出**哪些必须手动点**。

### `scripts/install-portable.ps1` — 从清单安装

```powershell
pwsh -File scripts/install-portable.ps1 -Manifest apps.json -WhatIf   # 先干跑
pwsh -File scripts/install-portable.ps1 -Manifest apps.json
pwsh -File scripts/install-portable.ps1 -Manifest apps.json -Only Notepad++,rclone
```

每个条目依次执行：

1. **下载**到 `.installers\` 缓存（已存在则跳过）
2. **校验 SHA256** —— 不匹配则**拒绝安装并删除下载**
3. **解压**（优先用已装的 7-Zip，否则自动拉取独立 `7zr.exe`）
4. **折叠单层目录** —— 保证布局恒为 `<目标>\<应用>\<文件>`
5. 可选**创建开始菜单快捷方式**
6. 可选**把 CLI 目录加入用户 PATH**

#### 关于 SHA256

清单里 **`sha256` 为空时脚本会拒绝安装**，必须显式传 `-AllowUnverified` 才放行。

这是刻意设计：哈希是"下载是否被篡改"的**唯一**防线，默认放行等于没有防线。

#### 关于 `-Only` 参数的坑

PowerShell 的 `-File` 模式**不会把 `A,B` 拆成数组**，整串会作为单个元素传入：

```powershell
# 实测：-File 模式下
pwsh -File x.ps1 -Only 'A','B'    # 收到 1 个元素 "A,B"，不是 2 个
```

脚本内部已做兼容 —— **逗号分隔会被自行拆分**，因此下面两种写法都有效：

```powershell
pwsh -File scripts/install-portable.ps1 -Manifest apps.json -Only Notepad++,rclone
pwsh -Command "& ./scripts/install-portable.ps1 -Manifest apps.json -Only Notepad++,rclone"
```

### `scripts/set-app-associations.ps1` — 文件关联

```powershell
pwsh -File scripts/set-app-associations.ps1                                  # 只报告 + 备份
pwsh -File scripts/set-app-associations.ps1 -Register @{ 'MdEditor' = 'C:\...\marktext.exe' }
```

**这个脚本不会替你设置默认程序 —— 因为 Windows 不允许。** 见下节。

---

## 必须知道的限制：默认程序无法脚本化

这是本项目最有价值的发现，也是"为什么脚本没帮我把图片默认程序改掉"的完整答案。

### 机理

Windows 10/11 把每个用户的默认程序记在：

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<扩展名>\UserChoice
```

这个键带**两重保护**：

1. **显式的 `Deny SetValue` ACE** —— 对当前用户拒绝写入
2. **`Hash` 值** —— 对 ProgId + SID + 时间戳做哈希，值不对就不认

实测证据（本机真实输出）：

```
Access 规则:
  <用户>              Deny    SetValue      ← 显式拒绝
  <用户>              Allow   FullControl   ← 但 SetValue 仍被 Deny 压过
  NT AUTHORITY\SYSTEM Allow   FullControl

键值:
  ProgId : AppX43hnxtbyyps62jhe9sqpdzxn1790zetc
  Hash   : Bjb6fycYDTA=

写入测试:
  Requested registry access is not allowed.
```

注意 `Deny` **优先于** `Allow FullControl` —— 所以即便你是键的所有者、哪怕是管理员，
也改不了。**这是防静默劫持的设计，不是 bug。**

### 脚本能做与不能做

| 能做 | 不能做 |
|---|---|
| 备份关联相关注册表分支（`reg export`） | 修改 `UserChoice` 的默认程序 |
| 在 `HKCU\Software\Classes` 注册 ProgID，让程序**出现在"打开方式"列表**里 | 让程序**成为默认** |
| 精确报告哪些扩展名还需要手动点一次 | 绕过 Hash 校验 |

### 需要手动点一次的操作

每个扩展名**只需一次**，之后长期生效：

1. 右键任意该类型文件 → **打开方式** → **选择其他应用**
2. 选中你的便携程序 → 勾选 **始终使用此应用**

或走 **设置 → 应用 → 默认应用 → 按文件类型选择默认应用**。

> **实测确认这条路径有效且持久**：本机 `.md` 已成功关联到 Notepad++、`.png` 已关联到
> JPEGView、`.webp` 已关联到 ImageGlass，而 `.jpg` / `.mp4` / `.mkv` / `.mp3` 等仍是
> 系统商店应用（`AppX...`），正等待手动选择。
> **手动设置是能生效的**，只是无法由脚本代劳。

---

## 软件选型：按用途分组

同一用途准备多个程序不是冗余 —— 不同程序在不同场景下明显更合适。

### 文本 / Markdown / 代码

| 程序 | 特点 |
|---|---|
| **Notepad++** | 轻量、启动快、语法高亮、多标签。`.md` 纯文本编辑的首选 |
| MarkText | 所见即所得的 Markdown 编辑器（Typora 的免费替代） |

> `.md` 用什么打开取决于习惯：改文字用 Notepad++，写文档要预览就用 MarkText。

### 图片查看

| 程序 | 特点 | 适用 |
|---|---|---|
| **JPEGView** | 极小、极快，启动几乎瞬时 | 大量图片快速翻看 |
| **nomacs** | 格式最全、EXIF 元数据、批量操作 | 看参数、批量处理 |
| **ImageGlass** | 界面现代、美观 | 日常浏览 |

> 便携版注意：JPEGView 不带参数启动会打开它自己目录里的 `NavPanel.png`，这是正常现象。

### 音视频播放

| 程序 | 特点 |
|---|---|
| **mpv** | 画质与格式覆盖最强；界面极简，键盘驱动 |
| **MPC-BE** | 传统播放器界面：播放列表、倍速、字幕加载 |

> mpv 常用键位：`空格` 播放/暂停、`←/→` 快退快进、`f` 全屏、`9/0` 音量、`q` 退出。
> 字幕自动加载同名 `.srt`。直接把文件拖进窗口即可播放。

### 本地 NAS 访问

| 程序 | 特点 |
|---|---|
| **rclone** | 通过 SMB / WebDAV 同步、校验、备份；命令行，可脚本化 |

**rclone 的边界**：`rclone mount` 把远端挂成盘符需要 **WinFsp**，而 WinFsp 是驱动安装、
**需要管理员权限**。因此在非管理员账户上：

- ✅ 用 rclone 做 `copy` / `sync` / `check`
- ✅ 要"盘符"就用 Windows 自带的 `net use` 映射 SMB 共享（不需要管理员）
- ❌ 不用 `rclone mount`

```bat
:: 判断权限够不够用，看这两条的差别
net use Z: \\NAS\share /persistent:yes     :: 不需要管理员
rclone mount nas: Z:                        :: 需要 WinFsp，需要管理员
```

---

## 清单格式

```json
{
  "version": 1,
  "apps": [
    {
      "name": "Notepad++",
      "url": "https://github.com/.../npp.8.9.8.1.portable.x64.zip",
      "sha256": "<从发布页取，留空会被拒绝安装>",
      "exe": "notepad++.exe",
      "addToPath": ".",
      "notes": "自由文本说明"
    }
  ]
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | ✅ | 目录名，也是 `-Only` 的匹配值 |
| `url` | ✅ | 直链下载地址（GitHub Release 资产直链可用） |
| `sha256` | ⚠️ | 强烈建议。留空需 `-AllowUnverified` |
| `exe` | | 主程序相对路径，用于创建快捷方式 |
| `addToPath` | | 需要加入 PATH 的子目录（CLI 工具用 `.`） |
| `notes` | | 说明 |

完整示例见 [`scripts/apps.example.json`](./scripts/apps.example.json)。

---

## 部署流程

```powershell
# 1) 先看现状：已经有什么、哪些关联还要手动点
pwsh -File scripts/check-software.ps1

# 2) 干跑：确认将会下载和解压什么
pwsh -File scripts/install-portable.ps1 -Manifest apps.json -WhatIf

# 3) 正式安装
pwsh -File scripts/install-portable.ps1 -Manifest apps.json

# 4) 看哪些关联需要手动确认（同时自动备份注册表）
pwsh -File scripts/set-app-associations.ps1

# 5) 开新终端，验证 CLI 工具已在 PATH
rclone version
```

---

## 目录布局

```
<便携根目录>\
├── .installers\          下载缓存（数百 MB，确认装好后可删）
├── _backup\              注册表备份（改关联前自动生成）
├── Notepad++\
│   └── notepad++.exe
├── mpv\
│   └── mpv.exe
├── rclone\
│   └── rclone.exe
└── ...
```

约定：**一个应用一个顶层目录**，主程序在其内部。这样安装器的"折叠单层目录"逻辑
能稳定产出统一布局，删除也只需删一个目录。

---

## 边界与限制

| 限制 | 说明 |
|---|---|
| **默认程序无法脚本设置** | `UserChoice` 有 `Deny SetValue` ACE + Hash。见上文 |
| **`rclone mount` 需要管理员** | 依赖 WinFsp 驱动 |
| **便携软件不出现在"应用和功能"** | 必须用目录扫描盘点 |
| **下载哈希需自己核对** | 脚本能校验，但哈希值要从发布页取 |
| **首次运行可能被 SmartScreen 拦** | 未签名程序属正常，需手动允许 |
| **不能操作提权窗口** | Windows 既定边界 |

---

## 安全提示

- **务必填 `sha256`。** 脚本默认拒绝无哈希条目，这道防线只在你不绕过它时有效
- **下载来源只用官方发布页。** 第三方"绿色版/破解版"是恶意软件主要载体
- **`.installers\` 是缓存**，含原始安装包，确认安装成功后可以删除以释放空间
- **不要提交任何含凭据的文件**：NAS 地址、用户名、`rclone.conf`、网络驱动器映射导出、
  浏览器书签备份都属于私有信息，不应进入公开仓库
