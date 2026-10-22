#!/bin/bash
# Recompute the *_SHA256 ARGs in the Containerfile for the versions currently pinned there.
# Run after Renovate (or you) bumps DXVK_VERSION, S2V_VERSION or RESCOMP_VERSION.
set -euo pipefail
cf=$(dirname "$0")/Containerfile
arg() { sed -nE "s/^ARG $1=(.*)/\1/p" "$cf"; }

declare -A url=(
	[DXVK]="https://github.com/doitsujin/dxvk/releases/download/v$(arg DXVK_VERSION)/dxvk-$(arg DXVK_VERSION).tar.gz"
	[S2V]="https://github.com/ValveResourceFormat/ValveResourceFormat/releases/download/$(arg S2V_VERSION)/cli-linux-x64.zip"
	[RESCOMP]="https://github.com/Dota-Modding-Community/workshoptools/releases/download/$(arg RESCOMP_VERSION)/resourcecompiler.zip"
)
for k in "${!url[@]}"; do
	sum=$(curl -fsSL "${url[$k]}" | sha256sum | cut -d' ' -f1)
	old=$(arg "${k}_SHA256")
	sed -i "s/^ARG ${k}_SHA256=.*/ARG ${k}_SHA256=$sum/" "$cf"
	[ "$old" = "$sum" ] && echo "$k: unchanged" || echo "$k: $old -> $sum"
done
