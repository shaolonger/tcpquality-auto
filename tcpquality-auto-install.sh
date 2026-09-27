#!/usr/bin/env bash
set -Eeuo pipefail

# TcpQuality Auto hotfix installer
# Version: 2026.09.26.1
#
# Replace tcpquality-auto-install.sh in shaolonger/tcpquality-auto with this file.
# It pins the previous known-good installer, applies the report-upload recovery
# patch deterministically, validates the patched result, then executes it.

BASE_COMMIT="9cfa6fcde0a134e2233ce90d4a479c92d251fe19"
BASE_URL="https://raw.githubusercontent.com/shaolonger/tcpquality-auto/${BASE_COMMIT}/tcpquality-auto-install.sh"
PATCH_VERSION="2026.09.26.1"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tcpquality-auto-hotfix.XXXXXX")"
base_script="${tmp_dir}/base.sh"
patched_script="${tmp_dir}/tcpquality-auto-install.sh"

cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

need_cmd curl
need_cmd python3
need_cmd bash

printf '[INFO] 下载 TcpQuality Auto 基础版本 %s...\n' "${BASE_COMMIT:0:12}"
curl -fsSL \
  --retry 4 \
  --retry-all-errors \
  --retry-delay 2 \
  --connect-timeout 15 \
  --max-time 120 \
  "${BASE_URL}" -o "${base_script}" \
  || die "无法下载基础安装脚本：${BASE_URL}"

[[ -s "${base_script}" ]] || die "基础安装脚本为空。"

python3 - "${base_script}" "${patched_script}" "${PATCH_VERSION}" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
version = sys.argv[3]
c = src.read_text(encoding="utf-8")

def replace_once(old: str, new: str, label: str):
    global c
    n = c.count(old)
    if n != 1:
        raise SystemExit(f"[FAIL] 补丁锚点异常：{label}，预期 1 处，实际 {n} 处")
    c = c.replace(old, new, 1)

replace_once(
    'APP_VERSION="2026.09.20.1"',
    f'APP_VERSION="{version}"',
    "APP_VERSION",
)

replace_once(
    'TCPQUALITY_FALLBACK_URL="${TCPQUALITY_FALLBACK_URL:-https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh}"',
    '''TCPQUALITY_FALLBACK_URL="${TCPQUALITY_FALLBACK_URL:-https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh}"
REPORT_API="${TCPQUALITY_REPORT_API:-https://tcpquality.ibsgss.uk/generate}"
REPORT_RECOVERY_ATTEMPTS="${TCPQUALITY_REPORT_RECOVERY_ATTEMPTS:-4}"
REPORT_RECOVERY_CONNECT_TIMEOUT="${TCPQUALITY_REPORT_RECOVERY_CONNECT_TIMEOUT:-15}"
REPORT_RECOVERY_MAX_TIME="${TCPQUALITY_REPORT_RECOVERY_MAX_TIME:-90}"''',
    "runner constants",
)

replace_once(
    '''clean_log="${LOG_DIR}/${stamp}.log"
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}"''',
    '''clean_log="${LOG_DIR}/${stamp}.log"
artifact_dir="${LOG_DIR}/${stamp}.artifacts"
mkdir -p "${artifact_dir}"
chmod 700 "${artifact_dir}"
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}"''',
    "artifact directory",
)

fetch_entry_block = r'''fetch_entry() {
  local url="$1"
  : > "${entry_script}"
  echo "[tcpquality-auto] 下载 TcpQuality 入口：${url}" >> "${raw_log}"

  if ! curl -fsSL \
    --retry 3 \
    --retry-all-errors \
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
'''

recovery_extra = r'''
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
  local response_file curl_err http_code recovered_url report_time
  local family attempt sleep_s curl_rc
  local -a retry_extra=()
  local -a report_headers=()

  RECOVERED_REPORT_URL=""
  [[ -s "${csv}" ]] || {
    echo "[tcpquality-auto] 报告恢复上传跳过：未找到本次测试 CSV。" >> "${raw_log}"
    return 1
  }

  report_time="$(extract_report_time)"
  if [[ -n "${report_time}" ]]; then
    report_headers+=(-H "X-Report-Time: ${report_time}")
  fi

  if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
    retry_extra+=(--retry-all-errors)
  fi

  response_file="$(mktemp "${TMPDIR:-/tmp}/tcpquality-auto-report-response.XXXXXX")"
  curl_err="$(mktemp "${TMPDIR:-/tmp}/tcpquality-auto-report-curl.XXXXXX")"

  # First preserve upstream behavior (IPv4). If that path is the problem,
  # retry with the system-selected address family, which can use IPv6.
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
        "${retry_extra[@]}"
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
        RECOVERED_REPORT_URL="${recovered_url}"
        echo "[tcpquality-auto] 恢复上传成功：HTTP ${http_code}，${RECOVERED_REPORT_URL}" >> "${raw_log}"
        rm -f "${response_file}" "${curl_err}"
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

  rm -f "${response_file}" "${curl_err}"
  return 1
}
'''
replace_once(fetch_entry_block, fetch_entry_block + recovery_extra, "report recovery functions")

