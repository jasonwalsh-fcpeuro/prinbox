#!/usr/bin/env bash
# Builds every theme and checks that the stub serves it. make-theme.sh fails when a golden name survives.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
stub="$here/../bin/prinbox"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for theme in "$here"/themes/*.json; do
    out="$work/$(basename "$theme" .json)"
    "$here/make-theme.sh" "$theme" "$out" >/dev/null
    diff <(PRINBOX_STUB_GOLDEN=$out "$stub" inbox) "$out/demo-inbox.json"
    diff <(PRINBOX_STUB_GOLDEN=$out "$stub" inbox --all --format lines) "$out/demo-inbox-all.lines"
    [ "$(jq -r .viewer "$out/demo-inbox.json")" = "$(jq -r .persona.viewer "$theme")" ]
    # Same shape as the golden demo: sections, row counts and reasons.
    shape='[.sections[] | {kind, n: (.rows | length), reasons: [.rows[].reason]}]'
    diff <(jq -c "$shape" "$here/../../PrinboxCoreTests/Golden/demo-inbox.json") <(jq -c "$shape" "$out/demo-inbox.json")
done
echo "themes: $(ls "$here"/themes | sed 's/\.json$//' | tr '\n' ' ')"
