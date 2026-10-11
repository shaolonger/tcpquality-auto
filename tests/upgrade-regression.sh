#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin"

sed '/^main "\$@"$/d' "${repo_dir}/tcpquality-auto-install.sh" > "${test_dir}/manager.sh"
# shellcheck disable=SC1091
source "${test_dir}/manager.sh"

CONF_FILE="${test_dir}/config"
RUNNER="${test_dir}/runner"
MANAGER_PATH="${test_dir}/installed-manager"
SERVICE_FILE="${test_dir}/tcpquality-auto.service"
TIMER_FILE="${test_dir}/tcpquality-auto.timer"
CRON_FILE="${test_dir}/tcpquality-auto.cron"
LOG_DIR="${test_dir}/logs"
SCRIPT_SELF="${repo_dir}/tcpquality-auto-install.sh"

cat > "${CONF_FILE}" <<'EOF'
SERVER_NAME=regression-vps
SCHEDULE_TZ=Asia/Shanghai
RUN_TIME=20:30
TG_BOT_TOKEN=dummy
TG_CHAT_ID=123
SEND_FULL_LOG=N
RUN_PROFILE=FULL
TEST_TIMEOUT=120m
EOF
touch "${RUNNER}" "${MANAGER_PATH}"
before="$(sha256sum "${CONF_FILE}")"

cat > "${test_dir}/bin/systemd-analyze" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${test_dir}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TEST_DIR}/systemctl-calls"
EOF
chmod +x "${test_dir}/bin/systemd-analyze" "${test_dir}/bin/systemctl"
export TEST_DIR="${test_dir}" PATH="${test_dir}/bin:${PATH}"

need_root() { :; }
check_os() { :; }
ensure_dependencies() { :; }
validate_timezone() { :; }
validate_time() { :; }
host_backend() { printf 'systemd'; }
scheduler_enabled() { return 0; }

upgrade_app
test "$(sha256sum "${CONF_FILE}")" = "${before}"
grep -q '^RUNNER_VERSION="2026.10.11.2"$' "${RUNNER}"
grep -q '^TimeoutStartSec=3h$' "${SERVICE_FILE}"
grep -q 'restart tcpquality-auto.timer' "${test_dir}/systemctl-calls"

scheduler_enabled() { return 1; }
: > "${test_dir}/systemctl-calls"
upgrade_app
test "$(sha256sum "${CONF_FILE}")" = "${before}"
grep -q 'disable --now tcpquality-auto.timer' "${test_dir}/systemctl-calls"

# The earliest installer had a runner and timer but no global manager command.
rm -f "${MANAGER_PATH}"
sed -i '/^SEND_FULL_LOG=/d; /^RUN_PROFILE=/d; /^TEST_TIMEOUT=/d' "${CONF_FILE}"
before="$(sha256sum "${CONF_FILE}")"
scheduler_enabled() { return 0; }
upgrade_app
test -x "${MANAGER_PATH}"
test "$(sha256sum "${CONF_FILE}")" = "${before}"
grep -q '^RUNNER_VERSION="2026.10.11.2"$' "${RUNNER}"

host_backend() { printf 'cron'; }
ensure_crond_running() { :; }
scheduler_enabled() { return 0; }
upgrade_app
test "$(sha256sum "${CONF_FILE}")" = "${before}"
grep -q '^30 20 \* \* \* root ' "${CRON_FILE}"

scheduler_enabled() { return 1; }
upgrade_app
test ! -e "${CRON_FILE}"

echo 'upgrade regression checks passed'
