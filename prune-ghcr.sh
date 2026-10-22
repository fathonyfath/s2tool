#!/bin/bash
# SPDX-License-Identifier: 0BSD
# Delete old s2tool image versions from GHCR.
# Keeps `latest` and the newest N tagged versions. Deletes everything else, including untagged versions
# (old builds whose tags moved to a newer image). Only lists what it would delete unless --yes is given.
#
#   ./prune-ghcr.sh [--keep 5] [--yes]
#
# Needs gh, logged in as the package owner with the delete:packages scope
# (gh auth refresh -s read:packages,delete:packages). PACKAGE overrides the package name (default s2tool).
set -euo pipefail
keep=5
yes=0
pkg=${PACKAGE:-s2tool}
while [ $# -gt 0 ]; do
	case $1 in
		--keep) keep=$2; shift 2 ;;
		--yes) yes=1; shift ;;
		*) sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
	esac
done
[[ $keep =~ ^[0-9]+$ ]] || { echo "--keep needs a number" >&2; exit 2; }

plan=$(gh api --paginate "/user/packages/container/$pkg/versions" \
		--jq '.[] | {id, created_at, digest: .name, tags: .metadata.container.tags}' |
	jq -s --argjson keep "$keep" '
		sort_by(.created_at) | reverse
		| ([.[] | select(.tags | length > 0)][:$keep] | map(.id)) as $newest
		| map(. + {keep: ((.id | IN($newest[])) or ((.tags | index("latest")) != null))})')

jq -r '.[] | [(if .keep then "keep  " else "delete" end), .created_at, .digest[7:19],
	(if (.tags | length) > 0 then (.tags | join(",")) else "(untagged)" end)] | @tsv' <<<"$plan" | column -t -s $'\t'

ids=$(jq -r '.[] | select(.keep | not) | .id' <<<"$plan")
n=$(grep -c . <<<"$ids" || true)
if [ "$n" -eq 0 ]; then
	echo "nothing to delete"
	exit 0
fi
if [ "$yes" -ne 1 ]; then
	echo "would delete $n version(s); run with --yes to delete"
	exit 0
fi
for id in $ids; do
	gh api -X DELETE "/user/packages/container/$pkg/versions/$id" >/dev/null
done
echo "deleted $n version(s)"
