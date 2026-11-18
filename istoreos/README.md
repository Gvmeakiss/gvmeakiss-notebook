# iStoreOS 优化（x86_64 软路由）

更新日期：2026-11-18。

一台 x86_64 软路由从 **iStoreOS 24.10.8** 升到 **25.12.6** 的完整改造记录：系统升级、磁盘分区、Passwall 重装、Docker/NAS 恢复、安全收口。目标是**下次换机或重装时能照着再做一遍**，所以每个动作都带判据、命令和已知坑。

本目录只放方法与通用配置，**不含订阅、节点、凭据、UUID、路由器备份**。Passwall 的分流规则与参数见 [`../passwall/`](../passwall/README.md)。

## 适用环境

| 项 | 本次环境 |
| --- | --- |
| 设备 | x86_64 四网口小主机（示例：N5000，64 GB SSD，EFI 启动） |
| 系统 | iStoreOS 24.10.8 → 25.12.6（构建 2026110611） |
| 包管理 | opkg → apk（25.12 起） |
| 代理 | Passwall 26.11.11 + xray-core 26.10.21 |
| 容器 | Docker 29.6.1 + dpanel（仅 LAN） |
| 存储 | 单盘：sda1 EFI 128M、sda2 rom 256M、sda3 overlay、sda4 data |

## 优化清单

| 类别 | 问题 | 动作 | 结果 |
| --- | --- | --- | --- |
| 系统 | 24.10.8 已是该分支最后一版；25.12.6 含安全修复 | 跨大版本重装到 25.12.6（EFI 镜像） | 系统更新，内核/软件源进入 25.12 |
| 磁盘 | 系统分区只有 2 GiB，数据分区 53.5G | sda3 扩到 **16 GiB**，sda4 重建为 **38.6G** | `/overlay` 可用 15.6G，数据可用 36.2G |
| 代理 | 升级后 Passwall 和 xray 都被清空 | apk 源重装 Passwall 26.11.11 + xray-core，恢复配置与名单 | 分流、DNS、订阅全部恢复 |
| DNS/分流 | 见 [`../passwall/`](../passwall/README.md) | 大陆白名单、chinadns-ng、可信 DNS 走代理 | 国内直连、海外走节点 |
| 安全 | 25.12 默认对 WAN 放行易有云 8897、unetd UDP 51819；iStore 后台装的 FastNet 还会放行 3200 | 删 `firewall.linkease`、停用 unetd、删 `firewall.fastnet` | WAN 入站只剩 DHCP/ICMP 等基础放行 |
| 容器 | 升级后 dockerd 与 dpanel 丢失，但数据盘还在 | 装回 docker/dockerman，恢复数据目录与容器 | dpanel 自动恢复，只绑 `192.168.100.1:8807` |
| 数据 | `/mnt` 是 tmpfs，旧软链接重启即失效 | 用 fstab 把数据分区挂到 `/mnt/data` | 重启后 Docker 数据目录稳定可用 |
| 软件包 | 25.12.6 自带包落后于软件源，82 个可升级 | `apk upgrade` 后重启验收 | 0 个待升级，LuCI/curl/dnsmasq 等已更新 |
| 监控 | smartd 已安装但未启用 | 启用 smartd，健康/错误/自检/温度告警写入持久日志 | 开机自启，日志在 `/mnt/data/logs/smartd.log` |

## 关键结论（复用前先看）

