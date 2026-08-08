# TcpQuality Auto

<p align="center">
  <strong>Debian VPS 的 TcpQuality 定时测试 + Telegram 自动推送工具</strong>
</p>

<p align="center">
  一次交互式安装，自动创建 systemd 定时任务，按自定义时区每天执行 TcpQuality，并把测试结果与完整日志发送到 Telegram。
</p>

---

## 简介

`tcpquality-auto` 是一个面向 Debian VPS 的轻量自动化脚本，用于将 [TcpQuality](https://github.com/ibsgss/TcpQuality) 变成长期、无人值守的定时网络质量测试任务。

安装时只需要填写：

- VPS / 节点名称
- 定时任务时区
- 每天执行时间
- Telegram Bot Token
- Telegram Chat ID
- Telegram Topic Thread ID（可选）

脚本随后会自动创建 `systemd service` 和 `systemd timer`。

到达指定时间后，服务器会自动执行 TcpQuality 完整测试，并将：

1. 测试完成 / 失败摘要；
2. 可识别到的 TcpQuality 在线结果地址；
3. 完整测试日志文件；

发送到指定 Telegram 会话。

特别适合拥有多台、分布在不同国家和地区 VPS 的用户，用于长期观察线路质量变化。

> [!NOTE]
> 本项目不是 TcpQuality 官方项目。
> `tcpquality-auto` 仅负责自动调度、systemd 集成、Telegram 通知和日志管理，实际测试能力来自 TcpQuality 上游项目。

---

## 功能

- 一键交互式安装
- 自动检测并安装必要依赖
- 自动创建 `systemd service`
- 自动创建 `systemd timer`
- 每天定时执行 TcpQuality
- 支持自定义 IANA 时区
- 不需要修改 VPS 系统时区
- 使用 TcpQuality 完整测试模式
- 自动启用测速
- Telegram 私聊推送
- Telegram 群组推送
- Telegram Forum / Topic 推送
- 测试成功自动发送摘要
- 自动尝试提取在线结果 URL
- 自动发送完整日志文件
- 测试失败自动发送错误信息和日志
- 单次测试 55 分钟超时保护
- Telegram 请求自带基础重试
- 本地日志默认保留 14 天
- 支持重复运行安装器修改配置
- 支持一键卸载

---

## 工作原理

```text
                ┌──────────────────────┐
                │    systemd timer     │
                │ 按指定时区每天自动触发 │
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │ tcpquality-auto-run  │
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │      TcpQuality      │
                │   执行完整网络测试     │
                └──────────┬───────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
      在线结果地址（如有）          完整测试日志
              │                         │
              └────────────┬────────────┘
                           ▼
                ┌──────────────────────┐
                │     Telegram Bot     │
                └──────────────────────┘
```

多台 VPS 可以使用同一个 Telegram Bot：

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

# 系统要求

推荐：

- Debian
- systemd
- Bash
- root 权限，或可以使用 `sudo`
- 能够访问 TcpQuality
- 能够访问 Telegram Bot API

安装器会检查并按需安装：

```text
curl
ca-certificates
coreutils
tzdata
```

> [!NOTE]
> 脚本主要针对 Debian 编写。
> 其他使用 systemd 的 Linux 发行版可能可以运行，但目前不保证完整兼容。

---

# 快速安装

假设仓库地址最终为：

```text
https://github.com/shaolonger/tcpquality-auto
```

推荐在 VPS 上执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/shaolonger/tcpquality-auto/main/tcpquality-auto-install.sh)
```

也可以：

```bash
curl -fsSL \
  "https://raw.githubusercontent.com/shaolonger/tcpquality-auto/main/tcpquality-auto-install.sh" \
  -o /tmp/tcpquality-auto-install.sh

sudo bash /tmp/tcpquality-auto-install.sh
```

也可以 Clone：

```bash
git clone https://github.com/shaolonger/tcpquality-auto.git
cd tcpquality-auto

