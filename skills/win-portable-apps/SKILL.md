---
name: win-portable-apps
description: 在 Windows 上为非管理员账户安装、盘点与清理便携软件（免安装、免提权、删文件夹即卸载）。当出现"帮我装些好用的软件""电脑没有 winget/装不了软件""装个打开 md/图片/视频的软件""便携版软件""软件装在哪个目录了""为什么我的默认打开程序改不掉""右键打开方式里没有这个程序""删了软件但打开方式里还在"等诉求时使用。核心是四条判断：便携版是非管理员账户的可行路线、便携软件不出现在系统应用列表所以必须目录扫描、默认程序受 UserChoice 的 Deny ACL + Hash 保护因而无法脚本设置、删程序后注册表关联不会自动清理。
agent_created: true
---

# Windows 便携软件安装（非管理员账户）

## 适用场景

用户想**装软件、管软件、或者搞不清软件装哪了**，而不是排查代码：

- "帮我装些方便用电脑的软件，免费的"
- "装个能打开 md / 图片 / 视频的"
- "电脑没有 winget / 装软件提示需要管理员"
- "便携版的，别装进系统里"
- "为什么我改了图片默认程序又变回去了"
- "右键打开方式里找不到我刚装的那个程序"

## 第一判断：能不能用安装程序？

**先看权限，再谈装什么。** 这一步决定整条路线：

| 条件 | 结论 |
|---|---|
| 是管理员 | MSI / winget / exe 安装程序都可以 |
| **不是管理员** | **走便携版**（或 Scoop 这类用户级包管理器） |

非管理员跑 MSI 的后果不是"报错"，而是**静默失败或留下半成品**，比直接失败更难排查。

```powershell
(New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent()
)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

配套：`Get-Command winget, scoop, choco -ErrorAction SilentlyContinue`
—— 三者都没有时，便携版就是唯一选项。

## 工作流程

### 第一步：盘点现状（只读）

```powershell
pwsh -File scripts/check-software.ps1
pwsh -File scripts/check-software.ps1 -Json
```

**关键点：便携软件根本不出现在 Windows 的"应用和功能"里。**
只查系统列表会得出"什么都没装"的错误结论。必须多路并查：

| 来源 | 方式 |
|---|---|
| 便携应用 | 扫描便携根目录，逐目录找主程序并读文件版本 |
| Scoop | `scoop list` |
| MSI / 安装程序 | 三个 Uninstall 注册表分支 |
| PATH | 报告哪些便携目录已进用户 PATH |

### 第二步：按用途选型

**同一用途配多个程序不是冗余。** 不同程序在不同场景下明显更合适：

| 用途 | 选择 | 选它的理由 |
|---|---|---|
| 文本 / 代码 | Notepad++ | 轻量、启动快、多标签 |
| Markdown 写作 | MarkText | 所见即所得预览 |
| 图片·快翻 | **JPEGView** | 极小极快，启动几乎瞬时 |
| 图片·元数据/批量 | **nomacs** | 格式最全、EXIF、批处理 |
| 图片·日常 | ImageGlass | 界面现代 |
| 视频·画质 | **mpv** | 格式覆盖最强，键盘驱动 |
| 视频·传统界面 | **MPC-BE** | 播放列表、倍速、字幕 |
| 网络存储 | **rclone** | 同步 / 校验 / 备份 |

### 第三步：从清单安装

```powershell
pwsh -File scripts/install-portable.ps1 -Manifest apps.json -WhatIf
pwsh -File scripts/install-portable.ps1 -Manifest apps.json
```

安装器依次：下载到 `.installers\` 缓存 → **校验 SHA256** → 解压 → 折叠单层目录 →
可选建快捷方式 → 可选加入 PATH。

**必须填 `sha256`。** 脚本默认**拒绝**无哈希的条目（需显式 `-AllowUnverified` 才放行）——
哈希是"下载是否被篡改"的唯一防线，默认放行等于没有防线。

### 第四步：处理文件关联

```powershell
pwsh -File scripts/set-app-associations.ps1
```

**然后接受一个事实：默认程序无法由脚本设置。** 见下节。

## 必须知道的限制：默认程序改不了

这是最容易被误判为"脚本有 bug"的一点。结论比"改不掉"更精确。

### 1) 官方 API 存在，但在 Windows 10+ 上已失效

`IApplicationAssociationRegistration`（CLSID `591209c7-767b-42b2-9fba-44ee4615f2c7`）
是微软文档化的接口，提供 `SetAppAsDefault` / `SetAppAsDefaultAll`。

实测（Windows 10 22H2）：

| 调用 | 结果 |
|---|---|
| `QueryAppIsDefault` | ✅ 能**查询**，正常工作 |
| `SetAppAsDefault` | ❌ 返回 **`0x80070002`**（`ERROR_FILE_NOT_FOUND`） |
| 实际效果 | 默认程序**未被改动** |

**错误码本身也在误导** —— 它暗示"文件找不到"，真实原因是被策略禁止。

### 2) 存储默认程序的键带两重保护

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<扩展名>\UserChoice
```

