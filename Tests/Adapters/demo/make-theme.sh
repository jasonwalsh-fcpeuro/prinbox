#!/usr/bin/env bash
# Builds a themed copy of the golden demo documents for screenshots and demos.
# Every name in the result comes from the theme file; the structure (sections, reasons, stacks, marks, ages)
# is the golden demo's, so the adapters render every state. Nothing real goes in a theme: invented people,
# orgs and repositories only.
# Usage: make-theme.sh THEME.json OUTDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
golden=$(cd "$here/../../PrinboxCoreTests/Golden" && pwd)
theme=$1 out=$2
mkdir -p "$out"

# JSON documents: rewrite repositories, logins, titles and URLs field by field.
filter='
  ($t.repositories) as $repos | ($t.logins) as $logins | ($t.titles) as $titles |
  def repo: . as $r | ($repos[$r] // $r);
  def login: . as $l | ($logins[$l] // $l);
  def url: reduce ($repos | to_entries[]) as $e (.; gsub("/" + $e.key + "/"; "/" + $e.value + "/"));
  walk(
    if type == "object" then
      (if has("repository") and (.repository | type) == "string" then .repository |= repo else . end)
      | (if has("author") and (.author | type) == "string" then .author |= login else . end)
      | (if has("viewer") and (.viewer | type) == "string" then .viewer |= login else . end)
      | (if has("number") and has("title") then .title = ($titles[(.number | tostring)] // .title) else . end)
      | with_entries(if (.value | type) == "string" and (.key | test("[Uu]rl$")) then .value |= url else . end)
    else . end)
  | if has("defaultRepositories") then .defaultRepositories |= map(repo) else . end'
for f in demo-inbox.json demo-inbox-all.json; do
    jq --argjson t "$(cat "$theme")" "$filter" "$golden/$f" >"$out/$f"
done

# Lines: id, kind, number, title, repository, reasonText, age, flags, url (a more:<kind> line per capped section).
for f in demo-inbox.lines demo-inbox-all.lines; do
    jq -r --argjson t "$(cat "$theme")" '
      ($t.repositories) as $repos | ($t.titles) as $titles |
      def url: reduce ($repos | to_entries[]) as $e (.; gsub("/" + $e.key + "/"; "/" + $e.value + "/"));
      split("\t") as $c |
      if ($c | length) >= 9 then
        [$c[0], $c[1], $c[2], ($titles[$c[2]] // $c[3]), ($repos[$c[4]] // $c[4]), $c[5], $c[6], $c[7], ($c[8] | url)]
        + $c[9:] | join("\t")
      else ($c | map(url) | join("\t")) end' -R "$golden/$f" >"$out/$f"
done

# Documents without rows (setup needed, no cache, fetch failed) are copied as they are.
for f in no-cache.json setup-needed.json fetch-failed.json; do
    [ -f "$golden/$f" ] && cp "$golden/$f" "$out/$f"
done

# No old name may survive: the theme must cover every repository and login in the golden demo.
if grep -qE '\b(acme|globex|initech|alice|bob|carol|dave|erin|frank|heidi)\b' "$out"/demo-inbox*.json "$out"/demo-inbox*.lines; then
    echo "make-theme: names left unthemed:" >&2
    grep -ohE '\b(acme|globex|initech|alice|bob|carol|dave|erin|frank|heidi)\b' "$out"/demo-inbox* | sort | uniq -c >&2
    exit 1
fi
echo "theme $(jq -r .name "$theme") -> $out"