sudo bash tcpquality-auto-install.sh
```

> [!TIP]
> 不推荐直接使用 `curl | bash`。
>
> 这是一个需要读取用户输入的交互式安装器，先下载再执行更稳定，也方便运行前自行检查源码。

---

# 安装向导

首次执行：

```bash
sudo bash tcpquality-auto-install.sh
```

脚本会依次询问下面几个参数。

---

## 1. 服务器名称

示例：

```text
服务器名称 [hostname]: LAX-01
```

建议使用容易识别的节点名称，例如：

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

这个名称会显示在 Telegram 消息中。

例如：

```text
✅ TcpQuality 测试完成

服务器：LAX-01
```

因此即使几十台 VPS 使用同一个 Telegram Bot，也能快速判断结果来自哪台服务器。

---

## 2. 定时任务时区

默认：

```text
Asia/Shanghai
```

也可以填写其他标准 IANA 时区：

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

安装器会检查：

```text
/usr/share/zoneinfo/
```

确保输入的时区真实存在。

---

## 自定义时区不会修改 VPS 系统时区

例如 VPS 自身运行：

```text
America/Los_Angeles
```

但安装时设置：

```text
定时任务时区：Asia/Shanghai
每天执行时间：08:30
```

那么任务会固定在：

```text
北京时间每天 08:30
```

执行。

VPS 自身系统时区仍然保持：

```text
America/Los_Angeles
```

这对于部署在多个国家和地区的 VPS 很方便。

你可以让全球所有 VPS：

```text
统一按照北京时间运行
```

也可以：

```text
每台机器按照各自当地时区运行
```

---

## 3. 每天执行时间

格式：

```text
HH:MM
```

必须使用 24 小时制。

例如：

```text
08:30
```

或：

```text
23:05
```

安装器还会调用：

```bash
systemd-analyze calendar
```

检查最终生成的 systemd 日历表达式是否有效。

---

# Telegram 配置

## 4. Bot Token

首先在 Telegram 中找到：

```text
@BotFather
```

创建 Bot 后获得 Bot Token。

格式类似：

```text
1234567890:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

安装时填写：

```text
Bot Token:
```

输入 Token 时终端不会显示明文。

配置完成后 Token 会保存在：

```text
/etc/tcpquality-auto.conf
```

文件权限自动设为：

```text
600
```

即：

```text
root 可读写
其他用户不可读取
```

> [!WARNING]
> Bot Token 相当于机器人的密码。
>
> 不要把真实 Token 提交到 GitHub、Issue、README、公开日志或截图中。

---

## 5. Chat ID

如果发送给自己，Chat ID 通常类似：

```text
123456789
```

如果发送到群组，通常类似：

```text
-1001234567890
```

安装时：

```text
Chat ID:
```

填写目标 Chat ID。

安装器会立即发送一条测试消息。

例如：

```text
✅ TcpQuality 自动任务 Telegram 配置测试成功

服务器：LAX-01
计划：每天 08:30
时区：Asia/Shanghai
```

只有 Telegram 测试成功，安装才会继续。

---

## 6. Telegram Topic Thread ID

如果目标 Telegram 群组启用了：

```text
Forum / Topics
```

可以填写对应 Topic 的：

```text
message_thread_id
```

安装时：

```text
Topic Thread ID:
```

不使用 Topic 时：

```text
直接回车
```

即可。

---

# 安装完成后

脚本会自动创建：

```text
/etc/tcpquality-auto.conf
/usr/local/sbin/tcpquality-auto-run.sh

/etc/systemd/system/tcpquality-auto.service
/etc/systemd/system/tcpquality-auto.timer

/var/log/tcpquality-auto/
```

随后自动执行：

```bash
systemctl daemon-reload
systemctl enable --now tcpquality-auto.timer
```

所以首次安装完成以后不需要再配置 cron。

安装最后还会询问：

```text
是否现在立即执行一次完整 TcpQuality 测试？[y/N]:
```

输入：

```text
y
```

即可马上执行一次完整测试。

---

# 常用管理命令

当前版本使用 systemd 直接管理任务。

## 查看定时任务

```bash
systemctl status tcpquality-auto.timer --no-pager
```

---

## 查看下一次执行时间

```bash
systemctl list-timers tcpquality-auto.timer --all
```

---

## 立即手动测试一次

```bash
sudo systemctl start tcpquality-auto.service
```

该命令会等待本次测试执行完成。

---

## 查看测试状态

