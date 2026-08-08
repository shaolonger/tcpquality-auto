#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="tcpquality-auto"
CONF_FILE="/etc/${APP_NAME}.conf"
RUNNER="/usr/local/sbin/${APP_NAME}-run.sh"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
TIMER_FILE="/etc/systemd/system/${APP_NAME}.timer"
LOG_DIR="/var/log/${APP_NAME}"

c_reset='\033[0m'
c_green='\033[0;32m'
c_yellow='\033[0;33m'
c_red='\033[0;31m'
c_cyan='\033[0;36m'

info() { echo -e "${c_cyan}[INFO]${c_reset} $*"; }
ok()   { echo -e "${c_green}[ OK ]${c_reset} $*"; }
warn() { echo -e "${c_yellow}[WARN]${c_reset} $*"; }
die()  { echo -e "${c_red}[FAIL]${c_reset} $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$0" "$@"
    fi
    die "请使用 root 运行，或安装 sudo 后重新执行。"
  fi
}

uninstall_app() {
  need_root "$@"
  echo
  warn "将卸载 TcpQuality 自动定时任务。历史日志默认保留：${LOG_DIR}"
  read -r -p "确认卸载？[y/N]: " ans
  if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
  fi

  systemctl disable --now "${APP_NAME}.timer" >/dev/null 2>&1 || true
  systemctl stop "${APP_NAME}.service" >/dev/null 2>&1 || true
  rm -f "${TIMER_FILE}" "${SERVICE_FILE}" "${RUNNER}" "${CONF_FILE}"
  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true

  read -r -p "是否同时删除历史日志 ${LOG_DIR}？[y/N]: " del_log
  if [[ "${del_log}" =~ ^[Yy]$ ]]; then
    rm -rf "${LOG_DIR}"
  fi

  ok "卸载完成。"
  exit 0
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall_app "$@"
fi

need_root "$@"

if [[ ! -r /etc/os-release ]]; then
  die "无法识别操作系统。"
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "debian" ]]; then
  warn "当前系统识别为 ${PRETTY_NAME:-未知}，本脚本主要面向 Debian；将继续尝试安装。"
fi

echo
echo "============================================================"
echo "      TcpQuality 每日自动测试 + Telegram 推送安装器"
echo "============================================================"
echo

