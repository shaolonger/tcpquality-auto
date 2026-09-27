#!/usr/bin/env bash
set -Eeuo pipefail

# TcpQuality Auto portable bootstrap
# Version: 2026.09.27.1
# Alpine: apk + Cronie/OpenRC compatibility backend
# Debian/Ubuntu: keeps the existing systemd backend unchanged.

BASE_COMMIT="260c5ab03ea26f58d39acc2037006f273a5e0b07"
BASE_URL="https://raw.githubusercontent.com/shaolonger/tcpquality-auto/${BASE_COMMIT}/tcpquality-auto-install.sh"
COMPAT_DIR="/usr/local/libexec/tcpquality-auto-compat"
MANAGER="/usr/local/sbin/tcpquality-auto"

die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

is_alpine() {
  [[ -r /etc/os-release ]] || return 1
  (
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "alpine" ]]
  )
}

setup_alpine_compat() {
  printf '[INFO] 检测到 Alpine，安装 apk/Cronie/OpenRC 依赖...\n'
  apk add --no-cache \
    bash curl ca-certificates coreutils findutils tzdata python3 procps cronie openrc \
    tar xz zstd util-linux >/dev/null

  mkdir -p "${COMPAT_DIR}"

  cat > "${COMPAT_DIR}/systemd-analyze" <<'EOF'
#!/usr/bin/env bash
# TcpQuality Auto Alpine compatibility shim.
case "${1:-}" in
  calendar)
    # RUN_TIME and timezone are already validated by the manager itself.
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

  cat > "${COMPAT_DIR}/systemctl" <<'EOF'
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
  command -v rc-update >/dev/null 2>&1 && rc-update add crond default >/dev/null 2>&1 || true
  command -v rc-service >/dev/null 2>&1 && rc-service crond start >/dev/null 2>&1 || true
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
    fi
    if [[ "${unit}" == "${SERVICE}" ]]; then
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
    fi
    if [[ "${unit}" == "${SERVICE}" ]]; then
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
    fi
    if [[ "${unit}" == "${SERVICE}" ]]; then
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

  cat > "${COMPAT_DIR}/journalctl" <<'EOF'
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
  find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' ! -name '*.raw.log' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -n 1 | cut -d' ' -f2- || true
)"

if [[ -n "${latest}" && -f "${latest}" ]]; then
  tail -n 150 "${latest}"
else
  echo "暂无 Alpine 定时任务日志。"
fi
EOF

  chmod 0755 \
    "${COMPAT_DIR}/systemctl" \
    "${COMPAT_DIR}/systemd-analyze" \
    "${COMPAT_DIR}/journalctl"

  # Make the compatibility commands visible to the current installer run.
  export PATH="${COMPAT_DIR}:${PATH}"

  # Start and enable Cronie now. The timer shim will write the actual job later.
  rc-update add crond default >/dev/null 2>&1 || true
  rc-service crond start >/dev/null 2>&1 || crond >/dev/null 2>&1 || true
}

patch_installed_manager() {
  [[ -f "${MANAGER}" ]] || return 0

  python3 - "${MANAGER}" "${COMPAT_DIR}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
compat = sys.argv[2]
text = path.read_text(encoding="utf-8")

marker = "# TCPQUALITY_AUTO_ALPINE_COMPAT"
if marker in text:
    raise SystemExit(0)

lines = text.splitlines(True)
insert_at = 1 if lines and lines[0].startswith("#!") else 0
block = (
    "\n"
    f"{marker}\n"
    'if [[ -r /etc/os-release ]]; then\n'
    '  _tq_id="$(. /etc/os-release; printf \'%s\' "${ID:-}")"\n'
    f'  [[ "${{_tq_id}}" == "alpine" ]] && export PATH="{compat}:$PATH"\n'
    '  unset _tq_id\n'
    'fi\n\n'
)
lines.insert(insert_at, block)
path.write_text("".join(lines), encoding="utf-8")
PY

  chmod 0755 "${MANAGER}"
  bash -n "${MANAGER}" || die "安装后的管理器未通过 bash -n 检查。"
}

if is_alpine; then
  setup_alpine_compat
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tcpquality-auto-portable.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
base_script="${tmp_dir}/tcpquality-auto-install.sh"

printf '[INFO] 下载 TcpQuality Auto 基础版本 %s...\n' "${BASE_COMMIT:0:12}"
curl -fsSL \
  --retry 4 \
  --retry-all-errors \
  --retry-delay 2 \
  --connect-timeout 15 \
  --max-time 120 \
  "${BASE_URL}" -o "${base_script}" \
  || die "无法下载基础脚本。"

chmod 0755 "${base_script}"
bash -n "${base_script}" || die "基础脚本语法检查失败。"

# Run the current 2026.09.26.1 implementation as a child process. On Alpine
# the compatibility PATH makes its existing systemd-oriented manager use
# Cronie/OpenRC transparently.
set +e
bash "${base_script}" "$@"
rc=$?
set -e

if is_alpine; then
  patch_installed_manager
fi

exit "${rc}"