```bash
systemctl status tcpquality-auto.service --no-pager
```

---

## 查看最近运行日志

```bash
journalctl -u tcpquality-auto.service -n 100 --no-pager
```

---

## 实时查看日志

```bash
journalctl -u tcpquality-auto.service -f
```

---

# 停止定时任务

如果暂时不想每天自动测速：

```bash
sudo systemctl disable --now tcpquality-auto.timer
```

这会：

```text
停止 Timer
+
取消开机自动启用 Timer
```

但不会删除：

```text
配置
执行脚本
日志
systemd service
```

---

## 同时停止正在运行的测试

如果执行停止命令时 TcpQuality 恰好正在测试：

```bash
sudo systemctl disable --now tcpquality-auto.timer
sudo systemctl stop tcpquality-auto.service
```

第一条命令负责停止未来任务。

第二条负责停止当前正在执行的 TcpQuality。

---

# 恢复定时任务

执行：

```bash
sudo systemctl enable --now tcpquality-auto.timer
```

即可重新启用。

---

# 修改配置

重新运行安装器即可：

```bash
sudo bash tcpquality-auto-install.sh
```

如果已经安装过，脚本会读取：

```text
/etc/tcpquality-auto.conf
```

并显示原来的值：

```text
服务器名称 [LAX-01]:
定时任务时区 [Asia/Shanghai]:
每天执行时间 [08:30]:
Bot Token [直接回车保留原 Token]:
Chat ID [123456789]:
```

对于不需要修改的参数：

```text
直接回车
```

即可保留旧值。

如果之前配置过 Topic Thread ID，也可以继续保留或输入：

```text
-
```

清空 Thread ID。

> [!IMPORTANT]
> 当前版本重新运行安装器后会再次执行：
>
> ```bash
> systemctl enable --now tcpquality-auto.timer
> ```
>
> 因此如果你之前手动暂停了 Timer，重新运行安装器修改配置后，Timer 会重新启用。

---

# 卸载

执行：

```bash
sudo bash tcpquality-auto-install.sh --uninstall
```

脚本会询问：

```text
确认卸载？[y/N]:
```

确认后自动：

```text
停止并禁用 Timer
停止正在运行的 Service
删除配置文件
删除 Runner
删除 systemd Service
删除 systemd Timer
重新加载 systemd
```

随后询问：

```text
是否同时删除历史日志？
```

默认保留：

```text
/var/log/tcpquality-auto/
```

中的历史数据。

---

# TcpQuality 执行模式

实际 Runner 当前使用：

```bash
bash <(
  curl -fsSL \
    --retry 3 \
    --connect-timeout 15 \
    --max-time 120 \
    https://tcpquality.ibsgss.uk/run
) --allow-speedtest -- --all
```

其中：

```text
--allow-speedtest
```

用于允许 TcpQuality rootfs 包装器执行测速。

而：

```text
--all
```

用于启用 TcpQuality 当前定义的完整测试组合。

因此本项目不需要使用：

```text
yes
expect
printf 'y'
```

等方式模拟交互输入。

> [!NOTE]
> TcpQuality 上游可能继续调整参数和测试项目。
> 本项目运行的是执行时从上游获取到的版本。

---

# 测试超时

为了避免某个测试异常卡死：

```text
TcpQuality 最大运行时间：55 分钟
```

Runner 使用：

```bash
timeout --signal=TERM --kill-after=30s 55m
```

systemd Service 本身还设置：

```text
TimeoutStartSec=1h
```

形成第二层保护。

---

# Telegram 推送内容

测试成功后，Telegram 会收到类似：

```text
✅ TcpQuality 测试完成

服务器：LAX-01
开始：2026-08-08 08:30:01 CST
完成：2026-08-08 08:37:35 CST

在线结果：
https://tcpquality.ibsgss.uk/...
```

如果脚本没有成功识别在线结果 URL，也不会影响完整日志发送。

随后会发送：

```text
✅ LAX-01 · TcpQuality 完整测试日志
```

并附带 `.log` 文件。

---

## 测试失败

如果测试失败：

```text
❌ TcpQuality 测试失败

服务器：LAX-01
开始：...
完成：...
原因：测试进程退出码 ...
```

