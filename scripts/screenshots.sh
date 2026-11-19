#!/usr/bin/env bash
# Builds the terminal screenshots in docs/images from the themed mock inbox, so they can be regenerated after any
# UI change. Everything runs in a private tmux server (its own socket, no tmux.conf) at a fixed size; the stub
# serves the inbox, so gh, your account and your organizations are never touched.
#   docs/images/emacs-config.png  prinbox.el configured (top) and the *prinbox* buffer it opens (bottom), emacs -nw
#   docs/images/emacs-inbox.png   the *prinbox* buffer alone, reason badges on
#   docs/images/tmux.png          the tmux picker over the same inbox, with the count in the status line
# Needs: tmux, a terminal emacs (29.1+), fzf, jq, uv, rsvg-convert. Usage: scripts/screenshots.sh [THEME]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
theme=${1:-foundations}
demo="$root/Tests/Adapters/demo"
stub="$root/Tests/Adapters/bin/prinbox"
images="$root/docs/images"
cols=120 rows=32
for tool in tmux emacs fzf jq uv rsvg-convert; do
    command -v "$tool" >/dev/null || { echo "screenshots: $tool not found" >&2; exit 1; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/prinbox-shots.XXXX")
sock="prinbox-shots-$$"
cleanup() { tmux -L "$sock" kill-server 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

# The same themed documents emacs-demo.sh serves.
"$demo/make-theme.sh" "$demo/themes/$theme.json" "$work/inbox" >/dev/null
owner=$(jq -r '.owners | to_entries[0].value' "$demo/themes/$theme.json")
export PRINBOX_STUB_GOLDEN="$work/inbox" PRINBOX_STUB_LOG="$work/stub.log"

printf 'set -g default-terminal xterm-256color\nset -g status off\n' >"$work/tmux.conf"
start() { tmux -L "$sock" -f "$work/tmux.conf" new-session -d -s shot -x "$cols" -y "$rows" "$@"; }
capture() { tmux -L "$sock" capture-pane -e -p -t shot >"$work/$1.ansi"; tmux -L "$sock" kill-server; }
render() {  # render NAME TITLE [STATUS_LEFT STATUS_RIGHT]
    local name=$1 title=$2; shift 2
    uv run --quiet "$root/scripts/ansi-to-image.py" "$work/$name.ansi" "$work/$name.svg" "$title" "$cols" "$@"
    rsvg-convert -z 2 -o "$images/$name.png" "$work/$name.svg"
    echo "wrote docs/images/$name.png"
}

# The configuration a reader would put in init.el, shown above the buffer it produces.
cat >"$work/init-prinbox.el" <<EOF
;;; init.el: prinbox (the settings this screenshot uses)
(use-package prinbox
  :vc (:url "https://github.com/creeonix/prinbox" :rev :newest)
  :commands (prinbox prinbox-mode-line-mode)
  :custom
  (prinbox-section-column nil)       ; a rule names each section instead
  (prinbox-icons 'unicode)           ; one-column symbols before each reason
  (prinbox-review-order 'quick)      ; small pull requests first
  (prinbox-review-drafts 'last)      ; drafts after the rest
  (prinbox-default-owners '("$owner")))
EOF

clean='(progn (menu-bar-mode -1) (setq inhibit-startup-screen t visible-bell nil ring-bell-function (quote ignore)))'

# 1. Configuration and result, side by side in one frame.
split="(run-with-timer 2 nil (lambda ()
  (let ((buf (find-file-noselect \"$work/init-prinbox.el\")))
    (delete-other-windows)
    (switch-to-buffer buf)
    (with-current-buffer buf (emacs-lisp-mode) (font-lock-ensure) (goto-char (point-min)))
    (select-window (split-window-below 13))
    (switch-to-buffer \"*prinbox*\")
    (goto-char (point-min))
    (message nil))))"
start "$demo/emacs-demo.sh" "$theme" -nw --eval "$clean" --eval "$split"
sleep 5; capture emacs-config; render emacs-config "init.el and M-x prinbox"

# 2. The buffer alone, with the reason badges.
start "$demo/emacs-demo.sh" "$theme" -nw --eval "$clean" \
    --eval "(run-with-timer 1 nil (lambda () (setq prinbox-reason-badges t) (with-current-buffer \"*prinbox*\" (revert-buffer)) (goto-char (point-min)) (message nil)))"
sleep 5; capture emacs-inbox; render emacs-inbox "M-x prinbox (reason badges on)"

# 3. tmux: the picker in a pane. The status line is drawn from the plugin's segment, which is exactly
#    `prinbox inbox --format tmux`, run here against the stub (a detached server never draws its own).
count=$("$stub" inbox --format tmux --max-age 60)
start env PRINBOX_CMD="$stub" PRINBOX_MAX_AGE=60 "$root/tmux/popup.sh"
sleep 3; capture tmux; render tmux "prefix + P: the prinbox picker" "[work] 0:prinbox*" "PR $count | 14:02 "
