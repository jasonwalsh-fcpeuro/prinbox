#!/usr/bin/env bash
# The picker inside the tmux popup: the inbox's rows through fzf. Enter opens the row's URL (a more line opens its
# section page), alt-s and alt-u snooze and wake through the command and reload (ctrl-s and ctrl-u too), alt-r refetches
# (ctrl-r too), alt-y copies the row's URL, alt-? shows the keys. Environment: PRINBOX_CMD (prinbox), PRINBOX_MAX_AGE
# (60), PRINBOX_ALL (off; on adds --all), PRINBOX_FZF (fzf), PRINBOX_OPENER (open on Darwin, else xdg-open),
# PRINBOX_COPIER (pbcopy on Darwin, else wl-copy or xclip).
# No `set -e`: a failed step must say why, not vanish with the popup.
set -uo pipefail
cmd=${PRINBOX_CMD:-prinbox}
max_age=${PRINBOX_MAX_AGE:-60}
all_flag=
[ "${PRINBOX_ALL:-off}" = on ] && all_flag=--all
fzf=${PRINBOX_FZF:-fzf}
opener=${PRINBOX_OPENER:-}
if [ -z "$opener" ]; then
    if [ "$(uname)" = Darwin ]; then opener=open; else opener=xdg-open; fi
fi
copier=${PRINBOX_COPIER:-}
if [ -z "$copier" ]; then
    if [ "$(uname)" = Darwin ]; then copier=pbcopy
    elif command -v wl-copy >/dev/null 2>&1; then copier=wl-copy
    else copier='xclip -selection clipboard'; fi
fi

pause() {
    printf '%s\n\nPress Enter to close.' "$1"
    read -r _ || true
}

command -v "$fzf" >/dev/null 2>&1 || { pause "prinbox: fzf is not installed (brew install fzf)"; exit 1; }
command -v "$cmd" >/dev/null 2>&1 || { pause "prinbox not found: brew install creeonix/tap/prinbox-cli"; exit 1; }

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
rows=$("$cmd" inbox --max-age "$max_age" --format lines $all_flag 2>"$errors")
code=$?
case "$code" in
    0|1) ;;
    *) pause "$(cat "$errors")"; exit "$code" ;;
esac
count=$("$cmd" inbox --cached --format tmux 2>/dev/null)
header="${count:-0} waiting on you · enter open  alt-s snooze  alt-u unsnooze  alt-r fetch  alt-y copy  alt-? keys"
if [ "$code" -eq 1 ]; then
    header="! $(head -n1 "$errors" | sed 's/^prinbox: //') · $header"
fi
reload="$cmd inbox --cached --format lines $all_flag"
fetch="$cmd inbox --format lines $all_flag"
# fzf owns the letters (the query), so motion stays on ctrl- and prinbox's actions sit on alt-; the original ctrl-
# action keys stay as aliases.
keys="enter open · alt-s snooze · alt-u unsnooze · alt-r fetch · alt-y copy link · esc close
ctrl-n/ctrl-j down · ctrl-p/ctrl-k up · type to filter · ctrl-s/ctrl-u/ctrl-r still work"
selection=$(printf '%s\n' "$rows" | "$fzf" --delimiter '\t' --with-nth 3,4,5,6,7 --no-sort --layout reverse --header "$header" \
    --preview "printf '%s\n' \"$keys\"" --preview-window 'down,3,hidden' \
    --bind "ctrl-s:execute-silent($cmd snooze {1})+reload($reload)" \
    --bind "ctrl-u:execute-silent($cmd unsnooze {1})+reload($reload)" \
    --bind "ctrl-r:reload($fetch)" \
    --bind "alt-s:execute-silent($cmd snooze {1})+reload($reload)" \
    --bind "alt-u:execute-silent($cmd unsnooze {1})+reload($reload)" \
    --bind "alt-r:reload($fetch)" \
    --bind "alt-y:execute-silent(printf %s {9} | $copier)" \
    --bind "alt-?:toggle-preview")
[ -n "$selection" ] || exit 0
url=$(printf '%s\n' "$selection" | cut -f9)
[ -n "$url" ] && "$opener" "$url"
exit 0
