#!/usr/bin/env bash
set -Eeuo pipefail

# Run on Linux with Bash 4+ (for example: docker run --rm -v "$PWD":/work:ro ubuntu:24.04 bash /work/tests/runner-regression.sh).
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin" "${test_dir}/logs"

awk '/^RUNNER_EOF$/ { exit } found { print } /cat > .*RUNNER_EOF/ { found=1 }' \
  "${repo_dir}/tcpquality-auto-install.sh" > "${test_dir}/runner"
test -s "${test_dir}/runner"
sed -i \
  -e "s|CONF_FILE=\"/etc/tcpquality-auto.conf\"|CONF_FILE=\"${test_dir}/conf\"|" \
  -e "s|LOG_DIR=\"/var/log/tcpquality-auto\"|LOG_DIR=\"${test_dir}/logs\"|" \
  -e "s|LOCK_FILE=\"/run/tcpquality-auto.lock\"|LOCK_FILE=\"${test_dir}/lock\"|" \
  "${test_dir}/runner"
bash -n "${test_dir}/runner"

cat > "${test_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
output=""
url=""
args=("$@")
while (( $# )); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  https://entry.test)
    cp "${TEST_DIR}/entry" "$output"
    ;;
  https://report.test/generate)
    if [[ -f "${TEST_DIR}/upload-ok" ]]; then
      printf '%s\n' '{"url":"https://tcpquality.ibsgss.uk/r/regression123"}' > "$output"
      printf '200'
    else
      printf '%s\n' '{"error":"temporary outage"}' > "$output"
      printf '503'
    fi
    ;;
  https://api.telegram.org/*/sendMessage)
    printf '%s\n' "${args[*]}" >> "${TEST_DIR}/telegram"
    ;;
  *) printf 'Unexpected curl URL: %s\n' "$url" >&2; exit 1 ;;
esac
EOF
chmod +x "${test_dir}/bin/curl"

cat > "${test_dir}/conf" <<'EOF'
SERVER_NAME=regression-vps
SCHEDULE_TZ=Asia/Shanghai
TG_BOT_TOKEN=dummy
TG_CHAT_ID=123
SEND_FULL_LOG=N
RUN_PROFILE=FULL
TEST_TIMEOUT=120m
EOF

cat > "${test_dir}/entry" <<'EOF'
#!/usr/bin/env bash
printf '网络,IP版本\n三网,IPv4\n' > "${TCPQUALITY_OUTPUT_DIR}/zstatic_nping_test.csv"
echo '报告时间：2026-09-29 20:30:00 CST'
echo '正在下载 https://example.test/rootfs.tar.zst'
echo 'SVG 报告上传失败，本地 CSV 已保留'
EOF

export TEST_DIR="${test_dir}" PATH="${test_dir}/bin:${PATH}"
export TCPQUALITY_URL=https://entry.test TCPQUALITY_REPORT_API=https://report.test/generate
export TCPQUALITY_REPORT_RECOVERY_ATTEMPTS=1

bash "${test_dir}/runner"
pending=("${test_dir}"/logs/*.artifacts/pending-upload)
test -f "${pending[0]}"
grep -q 'CSV 已保留' "${test_dir}/telegram"
if grep -q '在线结果：.*rootfs' "${test_dir}/telegram"; then
  echo 'rootfs URL was reported as a result' >&2
  exit 1
fi

first_log="${pending[0]%/pending-upload}"
first_log="${first_log%.artifacts}.log"
if bash "${test_dir}/runner" retry; then
  echo 'failed retry unexpectedly succeeded' >&2
  exit 1
fi
test -f "${pending[0]}"
test -f "${first_log}"
grep -q 'SVG 报告上传失败' "${first_log}"

touch "${test_dir}/upload-ok"
bash "${test_dir}/runner" retry
test ! -e "${pending[0]}"
grep -q '历史报告补传成功' "${test_dir}/telegram"
grep -q 'https://tcpquality.ibsgss.uk/r/regression123' "${test_dir}/telegram"

legacy_dir="${test_dir}/logs/20260920-203000.artifacts"
mkdir -p "${legacy_dir}"
printf '网络,IP版本\n三网,IPv4\n' > "${legacy_dir}/zstatic_nping_old.csv"
printf '报告时间：2026-09-20 20:30:00 CST\nSVG 报告上传失败\n' \
  > "${test_dir}/logs/20260920-203000.log"
bash "${test_dir}/runner" retry
test -f "${legacy_dir}/uploaded-url"

sleep 1
before_success="$(grep -c 'TcpQuality 测试完成' "${test_dir}/telegram" || true)"
bash "${test_dir}/runner"
after_success="$(grep -c 'TcpQuality 测试完成' "${test_dir}/telegram" || true)"
test "$after_success" -gt "$before_success"

sleep 1
cat > "${test_dir}/entry" <<'EOF'
#!/usr/bin/env bash
echo 'SVG 报告上传失败，本地 CSV 未生成'
EOF
bash "${test_dir}/runner"
grep -q '没有可用于恢复上传的本次 CSV' "${test_dir}/telegram"
grep -q '未找到本次测试持久化 CSV' "$(ls -t "${test_dir}"/logs/*.log | head -n 1)"

sleep 1
cat > "${test_dir}/entry" <<'EOF'
#!/usr/bin/env bash
echo '测速开始'
sleep 3
EOF
sed -i 's/TEST_TIMEOUT=120m/TEST_TIMEOUT=1s/' "${test_dir}/conf"
if bash "${test_dir}/runner"; then
  echo 'timeout run unexpectedly succeeded' >&2
  exit 1
fi
grep -q '测试超时或被超时控制器终止（1s）' "${test_dir}/telegram"

echo 'runner regression checks passed'
