# shellcheck shell=bash
# lab-history.sh (cài vào /etc/profile.d/): lưu lịch sử lệnh ngay sau mỗi lệnh, kèm thời gian.
export HISTTIMEFORMAT='%F %T '
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend
PROMPT_COMMAND='history -a'"${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
