#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# TcpQuality Auto
# Pure Bash / Low-overhead / Debian+Alpine
# Version: 2026.09.27.8
# ============================================================

APP_NAME="tcpquality-auto"
APP_VERSION="2026.09.27.8"

MANAGER_PATH="/usr/local/sbin/${APP_NAME}"
CONF_FILE="/etc/${APP_NAME}.conf"
RUNNER="/usr/local/sbin/${APP_NAME}-run.sh"

SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
TIMER_FILE="/etc/systemd/system/${APP_NAME}.timer"
SERVICE_UNIT="${APP_NAME}.service"
TIMER_UNIT="${APP_NAME}.timer"

CRON_FILE="/etc/cron.d/${APP_NAME}"

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

line() { printf '%s\n' "============================================================"; }

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

os_id() {
  if [[ -r /etc/os-release ]]; then
    (
      # shellcheck disable=SC1091
      source /etc/os-release
      printf '%s' "${ID:-}"
    )
  fi
}

os_pretty() {
  if [[ -r /etc/os-release ]]; then
    (
      # shellcheck disable=SC1091
      source /etc/os-release
      printf '%s' "${PRETTY_NAME:-未知}"
    )
  else
    printf '%s' "未知"
  fi
}

host_backend() {
  local id
  id="$(os_id)"

  if [[ "${id}" == "alpine" ]]; then
    printf '%s' "cron"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    printf '%s' "systemd"
    return 0
  fi

  printf '%s' "unsupported"
}

check_os() {
  [[ -r /etc/os-release ]] || die "无法识别操作系统：缺少 /etc/os-release"

  case "$(host_backend)" in
    systemd)
      info "当前系统：$(os_pretty)；调度后端：systemd timer。"
      ;;
    cron)
      info "当前系统：$(os_pretty)；调度后端：Cronie + OpenRC。"
      ;;
    *)
      die "当前系统暂不受支持。仅支持 Debian/Ubuntu（systemd）与 Alpine（Cronie/OpenRC）。"
      ;;
  esac
}

ensure_dependencies() {
  info "检查依赖..."

  local backend need_install=0
  backend="$(host_backend)"

  command -v bash >/dev/null 2>&1 || need_install=1
  command -v curl >/dev/null 2>&1 || need_install=1
  command -v timeout >/dev/null 2>&1 || need_install=1
  command -v find >/dev/null 2>&1 || need_install=1
  command -v awk >/dev/null 2>&1 || need_install=1
  command -v flock >/dev/null 2>&1 || need_install=1
  command -v nice >/dev/null 2>&1 || need_install=1
  [[ -d /usr/share/zoneinfo ]] || need_install=1

  case "${backend}" in
    systemd)
      if [[ "${need_install}" -eq 1 ]]; then
        export DEBIAN_FRONTEND=noninteractive
        info "安装必要依赖：bash、curl、ca-certificates、coreutils、tzdata..."
        apt-get update -y
        apt-get install -y \
          bash \
          curl \
          ca-certificates \
          coreutils \
          findutils \
          tzdata \
          util-linux \
          procps
      fi
      ;;

    cron)
      if [[ "${need_install}" -eq 1 ]] || ! command -v crond >/dev/null 2>&1; then
        info "安装必要依赖：bash、curl、ca-certificates、coreutils、cronie..."
        apk add --no-cache \
          bash \
          curl \
          ca-certificates \
          coreutils \
          findutils \
          tzdata \
          util-linux \
          procps \
          cronie \
          cronie-openrc \
          openrc \
          tar \
          xz \
          zstd
      fi
      ;;

    *)
      die "无法为当前系统安装依赖。"
      ;;
  esac

  command -v bash >/dev/null 2>&1 || die "bash 不可用。"
  command -v curl >/dev/null 2>&1 || die "curl 不可用。"
  command -v timeout >/dev/null 2>&1 || die "timeout 不可用。"
  command -v find >/dev/null 2>&1 || die "find 不可用。"
  command -v awk >/dev/null 2>&1 || die "awk 不可用。"
  command -v flock >/dev/null 2>&1 || die "flock 不可用。"
  command -v nice >/dev/null 2>&1 || die "nice 不可用。"
  [[ -d /usr/share/zoneinfo ]] || die "tzdata / zoneinfo 不可用。"
}

is_installed() {
  [[ -f "${CONF_FILE}" && -f "${RUNNER}" && -f "${MANAGER_PATH}" ]]
}

require_installed() {
  if ! is_installed; then
    die "TcpQuality Auto 尚未安装。请先执行“安装 / 更新”。"
  fi
}

