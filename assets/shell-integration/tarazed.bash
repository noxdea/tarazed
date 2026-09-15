# Tarazed shell integration for bash 3.2 and newer.
if [[ -z ${TARAZED_SHELL_INTEGRATION-} ]]; then
TARAZED_SHELL_INTEGRATION=1

__tarazed_urlencode() {
  local LC_ALL=C value=$1 output= character code hex index=0
  while (( index < ${#value} )); do
    character=${value:index:1}
    case $character in
      [a-zA-Z0-9.~_/-]) output=$output$character ;;
      *)
        printf -v code '%d' "'$character"
        printf -v hex '%%%02X' "$((code & 255))"
        output=$output$hex
        ;;
    esac
    (( index += 1 ))
  done
  printf '%s' "$output"
}

__tarazed_prompt_command() {
  local command_status=$1
  printf '\e]133;D;%s\a\e]7;file://%s%s\e\\\e]133;A\e\\' \
    "$command_status" "${HOSTNAME-}" "$(__tarazed_urlencode "$PWD")"
  __tarazed_command_active=0
}

PROMPT_COMMAND="__tarazed_prompt_status=\$?${PROMPT_COMMAND:+;$PROMPT_COMMAND};__tarazed_prompt_command \"\$__tarazed_prompt_status\""
PS1="${PS1-}\[\e]133;B\a\]"

if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  PS0="${PS0-}\[\e]133;C\a\]"
else
  __tarazed_command_active=1
  __tarazed_preexec() {
    if (( ! __tarazed_command_active )); then
      __tarazed_command_active=1
      printf '\e]133;C\e\\'
    fi
  }
  trap '__tarazed_preexec' DEBUG
fi
fi
