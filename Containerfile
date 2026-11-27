# SPDX-License-Identifier: 0BSD (this file only; see README "Notice" for the bundled software)
# s2tool: Source 2 toolchain only. Source2Viewer (decompile) + Valve's resourcecompiler under Wine (compile).
# The image bundles Valve's Workshop Tools; see README "Notice" before publishing it.
#
#   podman build -t s2tool .
#
# Every version below is pinned. The "# renovate:" comments let Renovate bump them (see renovate.json);
# Renovate updates each *_SHA256 with its version. A version ARG holds the exact release tag, which Renovate needs to find the release.

# ---------------------------------------------------------------- downloads (verified, then discarded)
FROM docker.io/library/debian:trixie-slim@sha256:ab3b3c8c5159eebfca4376430132d53c4d425f869c765ecbe47177a030da575d AS fetch

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl 7zip \
 && rm -rf /var/lib/apt/lists/*

# renovate: datasource=github-release-attachments depName=doitsujin/dxvk
ARG DXVK_VERSION=v3.2
ARG DXVK_SHA256=17449ed21602377971289eb2984750699825ac1bac3bbfa2426b2bba0f355692
# renovate: datasource=github-release-attachments depName=ValveResourceFormat/ValveResourceFormat
ARG S2V_VERSION=21.2
ARG S2V_SHA256=e097d2d69854fa28d2ae7bd3698de23fc922f64a89037abedb3ed8b34527f8ba
# renovate: datasource=github-release-attachments depName=Dota-Modding-Community/workshoptools
ARG RESCOMP_VERSION=v1.0.1
ARG RESCOMP_SHA256=9b22dff52ce4da9553a1112cfec79dfc87739cda08865b4417bcddaf973b2107

WORKDIR /dl
RUN curl -fsSLo dxvk.tar.gz "https://github.com/doitsujin/dxvk/releases/download/${DXVK_VERSION}/dxvk-${DXVK_VERSION#v}.tar.gz" \
 && curl -fsSLo s2v.zip "https://github.com/ValveResourceFormat/ValveResourceFormat/releases/download/${S2V_VERSION}/cli-linux-x64.zip" \
 && curl -fsSLo rescomp.zip "https://github.com/Dota-Modding-Community/workshoptools/releases/download/${RESCOMP_VERSION}/resourcecompiler.zip" \
 && printf '%s  %s\n' "$DXVK_SHA256" dxvk.tar.gz "$S2V_SHA256" s2v.zip "$RESCOMP_SHA256" rescomp.zip | sha256sum -c - \
 && mkdir -p /opt/s2v /opt \
 && 7z x -bd -o/opt/s2v s2v.zip >/dev/null && chmod 755 /opt/s2v/Source2Viewer-CLI \
 && 7z x -bd -o/opt rescomp.zip >/dev/null && mv /opt/resourcecompiler /opt/rescomp \
 && tar -xzf dxvk.tar.gz \
 && for dll in d3d11 dxgi d3d9 d3d10core; do cp "dxvk-${DXVK_VERSION#v}/x64/${dll}.dll" /opt/rescomp/game/bin/win64/; done \
 && rm -rf /opt/rescomp/content/dota_addons/* /opt/rescomp/game/dota_addons/* \
 && printf '{\n  "image": "s2tool",\n  "wine": "%s",\n  "dxvk": "%s",\n  "source2viewer": "%s",\n  "resourcecompiler": "%s"\n}\n' \
      "@WINE@" "${DXVK_VERSION#v}" "$S2V_VERSION" "$RESCOMP_VERSION" > /opt/toolchain.json

# ---------------------------------------------------------------- runtime
FROM docker.io/library/debian:trixie-slim@sha256:ab3b3c8c5159eebfca4376430132d53c4d425f869c765ecbe47177a030da575d

# renovate: datasource=deb depName=wine-stable-amd64 registryUrl=https://dl.winehq.org/wine-builds/debian?suite=trixie&components=main&binaryArch=amd64
ARG WINE_VERSION=11.0.0.0~trixie-1

# Wine, 64-bit only: resourcecompiler is x64. The `wine-stable` package (launchers: wine, wineserver, wineboot)
# requires the ~700 MB 32-bit half, so it is unpacked by hand instead of installed. Then lavapipe (software Vulkan
# for DXVK; the package's real-GPU drivers are deleted, since the container never sees a GPU), Xvfb in case a
# display is needed.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor -o /etc/apt/keyrings/winehq.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/debian trixie main" \
      > /etc/apt/sources.list.d/winehq.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "wine-stable-amd64=${WINE_VERSION}" \
      mesa-vulkan-drivers libvulkan1 \
      xvfb xauth \
      libicu76 libfontconfig1 \
      python3 \
 && cd /tmp && apt-get download "wine-stable=${WINE_VERSION}" \
 && dpkg-deb -x wine-stable_*.deb / && rm wine-stable_*.deb \
 && find /usr/share/vulkan/icd.d -type f ! -name lvp_icd.json -delete \
 && find /usr/lib/x86_64-linux-gnu -maxdepth 1 -name 'libvulkan_*.so' ! -name libvulkan_lvp.so -delete \
 && apt-get purge -y curl gnupg && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

ENV PATH=/opt/wine-stable/bin:$PATH \
    WINEPREFIX=/opt/prefix \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=;d3d11,dxgi,d3d9,d3d10core=n" \
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
    XDG_RUNTIME_DIR=/run/s2tool \
    DXVK_LOG_LEVEL=warn

COPY --from=fetch /opt/s2v /opt/s2v
COPY --from=fetch /opt/rescomp /opt/rescomp
COPY --from=fetch /opt/toolchain.json /opt/toolchain.json

# Create the Wine prefix once, at build time. wineboot copies every builtin DLL (~770 MB) into the
# prefix; swap identical copies for symlinks to Wine's own files so the image doesn't carry them twice.
RUN install -d -m 700 /run/s2tool \
 && wineboot -i && wineserver -w \
 && find "$WINEPREFIX/drive_c/windows" -type f -exec sh -c 'lib=/opt/wine-stable/lib/wine/x86_64-windows; \
      for f; do b="$lib/$(basename "$f")"; [ -f "$b" ] && cmp -s "$f" "$b" && ln -sf "$b" "$f"; done; true' sh {} + \
 && sed -i "s/@WINE@/$(wine --version | sed 's/^wine-//')/" /opt/toolchain.json

COPY s2tool.py /usr/local/bin/s2tool
ENTRYPOINT ["s2tool"]
CMD ["help"]
