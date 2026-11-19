#!/usr/bin/env bash
# lib/common.sh - hàm dùng chung của TV1: log, báo lỗi, trap, dry-run, kiểm tra điều kiện.
# File này được `source`, không chạy trực tiếp.
# shellcheck shell=bash

LOG_TAG="${LOG_TAG:-lab}"
DRY_RUN="${DRY_RUN:-0}"

# Ghi log ra stderr kèm thời gian và nhãn script.
log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$LOG_TAG" "$*" >&2; }

# Báo lỗi rõ ràng rồi thoát (không để script im lặng bỏ qua lỗi).
die() { log "LỖI: $*"; exit 1; }

_on_err()  { log "LỖI: lệnh thất bại (exit $2) ở dòng $1"; }
_on_exit() { local code=$?; [[ $code -eq 0 ]] || log "Kết thúc với mã lỗi $code"; }

# Gọi sau `set -Eeuo pipefail`: bắt lỗi (ERR) và ghi trạng thái khi thoát (EXIT).
setup_traps() {
  trap '_on_err "$LINENO" "$?"' ERR
  trap _on_exit EXIT
}

# Chạy lệnh; nếu DRY_RUN=1 thì chỉ in ra, không thực thi.
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: $*"
    return 0
  fi
  log "chạy: $*"
  "$@"
}

require_root() { [[ $EUID -eq 0 ]] || die "cần chạy bằng root (dùng sudo)"; }
require_cmd()  { command -v "$1" >/dev/null 2>&1 || die "thiếu lệnh: $1"; }
