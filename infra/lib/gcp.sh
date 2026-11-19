#!/usr/bin/env bash
# lib/gcp.sh - hàm dùng chung cho các script trong gcp/. Được `source`.
# Cần source lib/common.sh trước.
# shellcheck shell=bash

# Trả về 0 nếu lệnh gcloud thành công (dùng để kiểm tra tài nguyên đã tồn tại).
gcloud_exists() { gcloud "$@" >/dev/null 2>&1; }

# Nạp env.sh (biến PROJECT, ZONE...) và kiểm tra điều kiện trước khi chạy.
load_gcp_env() {
  local dir="$1" env_file="${ENV_FILE:-$1/env.sh}"
  require_cmd gcloud
  [[ -f "$env_file" ]] || die "chưa có $env_file. Chạy: cp $dir/env.sh.example $env_file rồi sửa PROJECT"
  # shellcheck source=/dev/null
  source "$env_file"
  [[ -n "${PROJECT:-}" && "$PROJECT" != "<project-id>" ]] || die "PROJECT chưa được đặt trong $env_file"
  gcloud config set project "$PROJECT" >/dev/null 2>&1 || log "không đặt được project (kiểm tra gcloud auth)"
}
