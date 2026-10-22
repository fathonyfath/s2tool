# s2tool

Source 2 toolchain in a container:

- `decompile`: [Source2Viewer](https://github.com/ValveResourceFormat/ValveResourceFormat), compiled `_c`
  files → css / xml / js / png
- `compile`: Valve's `resourcecompiler.exe` (Workshop Tools) under Wine, plain sources → `_c`

It needs no GPU, display or network. It only converts files; patching and packing VPKs are up to you.

> [!IMPORTANT]
> The image contains Valve's Workshop Tools (`resourcecompiler.exe`). They are Valve's property, and this
> project is not affiliated with or endorsed by Valve. See [Notice](#notice).

## Build

```sh
podman build -t s2tool .    # ~2 GB
```

## Usage

```sh
# Decompile from a game VPK. Comma-separate several files. Paths are kept:
#   ./stock/panorama/styles/hud/hud_reborn.css
podman run --rm --network=none -v "<dota>/game/dota:/dota:ro" -v ./stock:/out \
  s2tool decompile /dota/pak01_dir.vpk panorama/styles/hud/hud_reborn.vcss_c

# Compile everything in /in. Paths are kept:
#   ./compiled/panorama/styles/hud/hud_reborn.vcss_c, plus compile.log and toolchain.json
podman run --rm --network=none -v ./src:/in:ro -v ./compiled:/out s2tool compile

# Show the pinned tool versions
podman run --rm s2tool version
```

| Exit code | Meaning |
|---|---|
| 0 | ok |
| 1 | failed. Compile errors are printed with `/in/...` paths; the full log is in `/out/compile.log` |
| 2 | usage error |

| Env | Effect |
|---|---|
| `S2TOOL_XVFB=1` | run the compiler under Xvfb (hasn't been needed so far) |
| `S2TOOL_D3D=wined3d` | use Wine's OpenGL d3d11 instead of DXVK (untested fallback) |

Notes:
- **SELinux:** add `--security-opt label=disable`. Avoid `:Z` on a Steam library, because it relabels the
  game files.
- **File owner:** rootless podman writes `/out` as your user. Rootful docker writes it as root.

## Contents

| Component | Version |
|---|---|
| Debian trixie-slim | digest-pinned |
| Wine (WineHQ) | 11.0, 64-bit only |
| DXVK | 3.1.1 |
| Source2Viewer CLI | 20.1 |
| resourcecompiler ([workshoptools](https://github.com/Dota-Modding-Community/workshoptools)) | v1.0.0 |

How it works:
- **Rendering:** the compiler starts its DX11 renderer even for CSS. Here that runs on DXVK over lavapipe,
  Mesa's CPU-only Vulkan driver. Compiling doesn't draw anything, so speed isn't affected.
- **Compiler layout:** `/in` is copied to `content/dota_addons/s2tool/`, and the results are copied back
  from `game/dota_addons/s2tool/`.
- **Size:**
  - Wine's 32-bit half is left out (~700 MB).
  - Wine copies its DLLs into its prefix (its Windows folder); those copies are replaced with symlinks
    (~770 MB).
  - Mesa's GPU drivers are deleted.
- **Base image:** Debian, so every version can be pinned exactly and updated by Renovate.

## Updating

[Renovate](https://docs.renovatebot.com/) (`renovate.json`) bumps the base image, Wine, DXVK, Source2Viewer
and resourcecompiler. It can't update the download checksums, so on each Renovate PR run:

```sh
./update-checksums.sh
```

Until then the build fails, rather than using an unverified download.

## Tests

```sh
python3 test_s2tool.py
```

These check the log parsing and output paths, without needing Wine or the image.

## Notice

s2tool is an unofficial community tool. It is not affiliated with, endorsed by, or supported by Valve
Corporation. Dota 2, Source 2 and Steam are trademarks of Valve Corporation.

The image bundles third-party software, each under its own terms:

| Component | Owner | License | Source |
|---|---|---|---|
| `resourcecompiler.exe` and its DLLs (Workshop Tools) | Valve Corporation | Valve's terms; not open source | [workshoptools mirror](https://github.com/Dota-Modding-Community/workshoptools) |
| Wine | Wine project | LGPL-2.1-or-later | [winehq.org](https://www.winehq.org/), [gitlab.winehq.org/wine/wine](https://gitlab.winehq.org/wine/wine) |
| DXVK | Philip Rebohle and contributors | zlib | [github.com/doitsujin/dxvk](https://github.com/doitsujin/dxvk) |
| Source2Viewer (ValveResourceFormat) | ValveResourceFormat contributors | MIT | [github.com/ValveResourceFormat/ValveResourceFormat](https://github.com/ValveResourceFormat/ValveResourceFormat) |
| Debian, Mesa and other packages | their authors | various free licenses | [sources.debian.org](https://sources.debian.org/) |

Valve's Workshop Tools are included only so mods for Valve's games can be built. They are unmodified, and
using them is subject to Valve's terms, including the
[Steam Subscriber Agreement](https://store.steampowered.com/subscriber_agreement/). The exact versions are
pinned in the `Containerfile` and listed by `s2tool version`.

**Rights holders:** to have the image or any component removed, open an issue on this repo. It will be
taken down promptly.

This repo's own files (`Containerfile`, `s2tool.py`, scripts) contain no third-party binaries.