scheduler_enabled() {
  case "$(host_backend)" in
    systemd)
      systemctl is-enabled --quiet "${TIMER_UNIT}" 2>/dev/null
      ;;
    cron)
      [[ -f "${CRON_FILE}" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

scheduler_active() {
  case "$(host_backend)" in
    systemd)
      systemctl is-active --quiet "${TIMER_UNIT}" 2>/dev/null
      ;;
    cron)
      [[ -f "${CRON_FILE}" ]] && pgrep -x crond >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

runner_active() {
  pgrep -f "${RUNNER}" >/dev/null 2>&1
}

load_config() {
  SERVER_NAME=""
  SCHEDULE_TZ=""
  RUN_TIME=""
  TG_BOT_TOKEN=""
  TG_CHAT_ID=""
  TG_THREAD_ID=""
  SEND_FULL_LOG="N"
  RUN_PROFILE="AUTO"

  if [[ -r "${CONF_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONF_FILE}"
    SEND_FULL_LOG="${SEND_FULL_LOG:-N}"
    RUN_PROFILE="${RUN_PROFILE:-AUTO}"
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
    printf 'SEND_FULL_LOG=%q\n' "${SEND_FULL_LOG}"
    printf 'RUN_PROFILE=%q\n' "${RUN_PROFILE}"
  } > "${CONF_FILE}"

  chmod 600 "${CONF_FILE}"
}

validate_timezone() {
  local tz="$1"
  if [[ "${tz}" == *".."* || "${tz}" == /* || -z "${tz}" ]]; then
    return 1
  fi
  [[ -e "/usr/share/zoneinfo/${tz}" ]]
}

validate_time() {
  [[ "$1" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]
}

memory_total_kb() {
  awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0
}

swap_total_kb() {
  awk '/SwapTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0
}

warn_low_memory_interactive() {
  local mem_kb swap_kb mem_mb swap_mb
  mem_kb="$(memory_total_kb)"
  swap_kb="$(swap_total_kb)"
  mem_mb=$(( mem_kb / 1024 ))
  swap_mb=$(( swap_kb / 1024 ))

  if (( mem_kb > 0 && mem_kb < 262144 )); then
    warn "检测到当前 VPS 内存较低：约 ${mem_mb} MB；Swap：约 ${swap_mb} MB。"
    warn "TcpQuality --all 在低内存环境下可能超时、失败或触发 OOM。"
  fi
}

telegram_test() {
  local api="https://api.telegram.org/bot${TG_BOT_TOKEN}"
  local -a args=(
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
  local old_send_full_log="${SEND_FULL_LOG:-N}"
  local old_run_profile="${RUN_PROFILE:-AUTO}"

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
    [[ -n "${TG_CHAT_ID}" ]] && break
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
  local log_default_label="N"
  [[ "${old_send_full_log^^}" == "Y" ]] && log_default_label="Y"

  while true; do
    read -r -p "是否通过 Telegram 发送完整测试日志？[y/N]（当前：${log_default_label}）: " input
    if [[ -z "${input}" ]]; then
      SEND_FULL_LOG="${old_send_full_log:-N}"
      break
    fi

    case "${input}" in
      y|Y|yes|YES|Yes)
        SEND_FULL_LOG="Y"
        break
        ;;
      n|N|no|NO|No)
        SEND_FULL_LOG="N"
        break
        ;;
      *)
        warn "请输入 y 或 n；直接回车使用默认值。"
        ;;
    esac
  done

  echo
  local mem_kb_now swap_kb_now mem_mb_now swap_mb_now recommended_profile
  mem_kb_now="$(memory_total_kb)"
  swap_kb_now="$(swap_total_kb)"
  mem_mb_now=$((mem_kb_now / 1024))
  swap_mb_now=$((swap_kb_now / 1024))
  recommended_profile="FULL"

  if (( mem_kb_now > 0 && mem_kb_now < 196608 )); then
    recommended_profile="LOWMEM"
  elif (( mem_kb_now > 0 && mem_kb_now < 262144 && swap_kb_now < 131072 )); then
    recommended_profile="LOWMEM"
  fi

  echo "运行模式："
  echo "  1) AUTO   自动判断（推荐；当前环境会选择 ${recommended_profile}）"
  echo "  2) FULL   完整标准模式：TcpQuality --all"
  echo "  3) LOWMEM 超低内存模式：仍执行 --all，但强制 -p 1 -c 50"
  echo "当前内存：约 ${mem_mb_now} MB；Swap：约 ${swap_mb_now} MB"

  local profile_default="1"
  case "${old_run_profile^^}" in
    FULL) profile_default="2" ;;
    LOWMEM) profile_default="3" ;;
    *) profile_default="1" ;;
  esac

  while true; do
    read -r -p "请选择运行模式 [1-3，默认 ${profile_default}]: " input
    input="${input:-$profile_default}"
    case "${input}" in
      1) RUN_PROFILE="AUTO"; break ;;
      2) RUN_PROFILE="FULL"; break ;;
      3) RUN_PROFILE="LOWMEM"; break ;;
      *) warn "请输入 1、2 或 3。" ;;
    esac
  done

  echo
  ok "定时设置有效：每天 ${RUN_TIME}（${SCHEDULE_TZ}）"
  ok "运行模式：${RUN_PROFILE}"

  echo
  info "验证 Telegram 并发送测试消息..."
  telegram_test \
    || die "Telegram 测试发送失败。请检查 Bot Token、Chat ID、Thread ID，以及 VPS 到 api.telegram.org 的连通性。"
  ok "Telegram 测试消息已发送。"
}

write_runner() {
  mkdir -p "$(dirname "${RUNNER}")"

  cat > "${RUNNER}" <<'RUNNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

CONF_FILE="/etc/tcpquality-auto.conf"
LOG_DIR="/var/log/tcpquality-auto"

TCPQUALITY_URL="${TCPQUALITY_URL:-https://tcpquality.ibsgss.uk/run}"
TCPQUALITY_FALLBACK_URL="${TCPQUALITY_FALLBACK_URL:-https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh}"

REPORT_API="${TCPQUALITY_REPORT_API:-https://tcpquality.ibsgss.uk/generate}"
REPORT_RECOVERY_ATTEMPTS="${TCPQUALITY_REPORT_RECOVERY_ATTEMPTS:-4}"
REPORT_RECOVERY_CONNECT_TIMEOUT="${TCPQUALITY_REPORT_RECOVERY_CONNECT_TIMEOUT:-15}"
REPORT_RECOVERY_MAX_TIME="${TCPQUALITY_REPORT_RECOVERY_MAX_TIME:-90}"

KEEP_DAYS="${TCPQUALITY_KEEP_DAYS:-14}"
TEST_TIMEOUT="${TCPQUALITY_TEST_TIMEOUT:-55m}"

[[ -r "${CONF_FILE}" ]] || {
  echo "缺少配置：${CONF_FILE}" >&2
  exit 1
}

# shellcheck disable=SC1090
source "${CONF_FILE}"
SEND_FULL_LOG="${SEND_FULL_LOG:-N}"
RUN_PROFILE="${RUN_PROFILE:-AUTO}"

mkdir -p "${LOG_DIR}"
chmod 700 "${LOG_DIR}"

now_local() {
  TZ="${SCHEDULE_TZ}" date '+%Y-%m-%d %H:%M:%S %Z'
}

memory_total_kb() {
  awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0
}

swap_total_kb() {
  awk '/SwapTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0
}

resolve_run_profile() {
  local requested="${RUN_PROFILE^^}"
  local mem_kb swap_kb

  case "${requested}" in
    FULL|LOWMEM)
      printf '%s' "${requested}"
      return 0
      ;;
  esac

  mem_kb="$(memory_total_kb)"
  swap_kb="$(swap_total_kb)"

  if (( mem_kb > 0 && mem_kb < 196608 )); then
    printf '%s' "LOWMEM"
  elif (( mem_kb > 0 && mem_kb < 262144 && swap_kb < 131072 )); then
    printf '%s' "LOWMEM"
  else
    printf '%s' "FULL"
  fi
}

stamp="$(TZ="${SCHEDULE_TZ}" date '+%Y%m%d-%H%M%S')"
raw_log="${LOG_DIR}/${stamp}.raw.log"
clean_log="${LOG_DIR}/${stamp}.log"
artifact_dir="${LOG_DIR}/${stamp}.artifacts"

TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}"
entry_script="$(mktemp "${TMPDIR:-/tmp}/tcpquality-auto-entry.XXXXXX.sh")"

response_file=""
curl_err=""

cleanup() {
  rm -f "${entry_script}" 2>/dev/null || true
  [[ -n "${response_file}" ]] && rm -f "${response_file}" 2>/dev/null || true
  [[ -n "${curl_err}" ]] && rm -f "${curl_err}" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "${artifact_dir}"
chmod 700 "${artifact_dir}"

LOCK_FILE="/run/tcpquality-auto.lock"
mkdir -p "$(dirname "${LOCK_FILE}")"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "[tcpquality-auto] 已有测试任务正在运行，本次跳过。" >&2
  exit 75
fi

ACTIVE_PROFILE="$(resolve_run_profile)"
declare -a TEST_ARGS=(--all)
if [[ "${ACTIVE_PROFILE}" == "LOWMEM" ]]; then
  TEST_ARGS=(--all -p 1 -c 50)
fi

send_message() {
  local text="$1"
  local -a args=(
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
  local -a args=(
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

fetch_entry() {
  local url="$1"
  : > "${entry_script}"
  echo "[tcpquality-auto] 下载 TcpQuality 入口：${url}" >> "${raw_log}"

  if ! curl -fsSL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time 120 \
    "${url}" -o "${entry_script}" >> "${raw_log}" 2>&1; then
    echo "[tcpquality-auto] 入口下载失败：${url}" >> "${raw_log}"
    return 1
  fi

  if [[ ! -s "${entry_script}" ]]; then
    echo "[tcpquality-auto] 入口下载异常：返回内容为空：${url}" >> "${raw_log}"
    return 1
  fi

  if ! head -n 1 "${entry_script}" | grep -Eq '^#!.*(bash|sh)'; then
    echo "[tcpquality-auto] 入口下载异常：返回内容不是可识别的 Shell 脚本：${url}" >> "${raw_log}"
    return 1
  fi

  return 0
}

extract_report_url_from_json() {
  local file="$1"
  sed -nE 's/.*"url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${file}" 2>/dev/null \
    | sed 's#\\/#/#g' \
    | grep -E '^https?://tcpquality\.ibsgss\.uk/r/[A-Za-z0-9_-]+$' \
    | head -n 1 \
    || true
}

find_current_csv() {
  find "${artifact_dir}" -maxdepth 1 -type f -name 'zstatic_nping_*.csv' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2- \
    || true
}

extract_report_time() {
  grep -E '报告时间：' "${clean_log}" 2>/dev/null \
    | tail -n 1 \
    | sed -E 's/.*报告时间：[[:space:]]*//; s/[[:space:]]*$//' \
    || true
}

recover_report_upload() {
  local csv="$1"
  local recovered_url=""
  local report_time=""
  local family attempt sleep_s curl_rc http_code
  local -a report_headers=()

  [[ -s "${csv}" ]] || {
    echo "[tcpquality-auto] 报告恢复上传跳过：未找到本次测试 CSV。" >> "${raw_log}"
    return 1
  }

  report_time="$(extract_report_time)"
  if [[ -n "${report_time}" ]]; then
    report_headers+=(-H "X-Report-Time: ${report_time}")
  fi

  response_file="$(mktemp "${TMPDIR:-/tmp}/tcpquality-auto-report-response.XXXXXX")"
  curl_err="$(mktemp "${TMPDIR:-/tmp}/tcpquality-auto-report-curl.XXXXXX")"

  for family in ipv4 auto; do
    for ((attempt=1; attempt<=REPORT_RECOVERY_ATTEMPTS; attempt++)); do
      : > "${response_file}"
      : > "${curl_err}"
      http_code=""
      curl_rc=0

      local -a curl_args=(
        --silent
        --show-error
        --connect-timeout "${REPORT_RECOVERY_CONNECT_TIMEOUT}"
        --max-time "${REPORT_RECOVERY_MAX_TIME}"
        --retry 2
        --retry-delay 2
        --retry-max-time 180
        -o "${response_file}"
        -w '%{http_code}'
        -H 'Content-Type: text/csv; charset=utf-8'
        "${report_headers[@]}"
        --data-binary "@${csv}"
        "${REPORT_API}"
      )

      if [[ "${family}" == "ipv4" ]]; then
        curl_args=(-4 "${curl_args[@]}")
      fi

      echo "[tcpquality-auto] 恢复上传：协议栈=${family}，第 ${attempt}/${REPORT_RECOVERY_ATTEMPTS} 次。" >> "${raw_log}"
      http_code="$(curl "${curl_args[@]}" 2>"${curl_err}")" || curl_rc=$?

      recovered_url="$(extract_report_url_from_json "${response_file}")"
      if [[ "${curl_rc}" -eq 0 && "${http_code}" =~ ^2[0-9][0-9]$ && -n "${recovered_url}" ]]; then
        echo "${recovered_url}"
        return 0
      fi

      {
        echo "[tcpquality-auto] 恢复上传未成功：curl_rc=${curl_rc}，HTTP=${http_code:-none}"
        if [[ -s "${curl_err}" ]]; then
          echo "[tcpquality-auto] curl：$(tr '\n' ' ' < "${curl_err}" | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-400)"
        fi
        if [[ -s "${response_file}" ]]; then
          echo "[tcpquality-auto] 响应：$(tr '\n' ' ' < "${response_file}" | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-400)"
        fi
      } >> "${raw_log}"

      if (( attempt < REPORT_RECOVERY_ATTEMPTS )); then
        sleep_s=$((5 * (1 << (attempt - 1))))
        (( sleep_s > 40 )) && sleep_s=40
        sleep "${sleep_s}"
      fi
    done
  done

  return 1
}

log_has() {
  grep -Eqi -- "$1" "${clean_log}" 2>/dev/null
}

diagnose_failure() {
  if log_has '\[tcpquality-auto\] 入口下载(失败|异常)'; then
    echo "TcpQuality 入口脚本下载失败"
  elif log_has 'Could not resolve host|Temporary failure in name resolution|Name or service not known|无法解析.*域名'; then
    echo "网络异常：DNS / 域名解析失败"
  elif log_has 'curl: \(28\)|Connection timed out|Operation timed out|Timeout was reached|timed out'; then
    echo "网络异常：连接或下载超时"
  elif log_has 'curl: \(7\)|Failed to connect|Connection refused|No route to host|Network is unreachable'; then
    echo "网络异常：无法连接远端服务"
  elif log_has 'rootfs SHA256 校验失败|rootfs 大小校验失败'; then
    echo "TcpQuality rootfs 下载文件校验失败"
  elif log_has 'rootfs 下载失败|创建 Debian rootfs 需要|Docker 创建 Debian 容器失败|Docker 导出 Debian rootfs 失败|无法获取 Alpine minirootfs 元数据'; then
    echo "TcpQuality rootfs 获取或创建失败"
  elif log_has 'SVG 报告上传失败|已跳过 SVG 报告上传'; then
    echo "TcpQuality 在线报告上传失败"
  elif log_has '\[X\].*(依赖|失败|无法|不支持|缺少)'; then
    local detail=""
    detail="$(grep -Ei '\[X\].*(依赖|失败|无法|不支持|缺少)' "${clean_log}" 2>/dev/null | tail -n 1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' || true)"
    if [[ -n "${detail}" ]]; then
      echo "${detail}"
    else
      echo "TcpQuality 执行异常"
    fi
  else
    echo "TcpQuality 执行异常"
  fi
}

start_time="$(now_local)"
: > "${raw_log}"

mem_kb="$(memory_total_kb)"
swap_kb="$(swap_total_kb)"
echo "[tcpquality-auto] 运行档位：请求=${RUN_PROFILE^^}，实际=${ACTIVE_PROFILE}，参数=${TEST_ARGS[*]}" >> "${raw_log}"
if (( mem_kb > 0 && mem_kb < 262144 )); then
  echo "[tcpquality-auto] 警告：当前 VPS 内存约 $((mem_kb / 1024)) MB，Swap 约 $((swap_kb / 1024)) MB，完整 TcpQuality 测试可能 OOM 或超时。" >> "${raw_log}"
fi

entry_source="primary"
entry_ready=0

if fetch_entry "${TCPQUALITY_URL}"; then
  entry_ready=1
else
  echo "[tcpquality-auto] 主入口不可用，尝试官方 GitHub Raw 备用入口。" >> "${raw_log}"
  entry_source="fallback"
  if fetch_entry "${TCPQUALITY_FALLBACK_URL}"; then
    entry_ready=1
  fi
fi

set +e
if [[ "${entry_ready}" -eq 1 ]]; then
  echo "[tcpquality-auto] 入口脚本校验通过，开始执行 TcpQuality --all。" >> "${raw_log}"
  TERM=xterm \
    MALLOC_ARENA_MAX=2 \
    TCPQUALITY_OUTPUT_DIR="${artifact_dir}" \
    timeout --signal=TERM --kill-after=30s "${TEST_TIMEOUT}" \
    nice -n 10 bash "${entry_script}" "${TEST_ARGS[@]}" \
    >> "${raw_log}" 2>&1
  exit_code=$?
else
  echo "[tcpquality-auto] 入口脚本主源和备用源均不可用。" >> "${raw_log}"
  exit_code=90
fi
set -e

sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g' "${raw_log}" \
  | tr '\r' '\n' \
  > "${clean_log}" \
  || cp -f "${raw_log}" "${clean_log}"

end_time="$(now_local)"

report_url="$(
  grep -Eo 'https?://tcpquality\.ibsgss\.uk/r/[A-Za-z0-9_-]+' "${clean_log}" 2>/dev/null \
    | tail -n 1 \
    || true
)"

report_upload_failed=0
report_recovered=0
report_recovery_attempted=0
rootfs_fallback=0

log_has 'SVG 报告上传失败|已跳过 SVG 报告上传' && report_upload_failed=1 || true
log_has '预构建 rootfs 不可用，尝试下一来源|预构建 rootfs 下载失败，回退官方 Debian OCI|官方 Debian OCI rootfs 下载失败，尝试本地构建方式' && rootfs_fallback=1 || true

if [[ -z "${report_url}" && "${exit_code}" -eq 0 ]]; then
  current_csv="$(find_current_csv)"
  if [[ -n "${current_csv}" ]]; then
    report_recovery_attempted=1
    echo "[tcpquality-auto] 上游未返回有效 /r/ 链接，开始使用本次 CSV 在宿主机恢复上传。" >> "${raw_log}"

    if recovered_report_url="$(recover_report_upload "${current_csv}")"; then
      report_url="${recovered_report_url}"
      report_recovered=1

      sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g' "${raw_log}" \
        | tr '\r' '\n' \
        > "${clean_log}" \
        || true
    fi
  else
    echo "[tcpquality-auto] 上游未返回有效 /r/ 链接，且未找到本次测试持久化 CSV，无法恢复上传。" >> "${raw_log}"
  fi
fi

reason="$(diagnose_failure)"
status=""
msg=""
caption=""
return_code="${exit_code}"

low_mem_note=""
if (( mem_kb > 0 && mem_kb < 262144 )); then
  low_mem_note="低内存环境：RAM 约 $((mem_kb / 1024)) MB，Swap 约 $((swap_kb / 1024)) MB"
fi

if [[ "${exit_code}" -eq 0 && -n "${report_url}" ]]; then
  status="success"
  return_code=0

  msg="✅ TcpQuality 测试完成

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}

在线结果：
${report_url}"

  notes=()
  notes+=("运行档位：${ACTIVE_PROFILE}")
  if [[ "${entry_source}" == "fallback" ]]; then
    notes+=("主入口不可用，已自动切换官方 GitHub Raw 备用源")
  fi
  if [[ "${rootfs_fallback}" -eq 1 ]]; then
    notes+=("rootfs 下载过程中发生过自动回退，但最终测试成功")
  fi
  if [[ "${report_recovered}" -eq 1 ]]; then
    notes+=("上游首次报告上传失败，已使用本次 CSV 自动恢复上传")
  fi
  if [[ -n "${low_mem_note}" ]]; then
    notes+=("${low_mem_note}")
  fi

  if (( ${#notes[@]} > 0 )); then
    note_text="$(IFS='；'; echo "${notes[*]}")"
    msg="${msg}

备注：${note_text}"
  fi

  caption="✅ ${SERVER_NAME} · TcpQuality 完整测试日志"

elif [[ -n "${report_url}" ]]; then
  status="partial"
  msg="⚠️ TcpQuality 测试部分完成

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}
原因：${reason}（退出码 ${exit_code}）

在线结果：
${report_url}"
  if [[ -n "${low_mem_note}" ]]; then
    msg="${msg}

备注：${low_mem_note}"
  fi
  caption="⚠️ ${SERVER_NAME} · TcpQuality 部分完成日志"

elif [[ "${exit_code}" -eq 0 ]]; then
  status="partial"
  return_code=0

  if [[ "${report_upload_failed}" -eq 1 && "${report_recovery_attempted}" -eq 1 ]]; then
    reason="测试主体已执行结束；上游首次上传失败，宿主机恢复上传也未成功"
  elif [[ "${report_upload_failed}" -eq 1 ]]; then
    reason="测试主体已执行结束，但在线报告上传失败，且没有可用于恢复上传的本次 CSV"
  elif [[ "${report_recovery_attempted}" -eq 1 ]]; then
    reason="测试进程正常结束，但在线报告恢复上传未成功"
  else
    reason="测试进程正常结束，但未检测到有效的 /r/ 在线报告链接"
  fi

  msg="⚠️ TcpQuality 测试部分完成

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}
原因：${reason}

建议：查看本地测试日志确认具体阶段；不会再把 rootfs 下载地址误报为测试结果。"
  if [[ -n "${low_mem_note}" ]]; then
    msg="${msg}

备注：${low_mem_note}"
  fi
  caption="⚠️ ${SERVER_NAME} · TcpQuality 部分完成日志"

else
  status="failure"

  case "${exit_code}" in
    75) reason="已有 TcpQuality 测试任务正在运行，本次已跳过" ;;
    90) reason="TcpQuality 入口脚本主源和备用源均下载失败" ;;
    124|137) reason="测试超时（${TEST_TIMEOUT}）" ;;
    *)
      if [[ "${reason}" == "TcpQuality 执行异常" ]]; then
        reason="测试进程退出码 ${exit_code}"
      fi
      ;;
  esac

  msg="❌ TcpQuality 测试失败

