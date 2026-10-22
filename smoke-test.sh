#!/bin/bash
# SPDX-License-Identifier: 0BSD
# End-to-end check of a built image: a valid CSS file compiles (exit 0), a broken one fails (exit 1).
#   ./smoke-test.sh                                  podman, image "s2tool"
#   ENGINE=docker IMAGE=s2tool:test ./smoke-test.sh
set -euo pipefail
engine=${ENGINE:-podman}
image=${IMAGE:-s2tool}

tmp=$(mktemp -d)
# With rootful docker the outputs are owned by root, so cleanup may fail; that's fine.
trap 'rm -rf "$tmp" 2>/dev/null || true' EXIT
fail() { echo "smoke test FAILED: $*" >&2; exit 1; }
compile() { "$engine" run --rm --network=none --security-opt label=disable \
	-v "$tmp/$1/in:/in:ro" -v "$tmp/$1/out:/out" "$image" compile; }

mkdir -p "$tmp"/{ok,bad}/in/panorama/styles "$tmp"/{ok,bad}/out
printf '.smoke\n{\n\twidth: 10px;\n}\n' >"$tmp/ok/in/panorama/styles/smoke.css"
printf '.smoke\n{\n}\n}\n' >"$tmp/bad/in/panorama/styles/smoke.css"

"$engine" run --rm "$image" version

compile ok || fail "valid CSS did not compile"
[ -s "$tmp/ok/out/panorama/styles/smoke.vcss_c" ] || fail "no smoke.vcss_c in output"

rc=0
compile bad || rc=$?
[ "$rc" -eq 1 ] || fail "broken CSS: expected exit 1, got $rc"

echo "smoke test ok"
