# TcpQuality Auto

<p align="center">
  <strong>Debian VPS 的 TcpQuality 定时测试 + Telegram 自动推送 + systemd 管理工具</strong>
</p>

<p align="center">
  一次安装，按自定义时区每天自动执行 TcpQuality，并通过 Telegram 接收测试结果。
</p>

<p align="center">
  <a href="https://github.com/shaolonger/tcpquality-auto">GitHub</a>
  ·
  <a href="https://github.com/ibsgss/TcpQuality">TcpQuality</a>
</p>

---

## 简介

`tcpquality-auto` 是一个面向 Debian VPS 的 TcpQuality 自动化管理脚本。

它将 [TcpQuality](https://github.com/ibsgss/TcpQuality) 封装为长期、无人值守的 `systemd` 定时任务，并提供完整的中文管理菜单和命令行管理方式。

安装时只需配置：

- VPS / 节点名称
- 定时任务时区
- 每天执行时间
- Telegram Bot Token
- Telegram Chat ID
- Telegram Topic Thread ID（可选）
- 是否通过 Telegram 发送完整测试日志

安装完成后，服务器会按照指定时间自动执行 TcpQuality，并将测试结果推送到 Telegram。

适合拥有多台、分布在不同国家或地区 VPS 的用户，用于定期观察网络线路质量。

> [!NOTE]
> 本项目不是 TcpQuality 官方项目。
>
> `tcpquality-auto` 负责自动调度、systemd 管理、Telegram 通知和日志管理；实际网络测试能力来自 [TcpQuality](https://github.com/ibsgss/TcpQuality)。

---

## 功能特性

- 一键交互式安装
- 中文管理菜单
- 自动创建 `systemd service`
- 自动创建 `systemd timer`
- 安装后提供全局 `tcpquality-auto` 管理命令
- 每天定时执行 TcpQuality
- 支持自定义 IANA 时区
- 不修改 VPS 自身系统时区
- 使用 TcpQuality `--all` 完整测试模式
- 支持 Telegram 私聊
- 支持 Telegram 群组
- 支持 Telegram Forum / Topic
- 自动发送测试完成 / 失败摘要
- 自动尝试提取 TcpQuality 在线结果 URL
- 可选择是否发送完整测试日志附件
- **完整日志附件默认不发送**
- 完整日志始终保存在 VPS 本地
- Telegram 请求内置基础重试
- 单次测试 55 分钟超时保护
- systemd 非交互环境固定使用 `TERM=xterm`
- 默认保留最近 14 天测试日志
- 支持立即手动测试
- 支持启动 / 停止 / 重启定时任务
- 支持查看状态
- 支持查看 systemd 与 TcpQuality 日志
- 支持查看下一次执行时间
- 支持修改配置
- 支持停止并卸载
- 更新配置时保留原有 Timer 启停状态

---

# 快速安装

项目地址：

```text
https://github.com/shaolonger/tcpquality-auto
```

## 推荐安装方式

```bash
curl -fsSL \
  "https://raw.githubusercontent.com/shaolonger/tcpquality-auto/main/tcpquality-auto-install.sh" \
  -o /tmp/tcpquality-auto-install.sh

sudo bash /tmp/tcpquality-auto-install.sh
```

首次运行会进入中文管理菜单：

```text
============================================================
      TcpQuality Auto 管理面板
============================================================
状态：未安装
============================================================

1) 安装 / 更新
2) 立即执行一次测试
3) 查看状态
4) 查看日志
5) 修改配置
6) 启动 / 恢复定时任务
7) 停止定时任务
8) 重启定时任务
9) 查看下一次执行时间
10) 停止并卸载
0) 退出
```

选择：

```text
1) 安装 / 更新
```

即可开始配置。

---

## Root 用户也可以直接执行

如果当前已经是 `root`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shaolonger/tcpquality-auto/main/tcpquality-auto-install.sh)
```

> [!TIP]
> 对普通用户更推荐前面的“先下载，再 `sudo bash`”方式。
>
> 这样既避免进程替换在部分 `sudo` 环境中的 `/dev/fd/*` 兼容问题，也方便执行前自行检查脚本内容。

---

## Git Clone

```bash
git clone https://github.com/shaolonger/tcpquality-auto.git

cd tcpquality-auto

sudo bash tcpquality-auto-install.sh
```

---

# 系统要求

主要面向：

- Debian
- Bash
- systemd
- root 权限或可使用 `sudo`
- VPS 能够访问 TcpQuality
- VPS 能够访问 Telegram Bot API

安装器会检查并按需安装：

```text
curl
ca-certificates
coreutils
tzdata
```

同时会检查：

```text
curl
timeout
systemctl
systemd-analyze
```

是否可用。

> [!NOTE]
> 非 Debian 系统会显示警告并继续尝试，但目前不保证完整兼容。

---

# 安装配置

选择：

```text
1) 安装 / 更新
```

后，会依次进行以下配置。

---

## 1. 服务器名称

示例：

```text
服务器名称 [hostname]: LAX-01
```

建议给不同 VPS 使用容易识别的名称，例如：

```text
HKG-01
TYO-01
SIN-01
LAX-01
NYC-01
LON-01
FRA-01
AMS-01
```

该名称会出现在 Telegram 消息中：

```text
✅ TcpQuality 测试完成

服务器：LAX-01
```

因此多台 VPS 可以共用一个 Telegram Bot，而不会混淆测试来源。

---

## 2. 定时任务时区

默认：

```text
Asia/Shanghai
```

支持标准 IANA 时区，例如：

```text
Asia/Shanghai
Asia/Hong_Kong
Asia/Tokyo
Asia/Singapore

America/Los_Angeles
America/New_York

Europe/London
Europe/Berlin
Europe/Amsterdam

UTC
```

脚本会检查：

```text
/usr/share/zoneinfo/
```

确认时区是否存在。

如果不确定，可以执行：

```bash
timedatectl list-timezones
```

---

## 自定义时区不会改变 VPS 系统时区

例如 VPS 当前系统时区：

```text
America/Los_Angeles
```

但 TcpQuality Auto 设置为：

```text
定时任务时区：Asia/Shanghai
执行时间：20:30
```

则任务固定按照：

```text
北京时间每天 20:30
```

执行。

VPS 本身仍然保持：

```text
America/Los_Angeles
```

这非常适合跨国家、多地区 VPS 统一按照同一时区进行晚高峰测试。

---

## 3. 每天执行时间

默认：

```text
20:30
```

使用 24 小时制：

```text
HH:MM
```

例如：

```text
20:30
23:05
08:00
```

安装器会通过：

```bash
systemd-analyze calendar
```

验证最终生成的定时表达式。

---

# Telegram 配置

## 4. Bot Token

在 Telegram 中通过：

```text
@BotFather
```

创建 Bot 并获取 Token。

格式通常类似：

```text
1234567890:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

安装时：

```text
Bot Token:
```

终端不会回显 Token。

配置最终保存在：

```text
/etc/tcpquality-auto.conf
```

并自动设置权限：

```text
600
```

即只有 root 可以读取或修改。

> [!WARNING]
> Bot Token 相当于 Telegram Bot 的密码。
>
> 不要把真实 Token 提交到 GitHub、Issue、README、截图或公开日志中。

---

## 5. Chat ID

私人聊天通常类似：

```text
123456789
```

Telegram 群组通常类似：

```text
-1001234567890
```

安装器会向填写的目标发送 Telegram 测试消息：

```text
✅ TcpQuality Auto Telegram 配置测试成功

服务器：LAX-01
计划：每天 20:30
时区：Asia/Shanghai
```

如果测试发送失败，安装过程会停止并提示检查：

- Bot Token
- Chat ID
- Thread ID
- VPS 到 `api.telegram.org` 的网络连通性

---

## 6. Telegram Topic Thread ID

如果目标群组启用了 Telegram Forum / Topics，可以填写：

```text
Topic Thread ID
```

不使用 Topic：

```text
直接回车
```

即可。

如果以前已经配置了 Thread ID，重新配置时输入：

```text
-
```

可以清空该设置。

---

# 7. 是否发送完整测试日志

安装器会询问：

```text
是否通过 Telegram 发送完整测试日志？[y/N]
```

默认：

```text
N
```

也就是：

**默认不发送完整测试日志附件。**

---

## 默认模式：只发送结果摘要

选择：

```text
N
```

Telegram 会收到：

```text
✅ TcpQuality 测试完成

服务器：LAX-01
开始：2026-08-08 20:30:01 CST
完成：2026-08-08 20:38:35 CST

在线结果：
https://tcpquality.ibsgss.uk/...
```

不会额外收到：

```text
TcpQuality 完整测试日志
```

附件。

这也是推荐设置，可以减少 Telegram 消息数量。

---

## 开启完整日志附件

选择：

```text
Y
```

则测试成功后，在摘要消息之外还会额外发送：

```text
✅ LAX-01 · TcpQuality 完整测试日志
```

测试失败时也会发送：

```text
❌ LAX-01 · TcpQuality 错误日志
```

---

## 不发送 Telegram 日志 ≠ 不保存日志

无论这个选项是：

```text
Y
```

还是：

```text
N
```

完整日志都会保存在 VPS：

```text
/var/log/tcpquality-auto/
```

因此推荐大多数用户保持默认：

```text
N
```

需要排查问题时执行：

```bash
sudo tcpquality-auto logs
```

即可。

---

# 安装完成后

安装器会创建：

```text
/etc/tcpquality-auto.conf
/usr/local/sbin/tcpquality-auto
/usr/local/sbin/tcpquality-auto-run.sh
/etc/systemd/system/tcpquality-auto.service
/etc/systemd/system/tcpquality-auto.timer
/var/log/tcpquality-auto/
```

其中：

```text
/usr/local/sbin/tcpquality-auto
```

就是之后日常使用的管理命令。

因此以后无需再次寻找安装脚本，只需：

```bash
sudo tcpquality-auto
```

即可进入管理面板。

---

# 管理面板

安装后执行：

```bash
sudo tcpquality-auto
```

显示：

```text
============================================================
      TcpQuality Auto 管理面板
============================================================
状态：已安装 | Timer：运行 | 节点：LAX-01
============================================================

1) 安装 / 更新
2) 立即执行一次测试
3) 查看状态
4) 查看日志
5) 修改配置
6) 启动 / 恢复定时任务
7) 停止定时任务
8) 重启定时任务
9) 查看下一次执行时间
10) 停止并卸载
0) 退出
```

---

# 命令行管理

除了菜单，也可以直接执行命令。

| 功能 | 命令 |
|---|---|
| 打开管理菜单 | `sudo tcpquality-auto` |
| 安装 / 更新 | `sudo tcpquality-auto install` |
| 修改配置 | `sudo tcpquality-auto config` |
| 查看状态 | `sudo tcpquality-auto status` |
| 查看日志 | `sudo tcpquality-auto logs` |
| 立即测试 | `sudo tcpquality-auto run` |
| 启动任务 | `sudo tcpquality-auto start` |
| 停止任务 | `sudo tcpquality-auto stop` |
| 重启 Timer | `sudo tcpquality-auto restart` |
| 下一次执行 | `sudo tcpquality-auto next` |
| 停止并卸载 | `sudo tcpquality-auto uninstall` |
| 查看帮助 | `tcpquality-auto help` |

同样支持：

```text
--install
--config
--status
--logs
--run
--start
--stop
--restart
--next
--uninstall
--help
```

---

# 查看状态

执行：

```bash
sudo tcpquality-auto status
```

会显示：

```text
服务器
执行时间
任务时区
Chat ID
Thread ID
Bot Token 配置状态
TG 完整日志设置

Timer 是否设置开机启用
Timer 当前是否运行
TcpQuality 是否正在测试

最近一次 Service 状态
下一次执行时间
```

Bot Token 不会明文显示。

例如：

```text
TG 完整日志：不发送
```

或：

```text
TG 完整日志：发送
```

---

# 立即执行一次测试

```bash
sudo tcpquality-auto run
```

如果当前已经有 TcpQuality 测试正在运行，脚本会检测并阻止重复启动。

测试完成后自动：

1. 保存本地日志；
2. 发送 Telegram 摘要；
3. 尝试附带在线结果 URL；
4. 如果启用了 `SEND_FULL_LOG=Y`，再发送完整日志附件。

---

# 日志管理

进入：

```bash
sudo tcpquality-auto
```

选择：

```text
4) 查看日志
```

会显示：

```text
1) 查看最近 systemd 运行日志
2) 实时跟踪 systemd 日志
3) 查看最新 TcpQuality 测试日志
4) 列出本地测试日志文件
5) 查看 Timer 日志
0) 返回上级菜单
```

---

## 命令行快速查看

```bash
sudo tcpquality-auto logs
```

会同时显示：

- 最近 150 行 systemd Service 日志
- 最新 TcpQuality 测试日志最后 120 行

---

## 本地日志目录

```text
/var/log/tcpquality-auto/
```

通常包含：

```text
YYYYMMDD-HHMMSS.raw.log
YYYYMMDD-HHMMSS.log
```

其中：

### `.raw.log`

保存 TcpQuality 原始输出。

### `.log`

移除常见 ANSI 控制字符，更适合人工查看和 Telegram 发送。

---

## 日志保留时间

默认自动清理：

```text
14 天以前
```

的测试日志。

---

# 修改配置

可以通过菜单：

```text
5) 修改配置
```

或命令：

```bash
sudo tcpquality-auto config
```

已有配置会作为默认值显示：

```text
服务器名称 [LAX-01]:
定时任务时区 [Asia/Shanghai]:
每天执行时间 [20:30]:
Bot Token [直接回车保留原 Token]:
Chat ID [123456789]:
Topic Thread ID [...]
是否通过 Telegram 发送完整测试日志？[y/N]
```

不需要修改的项目：

```text
直接回车
```

即可保留。

---

## 修改配置会保持原来的 Timer 状态

如果修改前 Timer 正常启用：

```text
修改完成后继续保持启用
```

如果修改前已经通过：

```bash
sudo tcpquality-auto stop
```

暂停：

```text
修改完成后仍保持停止
```

不会因为修改 Telegram 或时间配置而意外重新启动定时任务。

---

# 启动定时任务

```bash
sudo tcpquality-auto start
```

效果：

```text
启动 Timer
+
设置开机自动启用
```

VPS 重启后 Timer 会自动恢复。

---

# 停止定时任务

```bash
sudo tcpquality-auto stop
```

效果：

- 停止 Timer
- 禁用 Timer 开机启动
- 如果当前 TcpQuality 正在测试，同时停止该测试

但不会删除：

- 配置
- Telegram 参数
- Runner
- systemd 文件
- 历史日志

以后可执行：

```bash
sudo tcpquality-auto start
```

恢复。

---

# 重启定时任务

```bash
sudo tcpquality-auto restart
```

如果 TcpQuality 当前正在运行，会先停止当前测试。

如果 Timer 原本已经设置为开机启用：

```text
重启后继续保持启用
```

如果 Timer 原本没有开机启用：

```text
只重启当前 Timer，不会自动改成 enabled
```

需要恢复开机自动运行时执行：

```bash
sudo tcpquality-auto start
```

---

# 查看下一次执行时间

```bash
sudo tcpquality-auto next
```

如果 Timer 正在运行，会调用：

```bash
systemctl list-timers tcpquality-auto.timer --all
```

显示下一次计划执行时间。

如果 Timer 已停止，则提示先执行：

```bash
sudo tcpquality-auto start
```

---

# 停止并卸载

通过菜单：

```text
10) 停止并卸载
```

或：

```bash
sudo tcpquality-auto uninstall
```

脚本会要求二次确认。

确认后会：

- 停止并禁用 Timer
- 停止正在运行的 TcpQuality
- 删除配置文件
- 删除 Runner
- 删除 systemd Service
- 删除 systemd Timer
- 删除全局 `tcpquality-auto` 管理命令
- 执行 `systemctl daemon-reload`

随后会再次询问：

```text
是否同时删除历史日志？
```

默认：

```text
不删除
```

---

# systemd 配置

Timer 类似：

```ini
[Timer]
OnCalendar=*-*-* 20:30:00 Asia/Shanghai
Persistent=true
AccuracySec=1s
Unit=tcpquality-auto.service
```

---

## Persistent=true

当前默认：

```ini
Persistent=true
```

意味着如果 VPS 在计划执行时间处于关机状态，之后恢复运行，systemd 可能补执行错过的任务。

例如：

```text
计划：20:30
服务器：20:00 关机
服务器：22:00 开机
```

systemd 可能在恢复后补执行当天错过的测试。

---

# 非交互 systemd 环境兼容

TcpQuality 在 systemd 定时环境中没有普通交互式终端。

当前版本会同时设置：

```ini
Environment=TERM=xterm
```

以及：

```bash
TERM=xterm timeout ...
```

避免 TcpQuality 在非交互环境中因终端类型问题提前退出。

因此无论：

```text
systemd timer 自动触发
```

还是：

```bash
sudo tcpquality-auto run
```

都会使用一致的终端环境。

---

# TcpQuality 执行模式

当前 Runner 执行：

```bash
bash <(
  curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 120 \
    https://tcpquality.ibsgss.uk/run
) --all
```

也就是：

```text
TcpQuality --all
```

完整测试模式。

---

# 超时保护

单次 TcpQuality 最大运行时间：

```text
55 分钟
```

Runner 使用：

```bash
timeout --signal=TERM --kill-after=30s 55m
```

systemd Service 还设置：

```ini
TimeoutStartSec=1h
```

形成第二层保护。

---

# Telegram 请求设置

文字消息：

```text
连接超时：10 秒
最大请求时间：30 秒
```

日志文件：

```text
连接超时：10 秒
最大请求时间：120 秒
```

Curl 使用：

```text
--retry 3
--retry-delay 2
```

进行基础网络错误重试。

---

# 多台 VPS 使用

多台 VPS 可以共用：

```text
Telegram Bot Token
Telegram Chat ID
```

建议只设置不同的：

```text
SERVER_NAME
```

例如：

| 地区 | 节点名称 |
|---|---|
| 香港 | `HKG-01` |
| 东京 | `TYO-01` |
| 新加坡 | `SIN-01` |
| 洛杉矶 | `LAX-01` |
| 纽约 | `NYC-01` |
| 伦敦 | `LON-01` |
| 法兰克福 | `FRA-01` |
| 阿姆斯特丹 | `AMS-01` |

架构：

```text
HKG-01 ───┐
TYO-01 ───┤
SIN-01 ───┤
LAX-01 ───┼────► Telegram Bot ────► 你
NYC-01 ───┤
LON-01 ───┤
FRA-01 ───┘
```

---

## 多 VPS 是否需要错峰？

如果服务器数量较多，推荐适当错峰。

例如：

```text
HKG-01   20:30
TYO-01   20:32
SIN-01   20:34
LAX-01   20:36
NYC-01   20:38
LON-01   20:40
FRA-01   20:42
```

这样可以：

- 避免大量服务器同时占用 TcpQuality 测试节点
- 减少同一个 Telegram Chat 短时间集中收消息
- 降低 Telegram 限流概率
- 更方便按顺序查看结果

---

# 配置文件

配置保存在：

```text
/etc/tcpquality-auto.conf
```

内容类似：

```bash
SERVER_NAME=LAX-01
SCHEDULE_TZ=Asia/Shanghai
RUN_TIME=20:30
TG_BOT_TOKEN=1234567890:AAxxxxxxxx
TG_CHAT_ID=123456789
TG_THREAD_ID=
SEND_FULL_LOG=N
```

其中：

```text
SEND_FULL_LOG=N
```

表示：

```text
不通过 Telegram 发送完整日志附件
```

```text
SEND_FULL_LOG=Y
```

表示：

```text
发送完整日志附件
```

脚本使用：

```bash
printf '%q'
```

保存 Bash 可安全重新 `source` 的变量内容。

配置文件权限：

```text
600
```

> [!WARNING]
> `/etc/tcpquality-auto.conf` 包含 Telegram Bot Token。
>
> 请勿上传到 GitHub 或公开分享完整内容。

---

# 文件位置

| 路径 | 用途 |
|---|---|
| `/usr/local/sbin/tcpquality-auto` | 管理脚本 |
| `/usr/local/sbin/tcpquality-auto-run.sh` | TcpQuality 实际执行 Runner |
| `/etc/tcpquality-auto.conf` | 配置与 Telegram 参数 |
| `/etc/systemd/system/tcpquality-auto.service` | systemd Service |
| `/etc/systemd/system/tcpquality-auto.timer` | systemd Timer |
| `/var/log/tcpquality-auto/` | 测试日志 |

---

# 更新 TcpQuality Auto

重新下载最新版本：

```bash
curl -fsSL \
  "https://raw.githubusercontent.com/shaolonger/tcpquality-auto/main/tcpquality-auto-install.sh" \
  -o /tmp/tcpquality-auto-install.sh
```

执行：

```bash
sudo bash /tmp/tcpquality-auto-install.sh
```

然后选择：

```text
1) 安装 / 更新
```

已有配置会自动读取。

直接回车即可保留旧值。

更新后：

```text
/usr/local/sbin/tcpquality-auto
```

也会同步更新为当前脚本版本。

---

# 常见问题

## 为什么不用 cron？

因为 systemd timer 更适合长期服务器任务：

- 支持独立时区
- 可以查看下一次运行时间
- 可以查看服务状态
- 可以统一管理进程
- 可以设置超时
- 可以方便启停
- 可以统一查看日志

---

## 为什么不用 `yes | ...` 自动回答多个 y？

TcpQuality 已支持非交互：

```text
--all
```

因此无需使用：

```text
yes
expect
printf
```

模拟键盘输入。

---

## 为什么定时任务必须设置 `TERM=xterm`？

systemd 定时任务没有普通交互式 TTY。

TcpQuality 的部分终端操作在非交互环境下可能受到 `TERM` 影响。

因此当前版本显式设置：

```text
TERM=xterm
```

保证定时执行和手动执行行为一致。

---

## 为什么默认不发送完整日志？

完整 TcpQuality 日志通常比较长。

绝大多数日常场景只需要：

```text
测试成功 / 失败
节点名称
测试时间
在线报告链接
```

因此默认：

```text
SEND_FULL_LOG=N
```

可以减少 Telegram 消息和附件数量。

出现异常时仍然可以：

```bash
sudo tcpquality-auto logs
```

查看 VPS 本地完整日志。

---

## 如何开启 Telegram 完整日志？

执行：

```bash
sudo tcpquality-auto config
```

在：

```text
是否通过 Telegram 发送完整测试日志？
```

输入：

```text
y
```

即可。

---

## Timer 停止后 VPS 重启会不会自动恢复？

如果使用：

```bash
sudo tcpquality-auto stop
```

脚本会：

```text
stop + disable
```

所以 VPS 重启后不会自动恢复。

需要：

```bash
sudo tcpquality-auto start
```

重新启用。

---

## 修改配置为什么没有重新启动 Timer？

如果配置修改前 Timer 已停止，脚本会保持原来的停止状态。

这是为了避免用户只是修改 Telegram 参数，却意外重新启用测速任务。

---

## Telegram 测试消息发送失败怎么办？

先检查：

```bash
curl -I https://api.telegram.org
```

然后确认：

- Bot Token 是否正确
- Chat ID 是否正确
- Thread ID 是否正确
- Bot 是否已经加入目标群组
- Bot 是否拥有发送消息权限
- VPS 是否能访问 Telegram

---

## 如何判断 Timer 是否正常？

```bash
sudo tcpquality-auto status
```

或：

```bash
sudo tcpquality-auto next
```

---

## 如何立即验证完整流程？

```bash
sudo tcpquality-auto run
```

然后：

```bash
sudo tcpquality-auto logs
```

并检查 Telegram。

---

# 故障排查

## 查看 Service 状态

```bash
systemctl status tcpquality-auto.service --no-pager
```

---

## 查看 Timer 状态

```bash
systemctl status tcpquality-auto.timer --no-pager
```

---

## 查看最近 Service 日志

```bash
journalctl -u tcpquality-auto.service -n 200 --no-pager
```

---

## 查看 Timer 日志

```bash
journalctl -u tcpquality-auto.timer -n 100 --no-pager
```

---

## 检查 TcpQuality 下载

```bash
curl -v https://tcpquality.ibsgss.uk/run
```

---

## 检查 Telegram 连通性

```bash
curl -I https://api.telegram.org
```

---

## 查看配置

```bash
sudo cat /etc/tcpquality-auto.conf
```

> [!WARNING]
> 上述命令会显示 Bot Token。
>
> 不要将完整输出粘贴到公开 Issue、聊天或截图中。

---

# 关于 TcpQuality rootfs

TcpQuality 当前默认运行过程可能需要下载临时 rootfs。

因此第一次执行或上游环境发生变化时，可能看到较大的下载过程。

这属于 TcpQuality 上游运行机制，不是 Telegram 或 systemd 本身的问题。

如果你只是进行频繁、轻量化的晚高峰监测，可以根据实际需求进一步考虑使用更轻量的测试模式，而不是高频执行完整 `--all`。

---

# 安全说明

## Telegram Bot Token

Bot Token 应视为敏感凭据。

不要：

- 提交到 GitHub
- 放入 README
- 贴到 Issue
- 分享完整配置文件
- 在截图中显示

如果 Token 泄漏，请立即通过 BotFather 撤销或重新生成。

---

## 多台 VPS 共用一个 Bot

由你控制的多台 VPS 可以共用一个 Telegram Bot。

但 VPS 越多：

```text
Token 保存位置越多
=
潜在攻击面越大
```

建议：

- 只部署在可信 VPS
- 使用 SSH Key
- 及时更新系统
- 减少不必要开放端口
- 避免运行来源不明的 root 脚本

---

## 远程脚本执行风险

`tcpquality-auto` 会在线获取并执行：

```text
https://tcpquality.ibsgss.uk/run
```

因此 TcpQuality 上游发生变化后，后续任务会运行更新后的上游代码。

对于高安全等级环境，可以考虑：

- 固定 TcpQuality Git Commit
- 固定发布版本
- 下载后校验 SHA256
- 审查上游代码后再升级
- 在专用测试 VPS 上运行

---

# 项目结构

```text
tcpquality-auto/
├── README.md
└── tcpquality-auto-install.sh
```

项目仓库：

```text
https://github.com/shaolonger/tcpquality-auto
```

---

# Roadmap

后续可考虑：

- [ ] 提供轻量晚高峰测试模式
- [ ] 支持 `--no-rootfs` 模式
- [ ] 自定义 TcpQuality 测试参数
- [ ] 自定义日志保留天数
- [ ] 自动随机错峰
- [ ] Telegram `429 retry_after` 精确处理
- [ ] 异常阈值检测
- [ ] 与历史基线对比
- [ ] 自动生成晚高峰线路日报
- [ ] 多 VPS 集中汇总
- [ ] Webhook / Discord 等其他通知方式
- [ ] 固定 TcpQuality 上游版本或 Commit

---

# 致谢

感谢 [ibsgss/TcpQuality](https://github.com/ibsgss/TcpQuality) 提供网络质量测试能力。

`tcpquality-auto` 主要解决：

```text
如何让 TcpQuality
在多台 VPS 上
按照指定时区每天自动运行
并自动把测试结果推送到 Telegram
```

这一自动化运维场景。

---

# Disclaimer

本项目仅用于：

- 网络质量测试
- VPS 运维监控
- 学习研究

测试结果可能受到以下因素影响：

- VPS 所在网络
- 测试节点
- 国际出口
- 运营商路由
- 网络拥塞
- 测试时间
- TcpQuality 上游实现变化

测试结果仅代表测试发生时的网络状态。

使用者应自行评估：

- 测速产生的流量
- CPU / 网络资源消耗
- 第三方服务依赖
- 远程脚本执行风险
- Telegram Bot Token 安全

使用本项目即代表你理解并自行承担相关风险。