服务器：${SERVER_NAME}
开始：${start_time}
完成：${end_time}
原因：${reason}"
  if [[ -n "${low_mem_note}" ]]; then
    msg="${msg}

备注：${low_mem_note}"
  fi
  caption="❌ ${SERVER_NAME} · TcpQuality 错误日志"
fi

push_failed=0
send_message "${msg}" || push_failed=1

if [[ "${SEND_FULL_LOG^^}" == "Y" ]]; then
  sleep 2
  send_document "${clean_log}" "${caption}" || push_failed=1
fi

find "${LOG_DIR}" -type f -mtime +"${KEEP_DAYS}" -delete 2>/dev/null || true
find "${LOG_DIR}" -mindepth 1 -maxdepth 1 -type d -name '*.artifacts' -mtime +"${KEEP_DAYS}" -exec rm -rf {} + 2>/dev/null || true

if [[ "${push_failed}" -ne 0 ]]; then
  echo "TcpQuality 状态：${status}；但 Telegram 推送失败。" >&2
  if [[ "${return_code}" -eq 0 ]]; then
    exit 2
  fi
fi

exit "${return_code}"
RUNNER_EOF

  chmod 700 "${RUNNER}"
}

write_systemd_units() {
  mkdir -p "$(dirname "${SERVICE_FILE}")"

  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=TcpQuality Auto Network Test
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=TERM=xterm
ExecStart=${RUNNER}
TimeoutStartSec=1h
Nice=10

[Install]
WantedBy=multi-user.target
EOF

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

  systemctl daemon-reload
}