1. **显式 `Deny SetValue` ACE**——对自己也拒绝写
2. **`Hash` 值**——ProgId + SID + 时间戳的哈希

```
Access 规则:
  <用户>              Deny    SetValue      ← 显式拒绝
  <用户>              Allow   FullControl   ← Deny 仍然压过 Allow
写入测试: Requested registry access is not allowed.
```

**NT 先判 `Deny` 再判 `Allow`** —— 所以哪怕你是键的所有者、哪怕是管理员也改不了。
这是**防静默劫持的设计，不是缺陷。**

### 3) 因此：脚本能做 / 不能做

| 能做 | 不能做 |
|---|---|
| 备份关联注册表分支（`reg export`，可还原） | 修改默认程序 |
| 注册应用让 Windows **主动提供**它（见下） | 绕过 Hash |
| 精确列出哪些扩展名还需手动点一次 | 用 COM API 设置默认 |

### 4) 注册应用有两条路径，缺一不可

最容易漏的一点 —— **只注册一条，程序就是"半可见"状态**：

| 注册位置 | 效果 |
|---|---|
| `HKCU\Software\Classes\Applications\<exe>` | 出现在右键**"打开方式"**列表 |
| `HKCU\Software\<Vendor>\Capabilities`<br>+ `HKCU\Software\RegisteredApplications` | 出现在**设置 → 默认应用 → 按文件类型选择** |

漏了第一条 → 用户只能手动浏览到 exe；
漏了第二条 → **设置页里根本看不到这个程序**。

### 给用户的操作指引

每个扩展名**只需一次**，之后长期生效：

> **A)** 右键任意该类型文件 → 打开方式 → 选择其他应用 → 选中便携程序 → 勾选"始终使用此应用"
>
> **B)** 设置 → 应用 → 默认应用 → 按文件类型选择默认应用（注册过的程序按名字出现在这里）

**手动设置确实有效且持久**（实测 `.md` → MarkText、`.png`/`.jpg` → JPEGView 均成功保持），
只是无法由脚本代劳。**必须把这句说明清楚**，否则用户会以为安装失败。

### 5) 卸载后要检查关联残留

便携版"删文件夹即卸载"，但**注册表不会跟着消失**。三类残留，严重性差别很大：

| 残留 | 后果 | 严重性 |
|---|---|---|
| `UserChoice` 指向已删程序 | **默认打开方式失效**，双击文件没反应或报错 | **高，必须修** |
| ProgID 指向已删程序且无扩展名引用 | 无害，但已删程序仍出现在"打开方式"列表 | 低，可清理 |
| `RegisteredApplications` / `Capabilities` 指向已删程序 | 设置页显示没装的程序 | 低，可清理 |

**所以"删程序"这个动作后面必须跟一次关联检查** —— 用
`scripts/clean-orphan-associations.ps1`。这是最容易被漏掉的一步。

