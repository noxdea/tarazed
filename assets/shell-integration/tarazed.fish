# Tarazed shell integration for fish.
if not set -q TARAZED_SHELL_INTEGRATION
set -g TARAZED_SHELL_INTEGRATION 1

function __tarazed_cwd
    set -l encoded (string escape --style=url -- $PWD)
    set encoded (string replace -r '^%2[Ff]' '' -- $encoded)
    printf '\e]7;file:///%s\e\\' $encoded
end

function __tarazed_preexec --on-event fish_preexec
    printf '\e]133;C\e\\'
end

function __tarazed_postexec --on-event fish_postexec
    set -l command_status $status
    printf '\e]133;D;%s\a' $command_status
end

functions -c fish_prompt __tarazed_original_fish_prompt
function fish_prompt
    __tarazed_cwd
    printf '\e]133;A\e\\'
    __tarazed_original_fish_prompt
    printf '\e]133;B\e\\'
end
end