ensure_crond_running() {
  rc-update add crond default >/dev/null 2>&1 || true
  rc-service crond start >/dev/null 2>&1 || true

  if ! pgrep -x crond >/dev/null 2>&1; then
    crond >/dev/null 2>&1 || true
  fi

  pgrep -x crond >/dev/null 2>&1 || die "crond 未能启动。"
}

write_cron_file() {
  mkdir -p "$(dirname "${CRON_FILE}")" "${LOG_DIR}"
  chmod 700 "${LOG_DIR}"

  local hh mm
  hh="${RUN_TIME%%:*}"
  mm="${RUN_TIME##*:}"

  cat > "${CRON_FILE}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CRON_TZ=${SCHEDULE_TZ}
${mm} ${hh} * * * root ${RUNNER} >> ${LOG_DIR}/cron.log 2>&1
EOF

  chmod 0644 "${CRON_FILE}"
  ensure_crond_running
}

remove_scheduler_files() {
  case "$(host_backend)" in
    systemd)
      systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true
      systemctl stop "${SERVICE_UNIT}" >/dev/null 2>&1 || true
      rm -f "${SERVICE_FILE}" "${TIMER_FILE}"
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    cron)
      rm -f "${CRON_FILE}"
      ;;
  esac
}

install_manager_self() {
  mkdir -p "$(dirname "${MANAGER_PATH}")"

  if [[ -f "${SCRIPT_SELF}" ]]; then
    local current_real="" target_real=""
    current_real="$(readlink -f "${SCRIPT_SELF}" 2>/dev/null || true)"
    target_real="$(readlink -f "${MANAGER_PATH}" 2>/dev/null || true)"

    if [[ -n "${current_real}" && "${current_real}" == "${target_real}" ]]; then
      chmod 755 "${MANAGER_PATH}"
    else
      install -m 0755 "${SCRIPT_SELF}" "${MANAGER_PATH}"
    fi
  else
    die "无法安装管理脚本自身。"
  fi
}

