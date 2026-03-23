# ev.zsh — open files in a running Emacs from vterm
#
# Source this from .zshrc:
#   source /path/to/emacs/goodies/ev.zsh
#
# Usage:
#   ev [file]         open file (or cwd) in Emacs — non-blocking
#   ev -nw [file]     open file and block until C-c C-c — use as $EDITOR
#
# The -nw blocking mode requires ev-open-file to be registered in
# vterm-eval-cmds; see terminal-config.el in the parent directory.

ev() {
    local blocking=false
    if [[ "$1" == "-nw" ]]; then
        blocking=true
        shift
    fi

    local file
    file="$(realpath "${1:-.}")"

    if $blocking; then
        local semaphore
        semaphore="$(mktemp)"
        rm -f "$semaphore"
        vterm_cmd ev-open-file "$file" "$semaphore"
        until [ -f "$semaphore" ]; do
            sleep 0.1
        done
        rm -f "$semaphore"
    else
        vterm_cmd find-file "$file"
    fi
}