replace_once(
    '  TERM=xterm timeout --signal=TERM --kill-after=30s 55m \\\n    bash "${entry_script}" --all \\\n    >>"${raw_log}" 2>&1',
    '  TERM=xterm TCPQUALITY_OUTPUT_DIR="${artifact_dir}" \\\n    timeout --signal=TERM --kill-after=30s 55m \\\n    bash "${entry_script}" --all \\\n    >>"${raw_log}" 2>&1',
    "TCPQUALITY_OUTPUT_DIR",
)

report_anchor = r'''report_url="$(
  grep -Eo 'https?://tcpquality\.ibsgss\.uk/r/[A-Za-z0-9_-]+' "${clean_log}" 2>/dev/null \
    | tail -n 1 \
    || true
)"

report_upload_failed=0
'''

report_hook = r'''report_url="$(
  grep -Eo 'https?://tcpquality\.ibsgss\.uk/r/[A-Za-z0-9_-]+' "${clean_log}" 2>/dev/null \
    | tail -n 1 \
    || true
)"

report_recovered=0
report_recovery_attempted=0
current_csv=""

if [[ -z "${report_url}" && "${exit_code}" -eq 0 ]]; then
  current_csv="$(find_current_csv)"
  if [[ -n "${current_csv}" ]]; then
    report_recovery_attempted=1
    echo "[tcpquality-auto] 上游未返回有效 /r/ 链接，开始使用本次 CSV 在宿主机恢复上传。" >> "${raw_log}"

    if recover_report_upload "${current_csv}"; then
      report_url="${RECOVERED_REPORT_URL}"
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

report_upload_failed=0
'''
replace_once(report_anchor, report_hook, "report recovery hook")

replace_once(
    '''  if [[ "${rootfs_fallback}" -eq 1 ]]; then
    notes+=("rootfs 下载过程中发生过自动回退，但最终测试成功")
  fi''',
    '''  if [[ "${rootfs_fallback}" -eq 1 ]]; then
    notes+=("rootfs 下载过程中发生过自动回退，但最终测试成功")
  fi
  if [[ "${report_recovered}" -eq 1 ]]; then
    notes+=("上游首次报告上传失败，已使用本次 CSV 自动恢复上传")
  fi''',
    "success recovery note",
)

replace_once(
    '''  if [[ "${report_upload_failed}" -eq 1 ]]; then
    reason="测试主体已执行结束，但在线报告上传失败"
  else
    reason="测试进程正常结束，但未检测到有效的 /r/ 在线报告链接"
  fi''',
    '''  if [[ "${report_upload_failed}" -eq 1 && "${report_recovery_attempted}" -eq 1 ]]; then
    reason="测试主体已执行结束；上游首次上传失败，宿主机恢复上传也未成功"
  elif [[ "${report_upload_failed}" -eq 1 ]]; then
    reason="测试主体已执行结束，但在线报告上传失败，且没有可用于恢复上传的本次 CSV"
  elif [[ "${report_recovery_attempted}" -eq 1 ]]; then
    reason="测试进程正常结束，但在线报告恢复上传未成功"
  else
    reason="测试进程正常结束，但未检测到有效的 /r/ 在线报告链接"
  fi''',
    "partial failure reason",
)

replace_once(
    '''# 保留最近 14 天运行日志。
find "${LOG_DIR}" -type f -mtime +14 -delete 2>/dev/null || true''',
    '''# 保留最近 14 天运行日志与本次测试产物。
find "${LOG_DIR}" -type f -mtime +14 -delete 2>/dev/null || true
find "${LOG_DIR}" -mindepth 1 -maxdepth 1 -type d -name '*.artifacts' -mtime +14 -exec rm -rf {} + 2>/dev/null || true''',
    "artifact cleanup",
)

dst.write_text(c, encoding="utf-8")
PY

chmod 0755 "${patched_script}"
bash -n "${patched_script}" || die "补丁后的脚本未通过 bash -n 语法检查。"

printf '[ OK ] TcpQuality Auto %s 补丁生成完成，开始执行。\n' "${PATCH_VERSION}"
exec bash "${patched_script}" "$@"