compute_next_run() {
  local tz="$1"
  local hhmm="$2"

  local now_epoch today target_epoch next_str
  now_epoch="$(TZ="${tz}" date +%s 2>/dev/null || true)"
  today="$(TZ="${tz}" date '+%Y-%m-%d' 2>/dev/null || true)"
  target_epoch="$(TZ="${tz}" date -d "${today} ${hhmm}:00" +%s 2>/dev/null || true)"

  if [[ -z "${now_epoch}" || -z "${today}" || -z "${target_epoch}" ]]; then
    return 1
  fi

  if (( target_epoch <= now_epoch )); then
    target_epoch="$(TZ="${tz}" date -d "${today} +1 day ${hhmm}:00" +%s 2>/dev/null || true)"
  fi

  [[ -n "${target_epoch}" ]] || return 1
  next_str="$(TZ="${tz}" date -d "@${target_epoch}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || true)"
  [[ -n "${next_str}" ]] || return 1

  printf '%s' "${next_str}"
}

install_or_configure() {
  need_root "$@"
  check_os
  ensure_dependencies
  warn_low_memory_interactive

  mkdir -p "${LOG_DIR}"
  chmod 700 "${LOG_DIR}"

  local existed=0
  local was_enabled=0

  is_installed && existed=1
  scheduler_enabled && was_enabled=1 || true

  echo
  line
  echo -e "${C_BOLD} TcpQuality Auto 安装 / 配置${C_RESET}"
  line

  prompt_config

  save_config
  write_runner
  install_manager_self

  case "$(host_backend)" in
    systemd)
      write_systemd_units
      ;;
    cron)
      :
      ;;
  esac

  if [[ "${existed}" -eq 0 ]]; then
    start_app install
    ok "首次安装完成，定时任务已启用。"
  else
    if [[ "${was_enabled}" -eq 1 ]]; then
      start_app install
      ok "配置已更新，定时任务保持启用。"
    else
      case "$(host_backend)" in
        systemd)
          systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true
          ;;
        cron)
          rm -f "${CRON_FILE}"
          ;;
      esac
      ok "配置已更新；检测到任务此前处于停止状态，因此继续保持停止。"
    fi
  fi

  echo
  echo "版本：  ${APP_VERSION}"
  echo "服务器：${SERVER_NAME}"
  echo "计划：  每天 ${RUN_TIME}"
  echo "时区：  ${SCHEDULE_TZ}"
  echo "模式：  ${RUN_PROFILE}"
  if [[ "${SEND_FULL_LOG^^}" == "Y" ]]; then
    echo "TG日志：发送完整测试日志"
  else
    echo "TG日志：仅发送摘要，不发送完整日志"
  fi
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

  local run_now=""
  read -r -p "是否现在立即执行一次完整 TcpQuality 测试？[y/N]: " run_now
  if [[ "${run_now}" =~ ^[Yy]$ ]]; then
    run_test
  fi
}

