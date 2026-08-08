#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# TcpQuality Auto
# Debian VPS 定时 TcpQuality + Telegram 推送 + systemd 管理器
# ============================================================

APP_NAME="tcpquality-auto"
MANAGER_PATH="/usr/local/sbin/${APP_NAME}"
CONF_FILE="/etc/${APP_NAME}.conf"
RUNNER="/usr/local/sbin/${APP_NAME}-run.sh"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
TIMER_FILE="/etc/systemd/system/${APP_NAME}.timer"
SERVICE_UNIT="${APP_NAME}.service"
TIMER_UNIT="${APP_NAME}.timer"
LOG_DIR="/var/log/${APP_NAME}"

SCRIPT_SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[0;33m'
  C_RED='\033[0;31m'
  C_CYAN='\033[0;36m'
  C_BOLD='\033[1m'
else
  C_RESET=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_CYAN=''
  C_BOLD=''
fi

info() { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[FAIL]${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

line() {
  printf '%s\n' "============================================================"
}

pause_menu() {
  echo
  read -r -p "按 Enter 返回菜单..." _ || true
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E bash "$SCRIPT_SELF" "$@"
    fi
    die "此操作需要 root 权限。请使用 root 运行，或安装 sudo。"
  fi
}

is_installed() {
  [[ -f "${CONF_FILE}" && -f "${RUNNER}" && -f "${SERVICE_FILE}" && -f "${TIMER_FILE}" ]]
}

require_installed() {
  if ! is_installed; then
    die "TcpQuality Auto 尚未安装。请先执行：sudo ${APP_NAME} install，或在菜单中选择“安装 / 更新”。"
  fi
}

check_os() {
  [[ -r /etc/os-release ]] || die "无法识别操作系统：缺少 /etc/os-release"
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "debian" ]]; then
    warn "当前系统为 ${PRETTY_NAME:-未知}。本脚本主要面向 Debian，将继续尝试。"
  fi
}

ensure_dependencies() {
  info "检查依赖..."
  export DEBIAN_FRONTEND=noninteractive

  local need_install=0
  local cmd
  for cmd in curl timeout systemctl systemd-analyze; do
    command -v "${cmd}" >/dev/null 2>&1 || need_install=1
  done
  [[ -d /usr/share/zoneinfo ]] || need_install=1

  if [[ "${need_install}" -eq 1 ]]; then
    info "安装必要依赖：curl、ca-certificates、coreutils、tzdata..."
    apt-get update -y
    apt-get install -y curl ca-certificates coreutils tzdata
  fi

  command -v curl >/dev/null 2>&1 || die "curl 不可用。"
  command -v timeout >/dev/null 2>&1 || die "timeout 不可用。"
  command -v systemctl >/dev/null 2>&1 || die "systemd / systemctl 不可用。"
  command -v systemd-analyze >/dev/null 2>&1 || die "systemd-analyze 不可用。"
}

load_config() {
  SERVER_NAME=""
  SCHEDULE_TZ=""
  RUN_TIME=""
  TG_BOT_TOKEN=""
  TG_CHAT_ID=""
  TG_THREAD_ID=""

  if [[ -r "${CONF_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONF_FILE}"
  fi
}

save_config() {
  {
    printf 'SERVER_NAME=%q\n' "${SERVER_NAME}"
    printf 'SCHEDULE_TZ=%q\n' "${SCHEDULE_TZ}"
    printf 'RUN_TIME=%q\n' "${RUN_TIME}"
    printf 'TG_BOT_TOKEN=%q\n' "${TG_BOT_TOKEN}"
    printf 'TG_CHAT_ID=%q\n' "${TG_CHAT_ID}"
    printf 'TG_THREAD_ID=%q\n' "${TG_THREAD_ID}"
  } > "${CONF_FILE}"

  chmod 600 "${CONF_FILE}"
}

validate_timezone() {
  local tz="$1"
  if [[ "${tz}" == *".."* || "${tz}" == /* ]]; then
    return 1
  fi
  [[ -e "/usr/share/zoneinfo/${tz}" ]]
}

validate_time() {
  [[ "$1" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]
}

telegram_test() {
  local api="https://api.telegram.org/bot${TG_BOT_TOKEN}"
  local args=(
    --silent
    --show-error
    --fail
    --retry 3
    --retry-delay 2
    --connect-timeout 10
    --max-time 30
    -X POST
    "${api}/sendMessage"
    --data-urlencode "chat_id=${TG_CHAT_ID}"
    --data-urlencode "text=✅ TcpQuality Auto Telegram 配置测试成功

服务器：${SERVER_NAME}
计划：每天 ${RUN_TIME}
时区：${SCHEDULE_TZ}"
    --data-urlencode "disable_web_page_preview=true"
  )

  if [[ -n "${TG_THREAD_ID:-}" ]]; then
    args+=(--data-urlencode "message_thread_id=${TG_THREAD_ID}")
  fi

  curl "${args[@]}" >/dev/null
}

prompt_config() {
  load_config

  local old_server="${SERVER_NAME:-}"
  local old_tz="${SCHEDULE_TZ:-}"
  local old_time="${RUN_TIME:-}"
  local old_token="${TG_BOT_TOKEN:-}"
  local old_chat="${TG_CHAT_ID:-}"
  local old_thread="${TG_THREAD_ID:-}"

  if [[ -n "${old_server}${old_tz}${old_time}${old_token}${old_chat}${old_thread}" ]]; then
    echo
    info "检测到已有配置。直接回车可保留原值。"
  fi

  local default_server="${old_server:-$(hostname)}"
  local input=""

  read -r -p "服务器名称 [${default_server}]: " input
  SERVER_NAME="${input:-$default_server}"

  local default_tz="${old_tz:-Asia/Shanghai}"
  while true; do
    read -r -p "定时任务时区 [${default_tz}]（如 Asia/Shanghai、America/Los_Angeles）: " input
    SCHEDULE_TZ="${input:-$default_tz}"
    if validate_timezone "${SCHEDULE_TZ}"; then
      break
    fi
    warn "时区无效：${SCHEDULE_TZ}"
    echo "可查看可用时区：timedatectl list-timezones | less"
  done

  local default_time="${old_time:-20:30}"
  while true; do
    read -r -p "每天执行时间 [${default_time}]（24 小时制 HH:MM）: " input
    RUN_TIME="${input:-$default_time}"
    if validate_time "${RUN_TIME}"; then
      break
    fi
    warn "时间格式错误，例如：20:30、23:05。"
  done

  echo
  echo "Telegram 参数："

  if [[ -n "${old_token}" ]]; then
    read -r -s -p "Bot Token [直接回车保留原 Token]: " input
    echo
    TG_BOT_TOKEN="${input:-$old_token}"
  else
    while true; do
      read -r -s -p "Bot Token: " input
      echo
      if [[ -n "${input}" ]]; then
        TG_BOT_TOKEN="${input}"
        break
      fi
      warn "Bot Token 不能为空。"
    done
  fi

  while true; do
    if [[ -n "${old_chat}" ]]; then
      read -r -p "Chat ID [${old_chat}]: " input
      TG_CHAT_ID="${input:-$old_chat}"
    else
      read -r -p "Chat ID（私聊如 123456789；群组通常为 -100...）: " input
      TG_CHAT_ID="${input}"
    fi

    if [[ -n "${TG_CHAT_ID}" ]]; then
      break
    fi
    warn "Chat ID 不能为空。"
  done

  if [[ -n "${old_thread}" ]]; then
    read -r -p "Topic Thread ID [${old_thread}]（输入 - 可清空）: " input
    if [[ "${input}" == "-" ]]; then
      TG_THREAD_ID=""
    else
      TG_THREAD_ID="${input:-$old_thread}"
    fi
  else
    read -r -p "Topic Thread ID（可选，不使用直接回车）: " input
    TG_THREAD_ID="${input}"
  fi

  echo
  info "验证 systemd 定时表达式..."
  local cal_expr="*-*-* ${RUN_TIME}:00 ${SCHEDULE_TZ}"
  systemd-analyze calendar "${cal_expr}" >/dev/null 2>&1 \
    || die "当前 systemd 无法解析：${cal_expr}"
  ok "定时表达式有效：${cal_expr}"

  echo
  info "验证 Telegram 并发送测试消息..."
  telegram_test \
    || die "Telegram 测试发送失败。请检查 Bot Token、Chat ID、Thread ID，以及 VPS 到 api.telegram.org 的连通性。"
  ok "Telegram 测试消息已发送。"
}

write_runner() {
  cat > "${RUNNER}" <<'RUNNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

CONF_FILE="/etc/tcpquality-auto.conf"
LOG_DIR="/var/log/tcpquality-auto"
TCPQUALITY_URL="https://tcpquality.ibsgss.uk/run"

[[ -r "${CONF_FILE}" ]] || {
  echo "缺少配置：${CONF_FILE}" >&2
  exit 1
}

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
    --silent
    --show-error
    --fail
    --retry 3
    --retry-delay 2
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
    --silent
    --show-error
    --fail
    --retry 3
    --retry-delay 2
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
  bash -c 'bash <(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 https://tcpquality.ibsgss.uk/run) --all' \
  >"${raw_log}" 2>&1
exit_code=$?
set -e

# 去除常见 ANSI 控制字符，并把 CR 转成换行，便于阅读和 Telegram 发送。
sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g' "${raw_log}" \
  | tr '\r' '\n' \
  > "${clean_log}" \
  || cp -f "${raw_log}" "${clean_log}"

end_time="$(now_local)"

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
  sleep 2
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
  *)       reason="测试进程退出码 ${exit_code}" ;;
esac

msg="❌ TcpQuality 测试失败

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}
原因：${reason}"

send_message "${msg}" || true
sleep 2
send_document "${clean_log}" "❌ ${SERVER_NAME} · TcpQuality 错误日志" || true

find "${LOG_DIR}" -type f -mtime +14 -delete 2>/dev/null || true
exit "${exit_code}"
RUNNER_EOF

  chmod 700 "${RUNNER}"
}

write_service() {
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=TcpQuality Auto Network Test
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
}

write_timer() {
  cat > "${TIMER_FILE}" <<EOF
[Unit]
Description=Run TcpQuality Auto Daily (${RUN_TIME} ${SCHEDULE_TZ})

[Timer]
OnCalendar=*-*-* ${RUN_TIME}:00 ${SCHEDULE_TZ}
Persistent=true
AccuracySec=1s
Unit=${SERVICE_UNIT}

[Install]
WantedBy=timers.target
EOF
}

install_manager_self() {
  # 把当前脚本安装成全局管理命令：
  # sudo tcpquality-auto
  if [[ -f "${SCRIPT_SELF}" ]]; then
    local current_real target_real
    current_real="$(readlink -f "${SCRIPT_SELF}" 2>/dev/null || true)"
    target_real="$(readlink -f "${MANAGER_PATH}" 2>/dev/null || true)"

    if [[ "${current_real}" != "${target_real}" ]]; then
      install -m 0755 "${SCRIPT_SELF}" "${MANAGER_PATH}"
    else
      chmod 755 "${MANAGER_PATH}"
    fi
  fi
}

install_or_configure() {
  need_root "$@"
  check_os
  ensure_dependencies

  local existed=0
  local was_enabled=0
  local was_active=0

  is_installed && existed=1
  systemctl is-enabled --quiet "${TIMER_UNIT}" 2>/dev/null && was_enabled=1 || true
  systemctl is-active --quiet "${TIMER_UNIT}" 2>/dev/null && was_active=1 || true

  echo
  line
  echo -e "${C_BOLD} TcpQuality Auto 安装 / 配置${C_RESET}"
  line

  prompt_config

  mkdir -p "${LOG_DIR}"
  chmod 700 "${LOG_DIR}"

  save_config
  write_runner
  write_service
  write_timer
  install_manager_self

  systemctl daemon-reload

  if [[ "${existed}" -eq 0 ]]; then
    systemctl enable --now "${TIMER_UNIT}" >/dev/null
    ok "首次安装完成，定时任务已启用。"
  else
    if [[ "${was_enabled}" -eq 1 ]]; then
      systemctl enable "${TIMER_UNIT}" >/dev/null 2>&1 || true
      systemctl restart "${TIMER_UNIT}"
      ok "配置已更新，定时任务保持启用。"
    elif [[ "${was_active}" -eq 1 ]]; then
      systemctl restart "${TIMER_UNIT}"
      ok "配置已更新，Timer 保持当前运行状态，但未设置开机启用。"
    else
      systemctl stop "${TIMER_UNIT}" >/dev/null 2>&1 || true
      ok "配置已更新；检测到任务此前处于停止状态，因此继续保持停止。"
    fi
  fi

  echo
  echo "服务器：${SERVER_NAME}"
  echo "计划：  每天 ${RUN_TIME}"
  echo "时区：  ${SCHEDULE_TZ}"
  echo
  show_next_run false

  echo
  echo "以后可直接运行："
  echo "  sudo ${APP_NAME}"
  echo
  echo "或使用命令："
  echo "  sudo ${APP_NAME} status"
  echo "  sudo ${APP_NAME} logs"
  echo "  sudo ${APP_NAME} config"
  echo "  sudo ${APP_NAME} run"
  echo "  sudo ${APP_NAME} start"
  echo "  sudo ${APP_NAME} stop"
  echo "  sudo ${APP_NAME} restart"
  echo "  sudo ${APP_NAME} uninstall"
  echo

  read -r -p "是否现在立即执行一次完整 TcpQuality 测试？[y/N]: " run_now
  if [[ "${run_now}" =~ ^[Yy]$ ]]; then
    run_test
  fi
}

start_app() {
  need_root "$@"
  require_installed
  systemctl enable --now "${TIMER_UNIT}"
  ok "定时任务已启动并设置为开机自动启用。"
  show_next_run false
}

stop_app() {
  need_root "$@"
  require_installed

  systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true

  if systemctl is-active --quiet "${SERVICE_UNIT}"; then
    info "检测到 TcpQuality 测试正在运行，正在停止..."
    systemctl stop "${SERVICE_UNIT}" || true
  fi

  ok "定时任务已停止并禁用。配置和历史日志均已保留。"
}

restart_app() {
  need_root "$@"
  require_installed

  if systemctl is-active --quiet "${SERVICE_UNIT}"; then
    info "检测到测试正在运行，先停止当前测试..."
    systemctl stop "${SERVICE_UNIT}" || true
  fi

  if systemctl is-enabled --quiet "${TIMER_UNIT}" 2>/dev/null; then
    systemctl restart "${TIMER_UNIT}"
    ok "定时任务已重启，并保持开机自动启用。"
  else
    systemctl restart "${TIMER_UNIT}"
    warn "定时任务已重启，但当前仍是“未启用开机自启”状态。"
    echo "如需恢复开机自动启用，请执行：sudo ${APP_NAME} start"
  fi

  show_next_run false
}

run_test() {
  need_root "$@"
  require_installed

  if systemctl is-active --quiet "${SERVICE_UNIT}"; then
    warn "TcpQuality 测试已经在运行，本次不会重复启动。"
    systemctl status "${SERVICE_UNIT}" --no-pager || true
    return 0
  fi

  info "开始执行 TcpQuality 完整测试..."
  echo "测试完成后会自动发送 Telegram 通知和完整日志。"
  echo

  if systemctl start "${SERVICE_UNIT}"; then
    ok "测试执行完成。"
  else
    warn "测试执行失败，请查看日志：sudo ${APP_NAME} logs"
    return 1
  fi
}

show_next_run() {
  local heading="${1:-true}"
  require_installed

  if [[ "${heading}" == "true" ]]; then
    echo
    line
    echo -e "${C_BOLD} 下一次执行时间${C_RESET}"
    line
  fi

  if systemctl is-active --quiet "${TIMER_UNIT}" 2>/dev/null; then
    systemctl list-timers "${TIMER_UNIT}" --all --no-pager || true
  else
    warn "Timer 当前未运行，因此没有活动的下一次执行计划。"
    echo "恢复任务：sudo ${APP_NAME} start"
  fi
}

show_status() {
  require_installed
  load_config

  local timer_enabled="否"
  local timer_active="否"
  local service_active="否"

  systemctl is-enabled --quiet "${TIMER_UNIT}" 2>/dev/null && timer_enabled="是" || true
  systemctl is-active --quiet "${TIMER_UNIT}" 2>/dev/null && timer_active="是" || true
  systemctl is-active --quiet "${SERVICE_UNIT}" 2>/dev/null && service_active="是" || true

  echo
  line
  echo -e "${C_BOLD} TcpQuality Auto 状态${C_RESET}"
  line
  printf '%-18s %s\n' "服务器：" "${SERVER_NAME:-未知}"
  printf '%-18s %s\n' "执行时间：" "${RUN_TIME:-未知}"
  printf '%-18s %s\n' "任务时区：" "${SCHEDULE_TZ:-未知}"
  printf '%-18s %s\n' "Chat ID：" "${TG_CHAT_ID:-未知}"
  printf '%-18s %s\n' "Thread ID：" "${TG_THREAD_ID:-未设置}"
  printf '%-18s %s\n' "Bot Token：" "已配置（不显示）"
  echo
  printf '%-18s %s\n' "开机自动启用：" "${timer_enabled}"
  printf '%-18s %s\n' "Timer 运行中：" "${timer_active}"
  printf '%-18s %s\n' "测试正在运行：" "${service_active}"

  echo
  echo "Service 最近状态："
  systemctl show "${SERVICE_UNIT}" \
    -p ActiveState \
    -p SubState \
    -p Result \
    -p ExecMainStatus \
    --no-pager 2>/dev/null || true

  echo
  show_next_run false
}

show_logs_cli() {
  require_installed
  echo
  line
  echo -e "${C_BOLD} TcpQuality Auto 最近运行日志${C_RESET}"
  line
  journalctl -u "${SERVICE_UNIT}" -n 150 --no-pager || true

  local latest=""
  latest="$(find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' ! -name '*.raw.log' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2- || true)"

  if [[ -n "${latest}" && -f "${latest}" ]]; then
    echo
    line
    echo "最新测试日志文件：${latest}"
    line
    tail -n 120 "${latest}" || true
  fi
}

logs_menu() {
  require_installed

  while true; do
    echo
    line
    echo -e "${C_BOLD} 日志管理${C_RESET}"
    line
    echo "1) 查看最近 systemd 运行日志"
    echo "2) 实时跟踪 systemd 日志"
    echo "3) 查看最新 TcpQuality 测试日志"
    echo "4) 列出本地测试日志文件"
    echo "5) 查看 Timer 日志"
    echo "0) 返回上级菜单"
    echo

    read -r -p "请选择 [0-5]: " choice

    case "${choice}" in
      1)
        journalctl -u "${SERVICE_UNIT}" -n 150 --no-pager || true
        pause_menu
        ;;
      2)
        echo "按 Ctrl+C 停止实时查看并返回。"
        journalctl -u "${SERVICE_UNIT}" -f || true
        pause_menu
        ;;
      3)
        local latest=""
        latest="$(find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' ! -name '*.raw.log' -printf '%T@ %p\n' 2>/dev/null \
          | sort -nr \
          | head -n 1 \
          | cut -d' ' -f2- || true)"
        if [[ -n "${latest}" && -f "${latest}" ]]; then
          echo
          echo "文件：${latest}"
          line
          cat "${latest}"
        else
          warn "暂未找到测试日志。"
        fi
        pause_menu
        ;;
      4)
        echo
        if [[ -d "${LOG_DIR}" ]]; then
          ls -lhAt "${LOG_DIR}" || true
        else
          warn "日志目录不存在：${LOG_DIR}"
        fi
        pause_menu
        ;;
      5)
        journalctl -u "${TIMER_UNIT}" -n 100 --no-pager || true
        pause_menu
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项。"
        ;;
    esac
  done
}

uninstall_app() {
  need_root "$@"

  echo
  line
  echo -e "${C_RED}${C_BOLD} 停止并卸载 TcpQuality Auto${C_RESET}"
  line

  if ! is_installed && [[ ! -e "${MANAGER_PATH}" ]]; then
    warn "未检测到已安装的 TcpQuality Auto。"
    return 0
  fi

  warn "该操作将停止定时任务，并删除配置、Runner 和 systemd 单元。"
  echo "历史测试日志默认保留。"
  echo
  read -r -p "确认停止并卸载？[y/N]: " ans

  if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    return 0
  fi

  systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true
  systemctl stop "${SERVICE_UNIT}" >/dev/null 2>&1 || true

  rm -f "${TIMER_FILE}" "${SERVICE_FILE}" "${RUNNER}" "${CONF_FILE}"
  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true

  read -r -p "是否同时删除历史日志 ${LOG_DIR}？[y/N]: " del_log
  if [[ "${del_log}" =~ ^[Yy]$ ]]; then
    rm -rf "${LOG_DIR}"
    ok "历史日志已删除。"
  else
    ok "历史日志已保留：${LOG_DIR}"
  fi

  # 最后删除全局管理命令；当前进程仍可正常结束。
  rm -f "${MANAGER_PATH}"

  ok "TcpQuality Auto 已停止并卸载。"
}

print_help() {
  cat <<EOF

TcpQuality Auto

用法：
  sudo ${APP_NAME}
  sudo ${APP_NAME} <command>

命令：
  install      安装 / 更新脚本并交互配置
  config       修改现有配置
  status       查看配置、Timer、Service 和下一次执行时间
  logs         查看最近 systemd 日志和最新测试日志
  run          立即执行一次 TcpQuality 测试
  start        启动并启用定时任务
  stop         停止并禁用定时任务（保留配置和日志）
  restart      重启定时任务
  next         查看下一次执行时间
  uninstall    停止并卸载
  help         显示帮助

同样支持：
  --install --config --status --logs --run --start --stop
  --restart --next --uninstall --help

安装后不带参数运行：
  sudo ${APP_NAME}

即可进入中文管理菜单。

EOF
}

menu_header() {
  clear 2>/dev/null || true
  line
  echo -e "${C_BOLD}      TcpQuality Auto 管理面板${C_RESET}"
  line

  if is_installed; then
    load_config
    local timer_state="停止"
    systemctl is-active --quiet "${TIMER_UNIT}" 2>/dev/null && timer_state="运行"
    echo "状态：已安装 | Timer：${timer_state} | 节点：${SERVER_NAME:-未知}"
  else
    echo "状态：未安装"
  fi
  line
  echo
}

main_menu() {
  need_root "$@"

  while true; do
    menu_header
    echo "1) 安装 / 更新"
    echo "2) 立即执行一次测试"
    echo "3) 查看状态"
    echo "4) 查看日志"
    echo "5) 修改配置"
    echo "6) 启动 / 恢复定时任务"
    echo "7) 停止定时任务"
    echo "8) 重启定时任务"
    echo "9) 查看下一次执行时间"
    echo "10) 停止并卸载"
    echo "0) 退出"
    echo

    read -r -p "请选择 [0-10]: " choice

    case "${choice}" in
      1)
        install_or_configure
        pause_menu
        ;;
      2)
        if is_installed; then
          run_test || true
        else
          warn "尚未安装。"
        fi
        pause_menu
        ;;
      3)
        if is_installed; then
          show_status
        else
          warn "尚未安装。"
        fi
        pause_menu
        ;;
      4)
        if is_installed; then
          logs_menu
        else
          warn "尚未安装。"
          pause_menu
        fi
        ;;
      5)
        if is_installed; then
          install_or_configure
        else
          warn "尚未安装，请先选择 1 安装。"
        fi
        pause_menu
        ;;
      6)
        if is_installed; then
          start_app
        else
          warn "尚未安装。"
        fi
        pause_menu
        ;;
      7)
        if is_installed; then
          stop_app
        else
          warn "尚未安装。"
        fi
        pause_menu
        ;;
      8)
        if is_installed; then
          restart_app
        else
          warn "尚未安装。"
        fi
        pause_menu
        ;;
      9)
        if is_installed; then
          show_next_run
        else
          warn "尚未安装。"
        fi
        pause_menu
        ;;
      10)
        uninstall_app
        echo
        echo "已退出。"
        exit 0
        ;;
      0)
        echo "已退出。"
        exit 0
        ;;
      *)
        warn "无效选项，请输入 0-10。"
        sleep 1
        ;;
    esac
  done
}

dispatch() {
  local cmd="${1:-menu}"

  case "${cmd}" in
    menu)
      main_menu
      ;;
    install|--install)
      need_root "$@"
      install_or_configure
      ;;
    config|--config)
      need_root "$@"
      require_installed
      install_or_configure
      ;;
    status|--status)
      require_installed
      show_status
      ;;
    logs|log|--logs|--log)
      require_installed
      show_logs_cli
      ;;
    run|--run)
      need_root "$@"
      run_test
      ;;
    start|--start)
      need_root "$@"
      start_app
      ;;
    stop|--stop)
      need_root "$@"
      stop_app
      ;;
    restart|--restart)
      need_root "$@"
      restart_app
      ;;
    next|--next)
      require_installed
      show_next_run
      ;;
    uninstall|remove|--uninstall|--remove)
      need_root "$@"
      uninstall_app
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      err "未知命令：${cmd}"
      print_help
      exit 2
      ;;
  esac
}

dispatch "$@"
