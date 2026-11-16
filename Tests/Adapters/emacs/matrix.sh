#!/usr/bin/env bash
# The Emacs adapter checks on each supported major version, in containers (silex/emacs *-ci images).
# Per version: byte-compile with warnings as errors, checkdoc (reported, not fatal), then the ERT suite against the stub command.
# The checkout is mounted read-only and copied inside, so nothing is written back. Local only.
#   EMACS_VERSIONS  space-separated image tags (default: newest point release of 29, 30, 31)
#   EMACS_IMAGE     image repository (default: silex/emacs)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
image=${EMACS_IMAGE:-silex/emacs}
versions=${EMACS_VERSIONS:-"29.4 30.2 31.1"}

inner='set -u
cp -R /src /work && cd /work
emacs --version | head -1
emacs --batch -Q --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile prinbox.el || exit 10
rm -f prinbox.elc
out=$(emacs --batch -Q --eval "(checkdoc-file \"prinbox.el\")" 2>&1 | grep "prinbox.el:")
[ -z "$out" ] || printf "checkdoc (warning only; upstream does not run it):\n%s\n" "$out"
emacs --batch -Q -L . -l ert -l Tests/Adapters/emacs/prinbox-test.el -f ert-run-tests-batch-and-exit 2>&1 \
  | grep -E "^Ran |unexpected|FAILED" ; exit "${PIPESTATUS[0]}"'

failed=()
for v in $versions; do
    echo "== emacs $v"
    if docker run --rm --platform linux/amd64 -v "$root:/src:ro" "$image:$v-ci" bash -c "$inner"; then
        echo "emacs $v: ok"
    else
        echo "emacs $v: FAILED"
        failed+=("$v")
    fi
done
[ ${#failed[@]} -eq 0 ] || { echo "failed: ${failed[*]}"; exit 1; }
echo "all versions ok: $versions"