start_app() {
  need_root "$@"
  require_installed

  case "$(host_backend)" in
    systemd)
      systemctl enable --now "${TIMER_UNIT}" >/dev/null
      ;;
    cron)
      load_config
      write_cron_file
      ;;
    *)
      die "无法启动定时任务：后端不受支持。"
      ;;
  esac

  if [[ "${1:-}" != "install" ]]; then
    ok "定时任务已启动。"
    show_next_run false
  fi
}

stop_app() {
  need_root "$@"
  require_installed

  case "$(host_backend)" in
    systemd)
      systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true
      ;;
    cron)
      rm -f "${CRON_FILE}"
      ;;
    *)
      die "无法停止定时任务：后端不受支持。"
      ;;
  esac

  if [[ "${1:-}" != "install" ]]; then
    ok "定时任务已停止。配置和历史日志均已保留。"
  fi
}

restart_app() {
  need_root "$@"
  require_installed

  case "$(host_backend)" in
    systemd)
      systemctl enable "${TIMER_UNIT}" >/dev/null 2>&1 || true
      systemctl restart "${TIMER_UNIT}" >/dev/null
      ;;
    cron)
      load_config
      write_cron_file
      ;;
    *)
      die "无法重启定时任务：后端不受支持。"
      ;;
  esac

  ok "定时任务已重启。"
  show_next_run false
}

