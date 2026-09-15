# Tarazed shell integration for zsh.
if [[ -z ${TARAZED_SHELL_INTEGRATION-} ]]; then
typeset -g TARAZED_SHELL_INTEGRATION=1

__tarazed_urlencode() {
  local LC_ALL=C value=$1 output= character code hex
  integer index=1
  while (( index <= ${#value} )); do
    character=${value[index]}
    case $character in
      [a-zA-Z0-9.~_/-]) output+=$character ;;
      *)
        printf -v code '%d' "'$character"
        printf -v hex '%%%02X' "$((code & 255))"
        output+=$hex
        ;;
    esac
    (( index += 1 ))
  done
  print -rn -- "$output"
}

__tarazed_precmd() {
  local command_status=$?
  printf '\e]133;D;%s\a\e]7;file://%s%s\e\\\e]133;A\e\\' \
    "$command_status" "${HOST-}" "$(__tarazed_urlencode "$PWD")"
}

__tarazed_preexec() {
  printf '\e]133;C\e\\'
}

precmd_functions=(__tarazed_precmd ${precmd_functions:#__tarazed_precmd})
preexec_functions=(__tarazed_preexec ${preexec_functions:#__tarazed_preexec})
PS1="${PS1-}"$'%{\e]133;B\a%}'
fi
