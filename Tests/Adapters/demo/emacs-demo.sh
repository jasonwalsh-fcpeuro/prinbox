#!/usr/bin/env bash
# Opens prinbox.el in a clean Emacs on a themed mock inbox, for screenshots and UX review. Never runs gh:
# the stub serves the theme. Nothing from your own config, account or organizations is loaded.
# Usage: emacs-demo.sh [THEME] [emacs args...]   THEME: a name in themes/ (default foundations); add -nw for a terminal
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
name=${1:-foundations}; [ $# -gt 0 ] && shift
theme="$here/themes/$name.json"
[ -f "$theme" ] || { echo "emacs-demo: no theme $name (have: $(ls "$here/themes" | sed 's/\.json$//' | tr '\n' ' '))" >&2; exit 2; }
out=$(mktemp -d "${TMPDIR:-/tmp}/prinbox-demo-$name.XXXX")
"$here/make-theme.sh" "$theme" "$out" >/dev/null
owner=$(jq -r '.owners | to_entries[0].value' "$theme")
export PRINBOX_STUB_GOLDEN="$out" PRINBOX_STUB_LOG="$out/stub.log"
exec emacs -Q "$@" -L "$root" \
    --eval "(progn
      (require 'prinbox)
      (setq prinbox-command \"$root/Tests/Adapters/bin/prinbox\"
            prinbox-section-column nil
            prinbox-icons 'unicode
            prinbox-review-order 'quick
            prinbox-review-drafts 'last
            prinbox-default-owners '(\"$owner\"))
      (prinbox)
      (delete-other-windows))"