或者：

```text
原因：测试超时（55 分钟）
```

同时会发送对应错误日志。

---

# 日志

本地日志位于：

```text
/var/log/tcpquality-auto/
```

其中包括：

```text
YYYYMMDD-HHMMSS.raw.log
YYYYMMDD-HHMMSS.log
```

`raw.log`：

```text
保存原始终端输出
```

普通 `.log`：

```text
移除常见 ANSI 控制字符后，更适合查看和发送到 Telegram
```

查看：

```bash
sudo ls -lh /var/log/tcpquality-auto/
```

---

## 日志保留时间

脚本每次运行结束后会删除：

```text
14 天以前
```

的日志。

对应逻辑：

```bash
find /var/log/tcpquality-auto \
  -type f \
  -mtime +14 \
  -delete
```

---

# systemd Timer 行为

Timer 大致如下：

```ini
[Timer]
OnCalendar=*-*-* 08:30:00 Asia/Shanghai
Persistent=true
AccuracySec=1s
Unit=tcpquality-auto.service
```

其中：

```text
OnCalendar
```

控制每天的执行时间和时区。

---

## Persistent=true 是什么？

当前版本设置：

```ini
Persistent=true
```

这意味着：

如果服务器在计划执行时间处于关机状态，随后恢复运行，systemd 可能补执行一次错过的任务。

例如：

```text
计划：08:00

VPS：
07:00 关机
10:00 开机
```

Timer 检测到：

```text
08:00 的任务被错过
```

可能会在恢复后补执行一次。

如果你不希望这种行为，可以手动将：

```text
/etc/systemd/system/tcpquality-auto.timer
```

中的：

```ini
Persistent=true
```

改成：

```ini
Persistent=false
```