run_test() {
  need_root "$@"
  require_installed
  warn_low_memory_interactive

  if runner_active; then
    warn "检测到已有 TcpQuality 测试正在运行，本次不会重复启动。"
    return 0
  fi

  info "开始执行 TcpQuality 完整测试..."
  echo "测试完成后会自动发送 Telegram 摘要；是否发送完整日志以当前配置为准。"
  echo

  if "${RUNNER}"; then
    ok "测试执行完成。"
  else
    local rc=$?
    warn "测试执行结束，退出码：${rc}。请查看日志：sudo ${APP_NAME} logs"
    return "${rc}"
  fi
}

show_next_run() {
  local heading="${1:-true}"
  require_installed
  load_config

  if [[ "${heading}" == "true" ]]; then
    echo
    line
    echo -e "${C_BOLD} 下一次执行时间${C_RESET}"
    line
  fi

  if scheduler_enabled; then
    local next_run=""
    next_run="$(compute_next_run "${SCHEDULE_TZ}" "${RUN_TIME}" || true)"

    echo "后端：$(host_backend)"
    echo "计划：每天 ${RUN_TIME}（${SCHEDULE_TZ}）"

    if [[ -n "${next_run}" ]]; then
      echo "下一次执行：${next_run}"
    else
      echo "下一次执行：无法计算（请检查 date / tzdata）"
    fi
  else
    warn "定时任务当前未启用，因此没有活动的下一次执行计划。"
    echo "恢复任务：sudo ${APP_NAME} start"
  fi
}

show_status() {
  require_installed
  load_config

  local timer_enabled="否"
  local timer_active_text="否"
  local running_text="否"

  scheduler_enabled && timer_enabled="是" || true
  scheduler_active && timer_active_text="是" || true
  runner_active && running_text="是" || true

  echo
  line
  echo -e "${C_BOLD} TcpQuality Auto 状态${C_RESET}"
  line
  printf '%-18s %s\n' "版本：" "${APP_VERSION}"
  printf '%-18s %s\n' "服务器：" "${SERVER_NAME:-未知}"
  printf '%-18s %s\n' "执行时间：" "${RUN_TIME:-未知}"
  printf '%-18s %s\n' "任务时区：" "${SCHEDULE_TZ:-未知}"
  printf '%-18s %s\n' "运行模式：" "${RUN_PROFILE:-AUTO}"
  printf '%-18s %s\n' "Chat ID：" "${TG_CHAT_ID:-未知}"
  printf '%-18s %s\n' "Thread ID：" "${TG_THREAD_ID:-未设置}"
  printf '%-18s %s\n' "Bot Token：" "已配置（不显示）"
  printf '%-18s %s\n' "调度后端：" "$(host_backend)"
  if [[ "${SEND_FULL_LOG^^}" == "Y" ]]; then
    printf '%-18s %s\n' "TG 完整日志：" "发送"
  else
    printf '%-18s %s\n' "TG 完整日志：" "不发送"
  fi
  echo
  printf '%-18s %s\n' "定时任务启用：" "${timer_enabled}"
  printf '%-18s %s\n' "调度器运行中：" "${timer_active_text}"
  printf '%-18s %s\n' "测试正在运行：" "${running_text}"

  local mem_kb swap_kb
  mem_kb="$(memory_total_kb)"
  swap_kb="$(swap_total_kb)"
  printf '%-18s %s\n' "系统内存：" "$((mem_kb / 1024)) MB"
  printf '%-18s %s\n' "系统 Swap：" "$((swap_kb / 1024)) MB"

  echo
  show_next_run false
}

