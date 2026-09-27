#!/usr/bin/env bash
set -Eeuo pipefail

# TcpQuality Auto portable bootstrap
# Version: 2026.09.27.5
#
# - Debian/Ubuntu: automatically installs missing bootstrap python3 dependency.
# - Alpine: apk + Cronie/OpenRC compatibility backend.
# - Keeps the validated 2026.09.26.1 report-upload recovery patch.
#
# The pinned hotfix below itself pins the complete installer at:
# 9cfa6fcde0a134e2233ce90d4a479c92d251fe19

HOTFIX_COMMIT="260c5ab03ea26f58d39acc2037006f273a5e0b07"
HOTFIX_URL="https://raw.githubusercontent.com/shaolonger/tcpquality-auto/${HOTFIX_COMMIT}/tcpquality-auto-install.sh"
TARGET_VERSION="2026.09.27.5"

die() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

os_id() {
  if [[ -r /etc/os-release ]]; then
    (
      # shellcheck disable=SC1091
      . /etc/os-release
      printf '%s' "${ID:-}"
    )
  fi
}

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "该操作需要 root 权限；请使用 root 运行。"
  fi
}

ensure_bootstrap_dependencies() {
  local id
  id="$(os_id)"

  case "${id}" in
    alpine)
      printf '[INFO] 检测到 Alpine，安装 bootstrap / Cronie / OpenRC 依赖...\n'
      run_root apk add --no-cache \
        bash \
        curl \
        ca-certificates \
        python3 \
        coreutils \
        findutils \
        tzdata \
        procps \
        cronie \
        cronie-openrc \
        openrc \
        tar \
        xz \
        zstd \
        util-linux >/dev/null
      ;;

    debian|ubuntu)
      local missing=0
      command -v bash >/dev/null 2>&1 || missing=1
      command -v curl >/dev/null 2>&1 || missing=1
      command -v python3 >/dev/null 2>&1 || missing=1
      [[ -d /usr/share/zoneinfo ]] || missing=1

      if [[ "${missing}" -eq 1 ]]; then
        printf '[INFO] Debian/Ubuntu 缺少 bootstrap 依赖，自动安装 python3 等组件...\n'
        if [[ "${EUID}" -eq 0 ]]; then
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -y
          apt-get install -y bash curl ca-certificates python3 coreutils tzdata
        elif command -v sudo >/dev/null 2>&1; then
          sudo env DEBIAN_FRONTEND=noninteractive apt-get update -y
          sudo env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y bash curl ca-certificates python3 coreutils tzdata
        else
          die "缺少 python3，且当前不是 root；请使用 root 重新运行。"
        fi
      fi
      ;;

    *)
      if ! command -v python3 >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          printf '[INFO] 检测到 apt 系统，安装 python3 bootstrap 依赖...\n'
          run_root apt-get update -y
          run_root apt-get install -y python3 curl ca-certificates
        elif command -v apk >/dev/null 2>&1; then
          printf '[INFO] 检测到 apk 系统，安装 python3 bootstrap 依赖...\n'
          run_root apk add --no-cache python3 curl ca-certificates bash
        else
          die "缺少 python3，且无法识别可用的软件包管理器。"
        fi
      fi
      ;;
  esac

  command -v bash >/dev/null 2>&1 || die "bash 不可用。"
  command -v curl >/dev/null 2>&1 || die "curl 不可用。"
  command -v python3 >/dev/null 2>&1 || die "python3 不可用。"
}

setup_alpine_compat() {
  [[ "$(os_id)" == "alpine" ]] || return 0

  printf '[INFO] 配置 Alpine Cronie/OpenRC 兼容后端...\n'

  run_root mkdir -p \
    /usr/local/bin \
    /usr/local/sbin \
    /etc/systemd/system \
    /etc/cron.d \
    /var/log/tcpquality-auto

  run_root chmod 0755 /usr/local/bin /usr/local/sbin
  run_root chmod 0700 /var/log/tcpquality-auto

  local tmp_compat
  tmp_compat="$(mktemp -d "${TMPDIR:-/tmp}/tcpquality-auto-alpine-compat.XXXXXX")"

  cat > "${tmp_compat}/systemd-analyze" <<'EOF'
#!/usr/bin/env bash
# TcpQuality Auto Alpine compatibility shim.
case "${1:-}" in
  calendar) exit 0 ;;
  *) exit 0 ;;
esac
EOF

  cat > "${tmp_compat}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -u

