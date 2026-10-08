# win-ai-gaming-setup · 一条命令把新机器配成 AI 开发 + 游戏机

方法论的判断清单见 [SKILL.md](./SKILL.md)。这里只讲**怎么跑、跑完什么样、坏了怎么办**。

```powershell
# 在一台新 Windows 机器上（建议：PowerShell 7，管理员）
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1
```

跑完输出一张 PASS/FAIL 表；退出码 0 = 选中的阶段全过，非 0 = 有阶段失败（便于脚本串联）。

---

## 六个阶段

| 阶段 | 内容 | 管理员 | 可回滚 |
|---|---|---|---|
| `check` | **引导安装 + 检查**：PowerShell 7 / Scoop / git / 7-Zip / 长路径 / 开发者模式 / github 连通 / 磁盘 / 提权 / build+UBR | 部分 | — |
| `dev` | Scoop 装 `python node go cmake dotnet mingw uv` + **VS Code / Windows Terminal** + 国内镜像（pip/npm/go/cargo/HF）；修 PATH、Store 存根、凭据助手 | 部分 | 是（Scoop 卸载） |
| `apps` | 按 `apps.json` 装便携软件：下载 → **SHA256 校验** → 解压 → 折叠目录 → 快捷方式 / PATH | 否 | 是（删目录） |
| `tune` | **先快照**，再改：GameDVR 关闭、MMCSS 调优、**关闭广告推荐/开始菜单联网搜索/遥测**；（可选）高性能电源计划、鼠标加速 | 是 | 是（`compare-services.ps1 -Restore`） |
| `link` | 注册关联（`-RegisterAssociations`）+ 报告哪些类型需手动点一次 + 孤儿关联检查 | 否 | 是（有注册表备份） |
| `verify` | dev 环境 / 软件清单 / 输入法健康 / 服务基线漂移，四项验收 | 否 | — |

## 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `check,dev,apps,tune,link,verify` 任意组合 |
| `-Manifest` | `apps.json`（技能根目录） | 便携软件清单 |
| `-Destination` | `%USERPROFILE%\Apps` | 便携软件根目录 |
| `-SnapshotDir` | `<Destination>\_backup` | 快照与关联备份位置 |
| `-Languages` | `python,node,go,cmake,dotnet,mingw,uv` | 开发阶段要装的 Scoop 包 |
| `-NoEditor` | 关 | 跳过 VS Code + Windows Terminal |
| `-DisableMouseAcceleration` | 关 | 把鼠标加速曲线清零（FPS 习惯） |
| `-HighPerformancePowerPlan` | 关 | 打开才切高性能（笔记本费电） |
| `-RegisterAssociations` | 关 | 打开才写关联注册（只写 HKCU） |
| `-SkipTweaks` | 关 | 只快照、不改系统 |
| `-WhatIf` | — | 预演，什么都不改 |

常用组合：

```powershell
# 只看这台机器缺什么
pwsh -File scripts/setup.ps1 -Phase check

# 开发环境 + 软件（最常用）
pwsh -File scripts/setup.ps1 -Phase dev,apps

# 先看看 tune 要改什么
pwsh -File scripts/setup.ps1 -Phase tune -WhatIf

# 只验收
pwsh -File scripts/setup.ps1 -Phase verify
```

## 跑完必须做的三件事（脚本代替不了）

1. **重启，然后新开一个终端** —— PATH 与输入法栈都在登录时重建；不重启就下结论是最常见的误判
2. **手动点一次默认程序** —— Windows 的 `UserChoice` 有 Deny ACL + Hash 保护，脚本只能让程序出现在候选里。
   右键任意该类文件 → 打开方式 → 选择其他应用 → 选中 → 勾"始终使用此应用"（每个类型一次，长期有效）
3. **设备有故障码就复位** —— `pwsh -File scripts/reset-failed-devices.ps1 -Reset`（管理员）；
   仍不行的先"完全关机"断电，再装厂商驱动

## 坏了怎么回滚

```powershell
# 1) 对比：哪些被改了、哪些本来就这样
pwsh -File scripts/compare-services.ps1 -Snapshot "$env:USERPROFILE\Apps\_backup\services-snapshot.csv"

# 2) 预演回滚，确认改动项与预期一致
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -WhatIf

# 3) 回滚（可只挑一项）
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -Only TabletInputService
```

输入法坏了走专用路径：

```powershell
pwsh -File scripts/diagnose-ime.ps1            # 诊断：服务/进程/语言栏模式/IFEO/策略，给结论
pwsh -File scripts/diagnose-ime.ps1 -Repair    # 修复（管理员），之后必须重启
```

## 工具箱（同一目录，可单独用）

| 脚本 | 用途 |
|---|---|
| `snapshot-services.ps1 -OutDir <dir>` | 改动前拍照（只读） |
| `compare-services.ps1 -Snapshot <csv> [-Restore] [-Only X]` | 逐项对比 / 按基线回滚 |
| `diagnose-ime.ps1 [-Repair]` | 输入法故障诊断与修复 |
| `reset-failed-devices.ps1 [-Reset] [-Class X]` | 设备故障码分诊与复位 |
| `install-portable.ps1 -Manifest <json>` | 清单式便携安装（SHA256 必填） |
| `check-software.ps1 [-Json]` | 便携软件盘点 |
| `set-app-associations.ps1 [-Register -Apps @{}]` | 关联注册 / 现状报告 |
| `clean-orphan-associations.ps1 [-Clean]` | 卸载后的关联残留清理 |
| `audit-env.ps1` / `fix-env.ps1` / `setup-langs.ps1` / `verify-env.ps1` | 开发环境审计 / 修复 / 装语言 / 验收 |

## 这台机器上不做的事（有意为之）

- **不禁用任何服务** —— 按需启动的服务禁用后省不到性能，却会把输入法/相机/手柄搞坏
- **不关 UAC、不改 DPI、不动 Windows 更新策略** —— 这些是用户取舍，交给你决定
- **不装第三方"优化大师/加速器"** —— 本方案本身就是那类东西的安全替代

## 环境

- Windows 10/11 + PowerShell 7+
- `scoop` 缺失时 `dev` 阶段会自动安装（用户级，无需提权）
- `apps` 阶段的 `.7z` 资产需要 `7z`（`scoop install 7zip`）
- 脚本均为 ASCII-only（英文），文档为中文