info "检查依赖..."
export DEBIAN_FRONTEND=noninteractive
missing=()
for cmd in curl timeout systemctl systemd-analyze; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if ((${#missing[@]} > 0)) || [[ ! -d /usr/share/zoneinfo ]]; then
  info "安装必要依赖：curl、ca-certificates、coreutils、tzdata..."
  apt-get update -y
  apt-get install -y curl ca-certificates coreutils tzdata
fi

command -v curl >/dev/null 2>&1 || die "curl 安装失败。"
command -v systemctl >/dev/null 2>&1 || die "systemd 不可用。"
command -v systemd-analyze >/dev/null 2>&1 || die "systemd-analyze 不可用。"

# 读取旧配置作为重复安装时的默认值
OLD_SERVER_NAME=""
OLD_SCHEDULE_TZ=""
OLD_RUN_TIME=""
OLD_TG_TOKEN=""
OLD_TG_CHAT_ID=""
OLD_TG_THREAD_ID=""

if [[ -f "${CONF_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONF_FILE}" || true
  OLD_SERVER_NAME="${SERVER_NAME:-}"
  OLD_SCHEDULE_TZ="${SCHEDULE_TZ:-}"
  OLD_RUN_TIME="${RUN_TIME:-}"
  OLD_TG_TOKEN="${TG_BOT_TOKEN:-}"
  OLD_TG_CHAT_ID="${TG_CHAT_ID:-}"
  OLD_TG_THREAD_ID="${TG_THREAD_ID:-}"
  echo
  info "检测到已有配置。直接回车可保留原值。"
fi

default_server="${OLD_SERVER_NAME:-$(hostname)}"
read -r -p "服务器名称 [${default_server}]: " SERVER_NAME
SERVER_NAME="${SERVER_NAME:-$default_server}"

default_tz="${OLD_SCHEDULE_TZ:-Asia/Shanghai}"
while true; do
  read -r -p "定时任务时区 [${default_tz}]（如 Asia/Shanghai、America/Los_Angeles）: " SCHEDULE_TZ
  SCHEDULE_TZ="${SCHEDULE_TZ:-$default_tz}"

  if [[ "${SCHEDULE_TZ}" == *".."* || "${SCHEDULE_TZ}" == /* ]]; then
    warn "时区格式无效，请输入 IANA 时区名称。"
    continue
  fi

  if [[ -e "/usr/share/zoneinfo/${SCHEDULE_TZ}" ]]; then
    break
  fi

  warn "未找到时区：${SCHEDULE_TZ}"
  echo "可执行：timedatectl list-timezones | less"
done

default_time="${OLD_RUN_TIME:-08:00}"
while true; do
  read -r -p "每天执行时间 [${default_time}]（24小时制 HH:MM）: " RUN_TIME
  RUN_TIME="${RUN_TIME:-$default_time}"

  if [[ "${RUN_TIME}" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
    break
  fi
  warn "时间格式错误，例如：08:30、23:05。"
done

echo
echo "Telegram 参数："
if [[ -n "${OLD_TG_TOKEN}" ]]; then
  read -r -s -p "Bot Token [直接回车保留原 Token]: " TG_BOT_TOKEN
  echo
  TG_BOT_TOKEN="${TG_BOT_TOKEN:-$OLD_TG_TOKEN}"
else
  while true; do
    read -r -s -p "Bot Token: " TG_BOT_TOKEN
    echo
    [[ -n "${TG_BOT_TOKEN}" ]] && break
    warn "Bot Token 不能为空。"
  done
fi

default_chat="${OLD_TG_CHAT_ID:-}"
while true; do
  if [[ -n "${default_chat}" ]]; then
    read -r -p "Chat ID [${default_chat}]: " TG_CHAT_ID
    TG_CHAT_ID="${TG_CHAT_ID:-$default_chat}"
  else
    read -r -p "Chat ID（私聊如 123456789；群组通常为 -100...）: " TG_CHAT_ID
  fi
  [[ -n "${TG_CHAT_ID}" ]] && break
  warn "Chat ID 不能为空。"
done

default_thread="${OLD_TG_THREAD_ID:-}"
if [[ -n "${default_thread}" ]]; then
  read -r -p "Topic Thread ID [${default_thread}]（不用话题可输入 - 清空）: " TG_THREAD_ID
  if [[ "${TG_THREAD_ID}" == "-" ]]; then
    TG_THREAD_ID=""
  else
    TG_THREAD_ID="${TG_THREAD_ID:-$default_thread}"
  fi
else
  read -r -p "Topic Thread ID（可选，不使用 Telegram 话题直接回车）: " TG_THREAD_ID
fi

echo
info "验证 systemd 日历表达式..."
CAL_EXPR="*-*-* ${RUN_TIME}:00 ${SCHEDULE_TZ}"
if ! systemd-analyze calendar "${CAL_EXPR}" >/dev/null 2>&1; then
  die "当前 systemd 无法解析：${CAL_EXPR}"
fi
ok "定时表达式有效：${CAL_EXPR}"

echo
info "验证 Telegram 并发送测试消息..."
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}"

tg_common_args=(
  --silent --show-error --fail
  --retry 3
  --connect-timeout 10
  --max-time 30
  -X POST
  "${TG_API}/sendMessage"
  --data-urlencode "chat_id=${TG_CHAT_ID}"
  --data-urlencode "text=✅ TcpQuality 自动任务 Telegram 配置测试成功

服务器：${SERVER_NAME}
计划：每天 ${RUN_TIME}
时区：${SCHEDULE_TZ}"
  --data-urlencode "disable_web_page_preview=true"
)
if [[ -n "${TG_THREAD_ID}" ]]; then
  tg_common_args+=(--data-urlencode "message_thread_id=${TG_THREAD_ID}")
fi

if ! curl "${tg_common_args[@]}" >/dev/null; then
  die "Telegram 测试发送失败。请检查 Bot Token、Chat ID、Thread ID，以及 VPS 到 api.telegram.org 的连通性。"
fi
ok "Telegram 测试消息已发送。"

mkdir -p "${LOG_DIR}"
chmod 700 "${LOG_DIR}"

# 安全保存配置，使用 Bash 可直接 source 的转义格式
{
  printf 'SERVER_NAME=%q\n' "${SERVER_NAME}"
  printf 'SCHEDULE_TZ=%q\n' "${SCHEDULE_TZ}"
  printf 'RUN_TIME=%q\n' "${RUN_TIME}"
  printf 'TG_BOT_TOKEN=%q\n' "${TG_BOT_TOKEN}"
  printf 'TG_CHAT_ID=%q\n' "${TG_CHAT_ID}"
  printf 'TG_THREAD_ID=%q\n' "${TG_THREAD_ID}"
} > "${CONF_FILE}"
chmod 600 "${CONF_FILE}"

cat > "${RUNNER}" <<'RUNNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

CONF_FILE="/etc/tcpquality-auto.conf"
LOG_DIR="/var/log/tcpquality-auto"
TCPQUALITY_URL="https://tcpquality.ibsgss.uk/run"

[[ -r "${CONF_FILE}" ]] || { echo "缺少配置：${CONF_FILE}" >&2; exit 1; }
# shellcheck disable=SC1090
source "${CONF_FILE}"

mkdir -p "${LOG_DIR}"
chmod 700 "${LOG_DIR}"

now_local() {
  TZ="${SCHEDULE_TZ}" date '+%Y-%m-%d %H:%M:%S %Z'
}

stamp="$(TZ="${SCHEDULE_TZ}" date '+%Y%m%d-%H%M%S')"
raw_log="${LOG_DIR}/${stamp}.raw.log"
clean_log="${LOG_DIR}/${stamp}.log"
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}"

send_message() {
  local text="$1"
  local args=(
    --silent --show-error --fail
    --retry 3
    --connect-timeout 10
    --max-time 30
    -X POST
    "${TG_API}/sendMessage"
    --data-urlencode "chat_id=${TG_CHAT_ID}"
    --data-urlencode "text=${text}"
    --data-urlencode "disable_web_page_preview=true"
  )
  if [[ -n "${TG_THREAD_ID:-}" ]]; then
    args+=(--data-urlencode "message_thread_id=${TG_THREAD_ID}")
  fi
  curl "${args[@]}" >/dev/null
}

send_document() {
  local file="$1"
  local caption="$2"
  local args=(
    --silent --show-error --fail
    --retry 3
    --connect-timeout 10
    --max-time 120
    -X POST
    "${TG_API}/sendDocument"
    -F "chat_id=${TG_CHAT_ID}"
    -F "document=@${file}"
    -F "caption=${caption}"
  )
  if [[ -n "${TG_THREAD_ID:-}" ]]; then
    args+=(-F "message_thread_id=${TG_THREAD_ID}")
  fi
  curl "${args[@]}" >/dev/null
}

start_time="$(now_local)"

set +e
timeout --signal=TERM --kill-after=30s 55m \
  bash -c 'bash <(curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 https://tcpquality.ibsgss.uk/run) --all' \
  >"${raw_log}" 2>&1
exit_code=$?
set -e

# 去除常见 ANSI 控制字符，并把 CR 转换为普通换行，方便查看日志。
sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g' "${raw_log}" | tr '\r' '\n' > "${clean_log}" || cp -f "${raw_log}" "${clean_log}"

end_time="$(now_local)"

# 尝试从输出中找在线结果链接；找不到也没关系，完整日志始终会作为文件发送。
report_url="$(
  grep -Eo 'https?://tcpquality\.ibsgss\.uk/[^[:space:]<>"'\'']+' "${clean_log}" 2>/dev/null \
    | grep -Ev '/run($|[/?#])' \
    | tail -n 1 \
    || true
)"

if [[ "${exit_code}" -eq 0 ]]; then
  msg="✅ TcpQuality 测试完成

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}"
  if [[ -n "${report_url}" ]]; then
    msg="${msg}

在线结果：
${report_url}"
  fi

  push_failed=0
  send_message "${msg}" || push_failed=1
  send_document "${clean_log}" "✅ ${SERVER_NAME} · TcpQuality 完整测试日志" || push_failed=1

  find "${LOG_DIR}" -type f -mtime +14 -delete 2>/dev/null || true
  if [[ "${push_failed}" -ne 0 ]]; then
    echo "测试成功，但 Telegram 推送失败。" >&2
    exit 2
  fi
  exit 0
fi

case "${exit_code}" in
  124|137) reason="测试超时（55 分钟）" ;;
  *) reason="测试进程退出码 ${exit_code}" ;;
esac

msg="❌ TcpQuality 测试失败

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}
原因：${reason}"

send_message "${msg}" || true
send_document "${clean_log}" "❌ ${SERVER_NAME} · TcpQuality 错误日志" || true
find "${LOG_DIR}" -type f -mtime +14 -delete 2>/dev/null || true
exit "${exit_code}"
RUNNER_EOF

chmod 700 "${RUNNER}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=TcpQuality Daily Network Test
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${RUNNER}
TimeoutStartSec=1h
Nice=10

[Install]
WantedBy=multi-user.target
EOF

cat > "${TIMER_FILE}" <<EOF
[Unit]
Description=Run TcpQuality Daily (${RUN_TIME} ${SCHEDULE_TZ})

[Timer]
OnCalendar=*-*-* ${RUN_TIME}:00 ${SCHEDULE_TZ}
Persistent=true
AccuracySec=1s
Unit=${APP_NAME}.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "${APP_NAME}.timer" >/dev/null

echo
echo "============================================================"
ok "安装/更新完成"
echo "============================================================"
echo
echo "服务器：${SERVER_NAME}"
echo "计划：每天 ${RUN_TIME}"
echo "时区：${SCHEDULE_TZ}"
echo
echo "下一次执行："
systemctl list-timers "${APP_NAME}.timer" --no-pager --all || true

echo
echo "常用命令："
echo "  立即手动测试：sudo systemctl start ${APP_NAME}.service"
echo "  查看本次状态：systemctl status ${APP_NAME}.service --no-pager"
echo "  查看运行日志：journalctl -u ${APP_NAME}.service -n 100 --no-pager"
echo "  查看定时任务：systemctl list-timers ${APP_NAME}.timer --all"
echo "  修改配置：    重新运行本安装脚本"
echo "  卸载：        sudo bash $0 --uninstall"
echo

read -r -p "是否现在立即执行一次完整 TcpQuality 测试？[y/N]: " run_now
if [[ "${run_now}" =~ ^[Yy]$ ]]; then
  echo
  info "开始完整测试。完成后 Telegram 会收到结果和完整日志..."
  if systemctl start "${APP_NAME}.service"; then
    ok "测试完成，请检查 Telegram。"
  else
    warn "测试未成功，请执行以下命令查看原因："
    echo "journalctl -u ${APP_NAME}.service -n 100 --no-pager"
  fi
else
  ok "定时任务已启用，等待下一次计划执行。"
fi