CONF="/etc/tcpquality-auto.conf"
RUNNER="/usr/local/sbin/tcpquality-auto-run.sh"
LOG_DIR="/var/log/tcpquality-auto"
TIMER="tcpquality-auto.timer"
SERVICE="tcpquality-auto.service"
CRON_FILE="/etc/cron.d/tcpquality-auto"

load_conf() {
  RUN_TIME="20:30"
  SCHEDULE_TZ="Asia/Shanghai"
  if [[ -r "${CONF}" ]]; then
    # shellcheck disable=SC1090
    . "${CONF}"
  fi
}

write_cron() {
  load_conf

  local hh="${RUN_TIME%%:*}"
  local mm="${RUN_TIME##*:}"

  mkdir -p /etc/cron.d "${LOG_DIR}"
  chmod 700 "${LOG_DIR}"

  cat > "${CRON_FILE}" <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CRON_TZ=${SCHEDULE_TZ}
${mm} ${hh} * * * root ${RUNNER} >> ${LOG_DIR}/cron.log 2>&1
CRON

  chmod 0644 "${CRON_FILE}"
}

start_crond() {
  command -v rc-update >/dev/null 2>&1 \
    && rc-update add crond default >/dev/null 2>&1 || true

  command -v rc-service >/dev/null 2>&1 \
    && rc-service crond start >/dev/null 2>&1 || true

  pgrep -x crond >/dev/null 2>&1 || crond >/dev/null 2>&1 || true
  pgrep -x crond >/dev/null 2>&1
}

timer_active() {
  [[ -f "${CRON_FILE}" ]] && pgrep -x crond >/dev/null 2>&1
}

service_active() {
  pgrep -f "${RUNNER}" >/dev/null 2>&1
}

action="${1:-}"
shift || true

unit=""
for arg in "$@"; do
  case "${arg}" in
    --*) ;;
    *.timer|*.service) unit="${arg}" ;;
  esac
done

case "${action}" in
  daemon-reload|reset-failed)
    exit 0
    ;;

  is-enabled)
    [[ "${unit}" == "${TIMER}" && -f "${CRON_FILE}" ]]
    exit $?
    ;;

  is-active)
    if [[ "${unit}" == "${TIMER}" ]]; then
      timer_active
    elif [[ "${unit}" == "${SERVICE}" ]]; then
      service_active
    else
      exit 1
    fi
    exit $?
    ;;

  enable)
    if [[ "${unit}" == "${TIMER}" ]]; then
      write_cron
      start_crond
      exit $?
    fi
    exit 0
    ;;

  disable)
    [[ "${unit}" == "${TIMER}" ]] && rm -f "${CRON_FILE}"
    exit 0
    ;;

  restart)
    if [[ "${unit}" == "${TIMER}" ]]; then
      write_cron
      start_crond
      exit $?
    elif [[ "${unit}" == "${SERVICE}" ]]; then
      pkill -TERM -f "${RUNNER}" >/dev/null 2>&1 || true
      sleep 1
      "${RUNNER}"
      exit $?
    fi
    exit 0
    ;;

  start)
    if [[ "${unit}" == "${TIMER}" ]]; then
      write_cron
      start_crond
      exit $?
    elif [[ "${unit}" == "${SERVICE}" ]]; then
      service_active && exit 0
      "${RUNNER}"
      exit $?
    fi
    exit 0
    ;;

  stop)
    if [[ "${unit}" == "${TIMER}" ]]; then
      rm -f "${CRON_FILE}"
      exit 0
    elif [[ "${unit}" == "${SERVICE}" ]]; then
      pkill -TERM -f "${RUNNER}" >/dev/null 2>&1 || true
      exit 0
    fi
    exit 0
    ;;

  status)
    if [[ "${unit}" == "${TIMER}" ]]; then
      echo "● ${TIMER} - TcpQuality Auto Daily Timer (Cronie backend)"
      if timer_active; then
        echo "   Active: active (running)"
      elif [[ -f "${CRON_FILE}" ]]; then
        echo "   Active: inactive (crond not running)"
      else
        echo "   Active: inactive (disabled)"
      fi
    else
      echo "● ${SERVICE} - TcpQuality Auto Network Test"
      if service_active; then
        echo "   Active: active (running)"
      else
        echo "   Active: inactive (dead)"
      fi
    fi
    exit 0
    ;;

  show)
    if [[ "${unit}" == "${SERVICE}" ]] && service_active; then
      echo "ActiveState=active"
      echo "SubState=running"
      echo "Result=success"
      echo "ExecMainStatus=0"
    else
      echo "ActiveState=inactive"
      echo "SubState=dead"
      echo "Result=success"
      echo "ExecMainStatus=0"
    fi
    exit 0
    ;;

  list-timers)
    load_conf
    echo "Alpine 定时后端：Cronie + OpenRC"
    echo "计划：每天 ${RUN_TIME} (${SCHEDULE_TZ})"

    if timer_active; then
      echo "状态：已启用，crond 正在运行"
    elif [[ -f "${CRON_FILE}" ]]; then
      echo "状态：已配置，但 crond 未运行"
    else
      echo "状态：未启用"
    fi
    exit 0
    ;;

  *)
    echo "[WARN] Alpine systemctl 兼容层未处理：${action} ${unit}" >&2
    exit 0
    ;;