1. **24.10 → 25.12 不能“保留软件包”升级**。官方明确不支持：配置可以备份恢复，已安装的包必须重装。opkg 的 ipk 在 25.12 上不可用，Passwall 要换 apk。
2. **EFI 机器必须用 `x86_64_efi/` 的镜像**。`x86_64/` 的 BIOS 镜像会被 sysupgrade 以“non EFI image”拒绝；强行刷会破坏引导。
3. **配置恢复不要依赖 `sysupgrade -f`**。实测刷完仍是默认配置，最后是手工解包恢复 `/etc/config/passwall` 与 `/etc/passwall/rules`。
4. **系统分区可以在线扩容**。已挂载的 sda3 用交互式 `parted resizepart`（确认 “Yes”）改分区表，再 `resize2fs` 在线扩文件系统；前提是先备份并删除/缩小它后面的数据分区。
5. **`/mnt` 是 tmpfs**。在里面建的软链接重启就没了；持久化要用 `/etc/config/fstab` 挂载数据分区。
6. **dpanel 默认发布到 `0.0.0.0`**。重建容器时指定 `-p 192.168.100.1:8807:8080`，只监听 LAN。
7. **25.12 默认服务仍会开 WAN 口**。易有云 8897、unetd 51819 是显式 ACCEPT；不用就关。

## 本次实测结果

| 检查项 | 结果 |
| --- | --- |
| 系统 | iStoreOS 25.12.6 / 2026110611 |
| 系统分区 | 15.7G，可用 15.6G |
| 数据分区 | 38.6G，可用 36.2G |
| Passwall | 26.11.11-r1 + xray-core 26.10.21-r1，自启 |
| 分流 | 直连 144 / 代理 66，DNS 223.5.5.5 + 可信 1.1.1.1（TCP，经代理） |
| 连通性 | Google 204 / 0.23–0.51s、百度 200 / 0.12s、GitHub 200（偶发首连偏慢）、ChatGPT 403（链路可达） |
| 出口 | IPv4 `loc=HK` |
| Docker | 29.6.1，dpanel Up，LAN 200，数据约 456 MB |
| 软件包 | 82 个升级完成，0 个待升级 |
| 监控 | smartd 运行，S95 自启，日志 `/mnt/data/logs/smartd.log` |
| 安全 | WAN 无 8897/51819/1688/8807 放行；unetd 停用 |

静态检查不等于设备已加载；上表是 2026-11-18 单次实测，换线路、换固件或换节点后要重新验收。

## 与 `passwall/` 的分工

| 目录 | 负责 |
| --- | --- |
| [`../passwall/`](../passwall/README.md) | Passwall 的分流模式、DNS、名单、端口边界与参数基线 |
| 本目录 | 系统版本、磁盘分区、升级/重装流程、Docker/NAS、安全收口与验收 |

两个目录共用同一台设备的一次改造记录，但可以独立复用：只升级系统就看本目录，只调分流就看 `passwall/`。

## 文件

| 文件 | 用途 |
| --- | --- |
| [`README.md`](./README.md) | 优化清单、结论、实测与边界 |
| [`使用指南.md`](./使用指南.md) | 升级、磁盘调整、重装 Passwall、Docker 恢复、验收与回滚的完整步骤 |
| [`AGENTS.md`](./AGENTS.md) | 给 AI 的改动协议、判据与红线 |
| [`scripts/verify.sh`](./scripts/verify.sh) | 只读验收脚本（版本、分区、DNS、WAN 端口、服务） |
| [`tests/istoreos.test.mjs`](./tests/istoreos.test.mjs) | 离线检查：文档一致性、敏感信息、链接 |

## 回滚原则

- **系统**：重刷同版本 EFI 镜像；配置用升级前的 `sysupgrade -b` 包恢复。
- **磁盘**：分区操作前必须把数据分区完整复制到另一台机器；本项目的扩容步骤不接受“没有副本”的执行。
- **服务**：保留上一个可用的 apk/容器版本；出问题先停服务、再回滚单个组件，不要整机重装。

## 来源

- 固件：<https://fw.koolcenter.com/iStoreOS/>（`x86_64_efi/` 为 EFI 镜像）
- 版本说明：iStoreOS 25.12 讨论区（opkg → apk、不支持保留软件包升级）
- Passwall 二进制：<https://github.com/Openwrt-Passwall/openwrt-passwall> 与 <https://github.com/moetayuko/openwrt-passwall-build>
- 分流规则与参数：本仓库 [`../passwall/`](../passwall/README.md)