反过来注意：如果把关联**重定向**到仍在的程序（把原 ImageGlass 的扩展名改指 JPEGView），
那些 ProgID 就**不是**孤儿，应判为健康。

### 怎么判断"已经是好的关联"

ProgId 以 `AppX` 开头表示当前是**系统商店应用**，通常正是需要改掉的那种：

```
.md  → MarkText.md                             ← 已关联成功
.png → JPEGView.png                            ← 已关联成功
.mp4 → AppX6eg8h5sxqq90pv53845wmnbewywdqq5h    ← 商店"电影和电视"，待改
```

## Windows 专属陷阱

### 1. `-File` 模式下逗号不拆数组

```powershell
pwsh -File x.ps1 -Only 'A','B'    # 实测：只收到 1 个元素 "A,B"，不是 2 个
```

`-Command` 模式会拆，`-File` 模式不会。**脚本必须自己兼容**：

```powershell
$wanted = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
```

否则用户按文档传 `-Only A,B` 会得到 "no apps selected"，看起来像脚本坏了。

### 2. 陈旧 PATH 让"已装的软件"看起来没装

GUI / agent 父进程的环境可能早于当前配置，子进程继承后会把已装的 Scoop、
7-Zip 报成缺失。**脚本必须自行从注册表重建 PATH**：
```powershell
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path','Machine'),
    [Environment]::GetEnvironmentVariable('Path','User')
) | Where-Object { $_ }) -join ';'
```

### 3. 中文路径与批处理的编码

`.bat` 里含中文文件名或变量时需要 `chcp 936`（GBK），或全程用引号包裹路径。
更稳的做法是让 `.bat` 只做转发，逻辑写在 `.ps1` 里。

### 4. 隐藏窗口启动（后台/开机任务）

需要开机静默运行的脚本，用 VBS 包一层可避免黑框闪烁：

```vbscript
CreateObject("WScript.Shell").Run "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\path\to\script.ps1""", 0, False
```

### 5. 枚举注册表：用 `reg query`，别用 PowerShell

清理关联残留要遍历 `HKCU\Software\Classes`（实测 853 个子键、333 个 ProgID）：

| 方法 | 耗时 |
|---|---|
| PowerShell 逐键 `Get-ItemProperty` | **281 秒** |
| 原生 `reg query /s` 全量 dump + 内存过滤 | **17.7 秒** |

> ⚠️ **`reg query /f` 不能跨反斜杠匹配键名。**
> `reg query 'HKCU\Software\Classes' /s /f 'shell\open\command' /k` **永远返回 0 条**，
> 因为 `/f` 只匹配**单层**键名。正确做法是 `/s` 全量 dump（约 25k 行）后按
> `\shell\open\command$` 在内存里过滤。

**规则**：注册表全量扫描一律优先 `reg query`；只在访问单个已知键时才用 PowerShell cmdlet。

## 边界

| 限制 | 原因 |
|---|---|
| **默认程序无法脚本设置** | UserChoice 的 `Deny SetValue` ACE + Hash；官方 COM API 在 Win10+ 返回 `0x80070002` 且不生效 |
| **`rclone mount` 需要管理员** | 依赖 WinFsp 驱动安装 |
| **便携软件不出现在系统应用列表** | 天生如此，必须目录扫描盘点 |
| **首次运行可能被 SmartScreen 拦** | 未签名程序，属正常，需手动允许 |
| **不能操作提权窗口** | Windows 既定边界 |
| **卸载后注册表残留不会自动清** | 便携版无卸载程序，须主动跑关联残留检查 |

## 安全纪律

- **只从官方发布页下载。** 第三方"绿色版/破解版"是恶意软件主要载体
- **务必校验 SHA256。** 脚本能校验，但哈希值要从发布页自己取——不要盲信某个来源
- **绝不把含凭据的文件放进公开仓库**：NAS 地址、用户名、`rclone.conf`、
  网络驱动器映射导出、浏览器书签备份都属于私有信息
- 交付前确认：文档与脚本里**没有**真实主机名、内网 IP、账号名、路径中的用户名