show_logs_cli() {
  require_installed

  echo
  line
  echo -e "${C_BOLD} TcpQuality Auto 最近运行日志${C_RESET}"
  line

  if [[ "$(host_backend)" == "cron" && -f "${LOG_DIR}/cron.log" ]]; then
    echo "Cron 调度日志（最近 60 行）："
    tail -n 60 "${LOG_DIR}/cron.log" || true
    echo
  fi

  local latest=""
  latest="$(find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' ! -name '*.raw.log' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2- || true)"

  if [[ -n "${latest}" && -f "${latest}" ]]; then
    line
    echo "最新测试日志文件：${latest}"
    line
    tail -n 150 "${latest}" || true
  else
    echo "暂无测试日志。"
  fi
}

uninstall_app() {
  need_root "$@"

  if is_installed; then
    case "$(host_backend)" in
      systemd)
        systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true
        systemctl stop "${SERVICE_UNIT}" >/dev/null 2>&1 || true
        ;;
      cron)
        rm -f "${CRON_FILE}"
        ;;
    esac
  fi

  rm -f "${RUNNER}" "${MANAGER_PATH}" "${CONF_FILE}" "${SERVICE_FILE}" "${TIMER_FILE}" "${CRON_FILE}"
  rm -rf "${LOG_DIR}"

  if [[ "$(host_backend)" == "systemd" ]]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  ok "TcpQuality Auto 已卸载。"
}

show_menu() {
  clear 2>/dev/null || true
  line
  echo -e "${C_BOLD}      TcpQuality Auto 管理面板${C_RESET}"
  line
  echo "版本：${APP_VERSION} | 状态：$(is_installed && echo 已安装 || echo 未安装)"
  line
  cat <<'EOF'
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
EOF
  echo
}

interactive_menu() {
  local choice=""
  while true; do
    show_menu
    read -r -p "请选择 [0-10]: " choice
    case "${choice}" in
      1) install_or_configure "$@"; pause_menu ;;
      2) run_test "$@"; pause_menu ;;
      3) show_status; pause_menu ;;
      4) show_logs_cli; pause_menu ;;
      5) install_or_configure "$@"; pause_menu ;;
      6) start_app "$@"; pause_menu ;;
      7) stop_app "$@"; pause_menu ;;
      8) restart_app "$@"; pause_menu ;;
      9) show_next_run true; pause_menu ;;
      10)
        local confirm=""
        read -r -p "确认停止并卸载 TcpQuality Auto？[y/N]: " confirm
        if [[ "${confirm}" =~ ^[Yy]$ ]]; then
          uninstall_app "$@"
        fi
        pause_menu
        ;;
      0) exit 0 ;;
      *) warn "无效选项，请重新输入。"; sleep 1 ;;
    esac
  done
}

usage() {
  cat <<EOF
TcpQuality Auto ${APP_VERSION}
纯 Bash / 无 Python / Debian+Alpine / 低内存自适应

用法：
  sudo ${APP_NAME}                 进入交互式菜单
  sudo ${APP_NAME} install         安装 / 更新
  sudo ${APP_NAME} config          修改配置
  sudo ${APP_NAME} run             立即执行一次测试
  sudo ${APP_NAME} status          查看状态
  sudo ${APP_NAME} logs            查看日志
  sudo ${APP_NAME} start           启动 / 恢复定时任务
  sudo ${APP_NAME} stop            停止定时任务
  sudo ${APP_NAME} restart         重启定时任务
  sudo ${APP_NAME} next            查看下一次执行时间
  sudo ${APP_NAME} uninstall       停止并卸载
EOF
}

main() {
  local cmd="${1:-menu}"

  case "${cmd}" in
    install|update)
      shift || true
      install_or_configure "$@"
      ;;
    config)
      shift || true
      install_or_configure "$@"
      ;;
    run)
      shift || true
      run_test "$@"
      ;;
    status)
      shift || true
      show_status
      ;;
    logs)
      shift || true
      show_logs_cli
      ;;
    start)
      shift || true
      start_app "$@"
      ;;
    stop)
      shift || true
      stop_app "$@"
      ;;
    restart)
      shift || true
      restart_app "$@"
      ;;
    next)
      shift || true
      show_next_run true
      ;;
    uninstall|remove)
      shift || true
      uninstall_app "$@"
      ;;
    menu|"")
      shift || true
      interactive_menu "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      err "未知命令：${cmd}"
      echo
      usage
      exit 1
      ;;
  esac
}

main "$@"