然后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart tcpquality-auto.timer
```

---

# 多台 VPS 部署

多台 VPS 可以使用同一个：

```text
Telegram Bot
Chat ID
```

建议为每台机器使用不同的：

```text
SERVER_NAME
```

例如：

| 地区 | SERVER_NAME |
|---|---|
| 香港 | `HKG-01` |
| 东京 | `TYO-01` |
| 新加坡 | `SIN-01` |
| 洛杉矶 | `LAX-01` |
| 纽约 | `NYC-01` |
| 伦敦 | `LON-01` |
| 法兰克福 | `FRA-01` |
| 阿姆斯特丹 | `AMS-01` |

---

## 是否需要错开时间？

少量 VPS 通常没有必要特别处理。

如果有几十台服务器，建议适当错开，例如：

```text
HKG-01   08:00
TYO-01   08:02
SIN-01   08:04
LAX-01   08:06
NYC-01   08:08
LON-01   08:10
FRA-01   08:12
```

好处包括：

- 避免大量测试同时占用测试节点
- 减少同一个 Telegram Chat 短时间收到大量消息
- 更容易按顺序检查结果

TcpQuality 的实际测试耗时本身也会存在差异，因此开始时间相同并不意味着结束时间一定相同。

---

# 多国家 VPS 共用一个 Telegram Bot

对于这种用途：

```text
美国 VPS
日本 VPS
香港 VPS
德国 VPS
荷兰 VPS
加拿大 VPS
```

共同调用同一个 Bot API 是正常的技术架构。

VPS 调用的是：

```text
Telegram Bot API
```

而不是让个人 Telegram 账号从不同国家反复登录。

真正需要注意的主要是：

```text
发送频率
Bot Token 安全
```

而不是 VPS 所在国家本身。

如果 VPS 数量很多，建议错开测试时间，减少短时间集中推送。

---

# Telegram 请求失败

当前版本发送 Telegram 时使用基础 Curl 重试：

```bash
--retry 3
```

并设置：

```text
连接超时：10 秒
普通消息最大请求时间：30 秒
日志文件最大请求时间：120 秒
```

当前版本尚未实现针对 Telegram Bot API JSON 中：

```text
parameters.retry_after
```

的专用解析与重试逻辑。

因此如果部署数量非常大，仍建议主动错峰。

---

# 文件说明

| 路径 | 用途 |
|---|---|
| `/etc/tcpquality-auto.conf` | 用户配置、Telegram 参数 |
| `/usr/local/sbin/tcpquality-auto-run.sh` | 实际执行 TcpQuality |
| `/etc/systemd/system/tcpquality-auto.service` | systemd Service |
| `/etc/systemd/system/tcpquality-auto.timer` | systemd Timer |
| `/var/log/tcpquality-auto/` | 测试日志 |

---

# 配置文件

示意：

```bash
SERVER_NAME=LAX-01
SCHEDULE_TZ=Asia/Shanghai
RUN_TIME=08:30
TG_BOT_TOKEN=1234567890:AAxxxxxxxx
TG_CHAT_ID=123456789
TG_THREAD_ID=
```

实际文件由安装器自动生成。

为了安全处理包含特殊字符的变量，脚本使用：

```bash
printf '%q'
```

生成可以被 Bash 再次安全 `source` 的内容。

> [!WARNING]
> 不要把 `/etc/tcpquality-auto.conf` 上传到 GitHub。

---

# 常见问题

## Q：为什么不用 cron？

因为 systemd timer 更适合这个场景，可以直接：

```text
管理独立时区
查看下一次运行时间
管理正在运行的测试
查看统一日志
设置超时
控制开机启用
```

---

## Q：为什么不用 `yes | bash ...` 自动回答多个 y？

因为 TcpQuality 已经提供非交互参数。

当前脚本直接使用：

```text
--allow-speedtest -- --all
```

比模拟键盘输入稳定。

---

## Q：怎么立即测试是否安装成功？

执行：

```bash
sudo systemctl start tcpquality-auto.service
```

然后：

```bash
journalctl -u tcpquality-auto.service -n 100 --no-pager
```

并检查 Telegram。

---

## Q：怎么判断 Timer 是否正常？

执行：

```bash
systemctl status tcpquality-auto.timer --no-pager
```

以及：

```bash
systemctl list-timers tcpquality-auto.timer --all
```

---

## Q：暂停之后 VPS 重启会不会重新开启？

如果你使用：

```bash
sudo systemctl disable --now tcpquality-auto.timer
```

则不会。

因为 Timer 已经被：

```text
disable
```

需要手动：

```bash
sudo systemctl enable --now tcpquality-auto.timer
```

才能重新恢复。

---

## Q：为什么重新运行安装器后 Timer 又启动了？

当前安装器完成配置后会自动执行：

```bash
systemctl enable --now tcpquality-auto.timer
```

因此重新配置也会重新启用定时任务。

---

## Q：Telegram 测试发送失败怎么办？

先测试：

```bash
curl -I https://api.telegram.org
```

然后确认：

```text
Bot Token 是否正确
Chat ID 是否正确
Thread ID 是否正确
Bot 是否已经加入目标群组
Bot 是否有发送消息权限
VPS 是否能够访问 Telegram
```

---

## Q：为什么没有收到在线结果地址？

Runner 会尝试从 TcpQuality 输出中提取：

```text
https://tcpquality.ibsgss.uk/...
```

如果上游输出格式发生变化，或者本次没有返回可识别 URL，提取可能失败。

这种情况下：

```text
完整日志仍然会正常发送
```

因此并不代表测试失败。

---

## Q：为什么日志里有 `.raw.log` 和 `.log` 两份？

`raw.log`：

```text
原始输出
```

`.log`：

```text
清理 ANSI 控制字符后的可读版本
```

Telegram 发送的是清理后的 `.log`。

---

## Q：执行测试会产生流量吗？

会。

尤其启用了：

```text
--allow-speedtest
```

后，TcpQuality 可能执行测速项目。

如果 VPS 有严格的月流量配额，请自行评估每天运行一次产生的流量。

---

# 更新项目

下载最新安装脚本：

```bash
curl -fsSL \
  "https://raw.githubusercontent.com/shaolonger/tcpquality-auto/main/tcpquality-auto-install.sh" \
  -o /tmp/tcpquality-auto-install.sh
