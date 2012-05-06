
set_colors()
{
    ts="$(date "+%Y-%m-%d %H:%M:%S")"
    [[ -t 1 ]] \
    && {
        RED="\033[38;5;196m"
        GREEN="\033[38;5;46m"
        NORMAL="\033[39m"
        BLUE="\033[38;5;33m"
        YELLOW="\033[38;5;226m"
    }
}

log::OK()
{
    local RED GREEN NORMAL BLUE YELLOW ts header
    set_colors
    header="$BLUE[$ts]::INFO::$GREEN";
    log "$@"
}

log::WARN()
{
    local RED GREEN NORMAL BLUE YELLOW ts header
    set_colors
    header="$YELLOW[$ts]::WARNING::";
    log "$@"
}

log::ERROR()
{
    local RED GREEN NORMAL BLUE YELLOW ts header
    set_colors
    header="$RED[$ts]::ERROR::";
    log "$@"
}

log::INFO()
{
    local RED GREEN NORMAL BLUE YELLOW ts header
    set_colors
    header="$BLUE[$ts]::INFO::";
    log "$@"
}

log()
{
    [[ $header == "" ]] \
    && {
        log::INFO "$@"
        return
    }
    echo -e "$header$@$NORMAL"
}


