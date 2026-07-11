#!/usr/bin/env bash
# Local verification for the Courseplay FS25 fork.
# Requires Lua 5.2 on PATH (built to ~/.local: `~/.local/bin/lua -v` -> 5.2.4).
# Usage:
#   docs-fork/verify.sh            # syntax-check all lua + run test suites
#   docs-fork/verify.sh syntax     # syntax check only
#   docs-fork/verify.sh tests      # test suites only
#
# NOTE: this is NOT a substitute for loading the mod in-game. It catches syntax
# errors and pure-logic regressions only; it cannot exercise Giants-engine APIs,
# specialization loading, multiplayer sync, or driving behavior.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mode="${1:-all}"
rc=0

command -v luac >/dev/null || { echo "ERROR: luac (Lua 5.2) not on PATH. Build it: see docs-fork/SETUP.md"; exit 2; }

if [[ "$mode" == "all" || "$mode" == "syntax" ]]; then
  echo "== Syntax check (luac -p) =="
  fail=0; total=0
  while IFS= read -r f; do
    total=$((total+1))
    luac -p "$f" 2>&1 || { echo "  SYNTAX FAIL: $f"; fail=$((fail+1)); }
  done < <(find scripts -name '*.lua' -not -path '*/test/*')
  echo "  checked $total files, $fail failures"
  [[ $fail -gt 0 ]] && rc=1
fi

if [[ "$mode" == "all" || "$mode" == "tests" ]]; then
  echo "== Unit tests =="
  run_test() { # dir file
    local out; out="$(cd "$1" && lua "$2" 2>&1)"
    if grep -qiE "[1-9][0-9]* failure|SYNTAX FAIL|stack traceback" <<<"$out"; then
      echo "  FAIL  $2"; grep -iE "fail|expected|actual|traceback" <<<"$out" | head -4
      rc=1
    else
      local line; line="$(grep -iE "Ran [0-9]+ test" <<<"$out" | tail -1)"
      echo "  ok    $2  ${line:-(no summary; exit clean)}"
    fi
  }
  for t in CpMathUtilTest LoggerTest MovingAverageTest CourseManagerTest; do
    run_test scripts/test "$t.lua"
  done
  for t in scripts/courseGenerator/test/*Test.lua; do
    run_test scripts/courseGenerator/test "$(basename "$t")"
  done
  for t in scripts/pathfinder/test/*Test.lua; do
    run_test scripts/pathfinder/test "$(basename "$t")"
  done
  # test runs write scratch dirs under scripts/test/; keep the tree clean
  rm -rf scripts/test/modSettings
fi

echo "== done (rc=$rc) =="
exit $rc