esac
EOF

  cat > "${tmp_compat}/journalctl" <<'EOF'
#!/usr/bin/env bash
set -u

LOG_DIR="/var/log/tcpquality-auto"

follow=0
for arg in "$@"; do
  [[ "${arg}" == "-f" ]] && follow=1
done

mkdir -p "${LOG_DIR}"

if [[ "${follow}" -eq 1 ]]; then
  touch "${LOG_DIR}/cron.log"
  exec tail -f "${LOG_DIR}/cron.log"
fi

if [[ -f "${LOG_DIR}/cron.log" ]]; then
  tail -n 150 "${LOG_DIR}/cron.log"
  exit 0
fi

latest="$(
  find "${LOG_DIR}" \
    -maxdepth 1 \
    -type f \
    -name '*.log' \
    ! -name '*.raw.log' \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2- \
    || true
)"

if [[ -n "${latest}" && -f "${latest}" ]]; then
  tail -n 150 "${latest}"
else
  echo "暂无 Alpine 定时任务日志。"
fi
EOF

  chmod 0755 \
    "${tmp_compat}/systemctl" \
    "${tmp_compat}/systemd-analyze" \
    "${tmp_compat}/journalctl"

  run_root install -m 0755 "${tmp_compat}/systemctl" /usr/local/bin/systemctl
  run_root install -m 0755 "${tmp_compat}/systemd-analyze" /usr/local/bin/systemd-analyze
  run_root install -m 0755 "${tmp_compat}/journalctl" /usr/local/bin/journalctl

  rm -rf "${tmp_compat}"

  run_root rc-update add crond default >/dev/null 2>&1 || true
  run_root rc-service crond start >/dev/null 2>&1 || true

  if ! pgrep -x crond >/dev/null 2>&1; then
    run_root crond >/dev/null 2>&1 || true
  fi

  pgrep -x crond >/dev/null 2>&1 \
    || die "Alpine crond 未能启动。"
}

ensure_bootstrap_dependencies
setup_alpine_compat

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tcpquality-auto-bootstrap.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

hotfix_script="${tmp_dir}/tcpquality-auto-hotfix.sh"

printf '[INFO] 下载报告恢复基础热修复 %s...\n' "${HOTFIX_COMMIT:0:12}"
curl -fsSL \
  --retry 4 \
  --retry-all-errors \
  --retry-delay 2 \
  --connect-timeout 15 \
  --max-time 120 \
  "${HOTFIX_URL}" -o "${hotfix_script}" \
  || die "无法下载基础热修复：${HOTFIX_URL}"

[[ -s "${hotfix_script}" ]] || die "基础热修复脚本为空。"

# Keep all report-recovery logic from the pinned hotfix, but expose this
# portable build as the actual manager version.
python3 - "${hotfix_script}" "${TARGET_VERSION}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")

old = 'PATCH_VERSION="2026.09.26.1"'
new = f'PATCH_VERSION="{version}"'

if text.count(old) != 1:
    raise SystemExit(
        f"[FAIL] 基础热修复版本锚点异常：预期 1 处，实际 {text.count(old)} 处"
    )

text = text.replace(old, new, 1)
text = text.replace(
    "# Version: 2026.09.26.1",
    f"# Version: {version}",
    1,
)

path.write_text(text, encoding="utf-8")
PY

chmod 0755 "${hotfix_script}"
bash -n "${hotfix_script}" || die "生成后的热修复脚本未通过 bash -n 语法检查。"

printf '[ OK ] Bootstrap 准备完成，目标版本：%s\n' "${TARGET_VERSION}"
exec bash "${hotfix_script}" "$@"