```

然后：

```bash
sudo bash /tmp/tcpquality-auto-install.sh
```

安装器会读取旧配置。

不需要修改的参数：

```text
直接回车
```

即可。

---

# 安全说明

## 1. Bot Token

Telegram Bot Token 应视为敏感凭据。

不要：

- 提交到 GitHub
- 写入公开 README
- 放入 Issue
- 放入公开日志
- 在截图中展示

如果怀疑 Token 泄漏：

```text
立即通过 BotFather 撤销 / 重新生成
```

---

## 2. 多台 VPS 共用同一个 Token

技术上完全可以。

但需要理解：

```text
部署的 VPS 越多
=
保存 Bot Token 的位置越多
=
攻击面越大
```

因此建议：

- 只部署到可信 VPS
- 使用 SSH Key
- 减少不必要端口
- 及时安装安全更新
- 不执行来源不明的 root 脚本

---

## 3. 远程脚本执行风险

本项目每天都会访问：

```text
https://tcpquality.ibsgss.uk/run
```

并执行上游返回的脚本。

这带来一个明显特征：

```text
上游更新
↓
下一次定时任务自动运行新版代码
```

优点是：

```text
无需手动维护 TcpQuality
```

但从供应链安全角度，也意味着你信任 TcpQuality 上游和其分发入口。

高安全等级的生产环境可以考虑自行改造为：

- 固定 Git Commit
- 固定发布版本
- 下载后校验 SHA256
- 审查代码后再升级
- 将网络测试放在独立 VPS 中运行

---

# 故障排查

## 1. Timer 没有执行

检查：

```bash
systemctl status tcpquality-auto.timer --no-pager
```

然后：

```bash
systemctl list-timers tcpquality-auto.timer --all
```

再检查：

```bash
journalctl -u tcpquality-auto.timer -n 100 --no-pager
```

---

## 2. Service 执行失败

```bash
systemctl status tcpquality-auto.service --no-pager
```

查看详细日志：

```bash
journalctl -u tcpquality-auto.service -n 200 --no-pager
```

---

## 3. TcpQuality 下载失败

测试：

```bash
curl -v https://tcpquality.ibsgss.uk/run
```

---

## 4. Telegram 无法访问

测试：

```bash
curl -I https://api.telegram.org
```

---

## 5. 检查当前配置

```bash
sudo cat /etc/tcpquality-auto.conf
```

> [!WARNING]
> 该命令会显示 Bot Token。
>
> 请勿在公开 Issue、截图或聊天中直接粘贴完整输出。

---

# 项目结构

建议仓库保持简单：

```text
tcpquality-auto/
├── README.md
├── LICENSE
└── tcpquality-auto-install.sh
```

如果以后功能继续增加，可以扩展为：

```text
tcpquality-auto/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── tcpquality-auto-install.sh
└── docs/
```

---

# Roadmap

后续可以考虑加入：

- [ ] `--start`
- [ ] `--stop`
- [ ] `--status`
- [ ] `--run`
- [ ] `--config`
- [ ] Telegram `429 retry_after` 精确处理
- [ ] 多种通知方式
- [ ] Discord / Webhook
- [ ] 自定义日志保留天数
- [ ] 随机错峰执行
- [ ] 固定 TcpQuality 上游版本
- [ ] SHA256 / Commit 校验
- [ ] 多 VPS 集中汇总日报

---

# 致谢

感谢：

[ibsgss/TcpQuality](https://github.com/ibsgss/TcpQuality)

提供网络质量测试能力。

`tcpquality-auto` 的目标不是替代 TcpQuality，而是解决：

```text
如何让 TcpQuality
在多台 VPS 上
每天自动运行
并自动把结果发给 Telegram
```

这个运维场景。

---

# License

建议为本项目选择一个明确的开源许可证。

如果希望简单、宽松并允许其他人修改和二次发布，可以考虑：

```text
MIT License
```

然后在仓库根目录增加：

```text
LICENSE
```

> [!IMPORTANT]
> `tcpquality-auto` 自身的许可证和 TcpQuality 上游项目的许可证是两个不同问题。
> 公开发布前请确认 TcpQuality 当前许可证及相关使用要求。

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

测试结果只代表测试发生时的网络状态。

使用者应自行评估：

- 测速产生的流量
- CPU / 网络资源消耗
- 第三方服务依赖
- 远程脚本执行风险
- Telegram Bot Token 安全

使用本项目即代表你理解并自行承担相关风险。
