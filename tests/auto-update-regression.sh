#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin" "${test_dir}/logs"

sed '/^main "\$@"$/d' "${repo_dir}/tcpquality-auto-install.sh" > "${test_dir}/manager.sh"
# shellcheck disable=SC1091
source "${test_dir}/manager.sh"

CONF_FILE="${test_dir}/config"
RUNNER="${test_dir}/runner"
MANAGER_PATH="${test_dir}/installed-manager"
SERVICE_FILE="${test_dir}/tcpquality-auto.service"
TIMER_FILE="${test_dir}/tcpquality-auto.timer"
UPDATE_SERVICE_FILE="${test_dir}/tcpquality-auto-update.service"
UPDATE_TIMER_FILE="${test_dir}/tcpquality-auto-update.timer"
CRON_FILE="${test_dir}/tcpquality-auto.cron"
LOG_DIR="${test_dir}/logs"
RELEASE_API_URL="https://api.example.test/releases/latest"
RELEASE_RAW_BASE="https://raw.example.test/tcpquality-auto"

printf 'APP_VERSION="2026.10.11.3"\n' > "${MANAGER_PATH}"
printf 'RUNNER_VERSION="2026.10.11.3"\n' > "${RUNNER}"
printf 'existing configuration\n' > "${CONF_FILE}"
printf 'original service\n' > "${SERVICE_FILE}"
printf 'original timer\n' > "${TIMER_FILE}"
printf 'original update service\n' > "${UPDATE_SERVICE_FILE}"
printf 'original update timer\n' > "${UPDATE_TIMER_FILE}"
before_config="$(sha256sum "${CONF_FILE}")"

cat > "${test_dir}/installer.sh" <<'EOF'
#!/usr/bin/env bash
APP_VERSION="2026.10.12.1"
[[ "${1:-}" == upgrade ]] || exit 2
printf 'APP_VERSION="2026.10.12.1"\n' > "${TEST_MANAGER}"
printf 'RUNNER_VERSION="2026.10.12.1"\n' > "${TEST_RUNNER}"
printf 'changed service\n' > "${TEST_SERVICE}"
[[ "${TEST_UPGRADE_FAIL:-0}" == 1 ]] && exit 42
exit 0
EOF

cat > "${test_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
output="" url=""
while (( $# )); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "${url}" in
  https://api.example.test/releases/latest)
    printf '{\n  "tag_name": "%s"\n}\n' "${TEST_RELEASE_TAG}" > "${output}" ;;
  https://raw.example.test/tcpquality-auto/*/tcpquality-auto-install.sh)
    cp "${TEST_INSTALLER}" "${output}" ;;
  *) exit 2 ;;
esac
EOF

cat > "${test_dir}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  is-enabled|is-active) exit 0 ;;
  *) printf '%s\n' "$*" >> "${TEST_DIR}/systemctl-calls" ;;
esac
EOF
chmod +x "${test_dir}/bin/curl" "${test_dir}/bin/systemctl"

export TEST_DIR="${test_dir}" TEST_MANAGER="${MANAGER_PATH}" TEST_RUNNER="${RUNNER}"
export TEST_SERVICE="${SERVICE_FILE}" TEST_INSTALLER="${test_dir}/installer.sh"
export TEST_RELEASE_TAG="v2026.10.12.1" PATH="${test_dir}/bin:${PATH}"
need_root() { :; }
runner_active() { return 1; }
host_backend() { printf systemd; }

version_is_newer '2026.10.11.3' '2026.10.11.2'
version_is_newer '2026.10.12.1' '2026.10.11.99'
if version_is_newer '2026.10.11.2' '2026.10.11.3'; then exit 1; fi
if version_is_newer '2026.10.11.3' '2026.10.11.3'; then exit 1; fi

auto_update_app
grep -q '^APP_VERSION="2026.10.12.1"$' "${MANAGER_PATH}"
grep -q '^RUNNER_VERSION="2026.10.12.1"$' "${RUNNER}"
test "$(sha256sum "${CONF_FILE}")" = "${before_config}"

printf 'APP_VERSION="2026.10.11.3"\n' > "${MANAGER_PATH}"
printf 'RUNNER_VERSION="2026.10.11.3"\n' > "${RUNNER}"
printf 'original service\n' > "${SERVICE_FILE}"
export TEST_UPGRADE_FAIL=1
if auto_update_app; then
  echo 'failed upgrade unexpectedly succeeded' >&2
  exit 1
fi
grep -q '^APP_VERSION="2026.10.11.3"$' "${MANAGER_PATH}"
grep -q '^RUNNER_VERSION="2026.10.11.3"$' "${RUNNER}"
grep -q '^original service$' "${SERVICE_FILE}"
test "$(sha256sum "${CONF_FILE}")" = "${before_config}"
grep -q '^daemon-reload$' "${test_dir}/systemctl-calls"

unset TEST_UPGRADE_FAIL
export TEST_RELEASE_TAG='invalid/tag'
if auto_update_app; then
  echo 'invalid release tag unexpectedly accepted' >&2
  exit 1
fi
grep -q '^APP_VERSION="2026.10.11.3"$' "${MANAGER_PATH}"

echo 'auto-update regression checks passed'
