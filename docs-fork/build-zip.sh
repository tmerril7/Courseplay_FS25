#!/usr/bin/env bash
# Build an installable FS25_Courseplay.zip from the current working tree, matching the
# repo's release rules (.github/workflows/build-release.yml) plus excluding docs-fork/.
#
# Usage:
#   docs-fork/build-zip.sh                # -> ../FS25_Courseplay.zip (next to the repo)
#   docs-fork/build-zip.sh /path/out.zip  # -> explicit output path
#   docs-fork/build-zip.sh "/mnt/c/Users/<you>/Documents/My Games/FarmingSimulator2025/mods/FS25_Courseplay.zip"
#
# Builds from `git ls-files` (tracked files only), so no build junk / untracked cruft
# leaks in. Requires python3 (no `zip` binary needed). modDesc.xml lands at the zip root.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/../FS25_Courseplay.zip}"

command -v python3 >/dev/null || { echo "ERROR: python3 required"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: not a git repo"; exit 2; }

python3 - "$OUT" <<'PY'
import sys, subprocess, zipfile, os, posixpath
out = os.path.abspath(sys.argv[1])
files = subprocess.check_output(["git", "ls-files"]).decode().splitlines()

def excluded(p):
    base = posixpath.basename(p)
    # mirrors build-release.yml: *.git* *.editorconfig *README* *LICENSE* test/* *.bat *.md Contributors.md
    if p.startswith(".git") or p.startswith(".github/"): return True
    if p.startswith("docs-fork/"): return True                 # our working notes (not upstream)
    if base in (".gitignore", ".editorconfig"): return True
    if "README" in base or "LICENSE" in base: return True
    if base.endswith(".md"): return True
    if base.endswith(".bat"): return True
    if "/test/" in p or p.startswith("test/"): return True
    return False

included = [f for f in files if not excluded(f)]
if "modDesc.xml" not in included:
    sys.exit("ERROR: modDesc.xml missing from include set - refusing to build")

os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in included:
        z.write(f, f)  # arcname = repo-relative path -> modDesc.xml at zip root

size_mb = os.path.getsize(out) / 1e6
print(f"Built {out}")
print(f"  {len(included)} files ({len(files) - len(included)} excluded), {size_mb:.1f} MB")
print(f"  root: {', '.join(sorted({n.split('/')[0] for n in included}))}")
PY

echo "Done. Install: drop this zip in the FS25 'mods' folder (and remove any unzipped"
echo "FS25_Courseplay dev folder so they don't conflict)."
