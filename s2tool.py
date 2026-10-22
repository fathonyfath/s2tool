#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
"""s2tool: Source 2 toolchain entrypoint.

  s2tool decompile <pak01_dir.vpk> <file>[,<file>...]   Source2Viewer: _c -> css/xml/js/png into /out (paths kept)
  s2tool compile                                        resourcecompiler: /in (plain sources) -> /out (_c, paths kept)
  s2tool version                                        print toolchain.json

Env: S2TOOL_XVFB=1 runs the compiler under Xvfb; S2TOOL_D3D=wined3d uses Wine's OpenGL d3d11 instead of DXVK.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

IN = Path(os.environ.get("S2TOOL_IN", "/in"))
OUT = Path(os.environ.get("S2TOOL_OUT", "/out"))
S2V = "/opt/s2v/Source2Viewer-CLI"
RC = Path("/opt/rescomp")
TOOLCHAIN = Path("/opt/toolchain.json")
ADDON = "s2tool"

# compiled extension -> what Source2Viewer writes
DECOMPILED_EXT = {"vcss": "css", "vxml": "xml", "vjs": "js", "vts": "ts", "vtex": "png"}

# " OK: 1 compiled, 0 failed, ..." or " ERROR: 0 compiled, 1 failed, ..."
SUMMARY = re.compile(r"(?:OK|ERROR): (\d+) compiled, (\d+) failed")
# Z:\opt\rescomp\content\dota_addons\s2tool\panorama\x.css(4,2): RESOURCE COMPILE ERROR: Unexpected '}' ...
COMPILE_ERROR = re.compile(
    r"^Z:\\opt\\rescomp\\content\\dota_addons\\" + ADDON + r"\\(?P<path>.*?): RESOURCE COMPILE ERROR: (?P<msg>.*)$",
    re.M)


class Fail(Exception):
    """Exit with a message on stderr (code 1; 2 for usage errors)."""

    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


# ---------------------------------------------------------------- pure helpers (unit tested)

def decompiled_path(compiled):
    """panorama/styles/hud/hud_reborn.vcss_c -> panorama/styles/hud/hud_reborn.css"""
    stem, _, ext = compiled.removesuffix("_c").rpartition(".")
    return f"{stem}.{DECOMPILED_EXT.get(ext, ext)}"


def parse_log(text):
    """Return (compiled, failed, errors) from a resourcecompiler log; compiled is None if no summary."""
    summaries = SUMMARY.findall(text)
    errors = [f"{IN}/{m['path'].replace(chr(92), '/')}: {m['msg'].strip()}" for m in COMPILE_ERROR.finditer(text)]
    if not summaries:
        return None, None, errors
    ok, failed = summaries[-1]
    return int(ok), int(failed), errors


# ---------------------------------------------------------------- commands

def decompile(vpk, filter_):
    files = [f for f in filter_.split(",") if f]
    if not files:
        raise Fail("decompile: no files given", 2)
    dests = [OUT / decompiled_path(f) for f in files]
    # With several files, -o is a folder and Source2Viewer keeps their paths under it. With exactly one,
    # -o is the output *file*, so pass the full path. One call either way: each call re-reads the VPK index.
    if len(files) == 1:
        dests[0].parent.mkdir(parents=True, exist_ok=True)
    res = subprocess.run([S2V, "-i", vpk, "-o", dests[0] if len(files) == 1 else OUT, "-d", "-f", ",".join(files)],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    missing = [f for f, d in zip(files, dests) if not d.is_file() or d.stat().st_size == 0]
    if res.returncode != 0 or missing:
        sys.stderr.write(res.stdout)
        raise Fail(f"not found or not decompiled: {', '.join(missing) or '(Source2Viewer failed)'}")
    for d in dests:
        print(d)


def compile_():
    if not IN.is_dir():
        raise Fail(f"mount sources at {IN}", 2)
    OUT.mkdir(parents=True, exist_ok=True)
    src = RC / "content/dota_addons" / ADDON
    dst = RC / "game/dota_addons" / ADDON
    log = OUT / "compile.log"
    shutil.rmtree(src, ignore_errors=True)
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(IN, src, symlinks=True)

    cmd = ["wine", "game/bin/win64/resourcecompiler.exe", "-i", f"content/dota_addons/{ADDON}/*", "-r"]
    if os.environ.get("S2TOOL_XVFB") == "1":
        cmd = ["xvfb-run", "-a", *cmd]
    env = dict(os.environ)
    if os.environ.get("S2TOOL_D3D") == "wined3d":
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml=;d3d11,dxgi,d3d9,d3d10core=b"

    with open(log, "wb") as f:
        rc = subprocess.run(cmd, cwd=RC, env=env, stdout=f, stderr=subprocess.STDOUT).returncode
    subprocess.run(["wineserver", "-k"], stderr=subprocess.DEVNULL)

    shutil.copy(TOOLCHAIN, OUT / "toolchain.json")
    if dst.is_dir():
        shutil.copytree(dst, OUT, dirs_exist_ok=True)

    text = log.read_text(errors="replace")
    ok, failed, errors = parse_log(text)
    if ok is None:
        sys.stderr.write("\n".join(text.splitlines()[-40:]) + "\n")
        raise Fail(f"resourcecompiler gave no summary (exit {rc}); see compile.log")
    summary = f"{'OK' if failed == 0 and ok > 0 else 'ERROR'}: {ok} compiled, {failed} failed"
    if failed or not ok:
        for e in errors:
            print(e, file=sys.stderr)
        raise Fail(f"{summary}; see compile.log")
    print(f"s2tool: {summary}")


def usage():
    return __doc__.split("\n\n")[1] + "\n"


def main(argv):
    cmd, args = (argv[0], argv[1:]) if argv else ("help", [])
    try:
        if cmd == "decompile" and len(args) == 2:
            decompile(*args)
        elif cmd == "compile" and not args:
            compile_()
        elif cmd == "version" and not args:
            sys.stdout.write(TOOLCHAIN.read_text())
        elif cmd in ("help", "-h", "--help"):
            sys.stdout.write(usage())
        else:
            sys.stderr.write(usage())
            return 2
    except Fail as e:
        print(f"s2tool: {e}", file=sys.stderr)
        return e.code
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
