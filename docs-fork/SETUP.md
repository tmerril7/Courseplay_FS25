# Dev setup for the Courseplay FS25 fork

## Lua 5.2 (matches CI)
The mod runs on the Giants engine's Lua 5.2; CI (`.github/workflows/unit-test.yml`)
uses Lua **5.2.4**. There was no system Lua, so it's built into `~/.local`
(no sudo needed):

```bash
cd <scratch>
curl -sSL https://www.lua.org/ftp/lua-5.2.4.tar.gz -o lua-5.2.4.tar.gz
tar xzf lua-5.2.4.tar.gz && cd lua-5.2.4
make posix SYSLIBS="-Wl,-E -ldl"      # 'posix' target skips readline (not installed)
make install INSTALL_TOP="$HOME/.local"
```

`~/.local/bin` is already on PATH (that's where `gh` lives). Verify:
```bash
lua -v      # Lua 5.2.4
luac -v     # Lua 5.2.4
```
`readline` is intentionally omitted — only affects the interactive REPL, not
`luac -p` syntax checks or running test scripts.

## What we can verify locally
Run `docs-fork/verify.sh` after any change:
- `verify.sh` — syntax-check every non-test `.lua` (`luac -p`) + run all test suites
- `verify.sh syntax` — syntax only (fast)
- `verify.sh tests` — test suites only

Note `BlockSequencerTest` (~37s) and `FieldworkCourseTest` (~11s) are slow (genetic
algorithm / full course gen); the whole suite takes ~1 min.

## What we CANNOT verify locally (needs the game)
luac + unit tests catch syntax errors and pure-logic regressions only. They do NOT
exercise: Giants-engine APIs, vehicle specialization loading, the spec-alias race
(the exact thing `fork/crash-fixes` addresses), multiplayer sync, HUD/GUI, or any
driving behavior. **Loading the mod in-game — and for MP fixes, a multiplayer
join — remains the real test.** Iterate in-game with `reload.bat`.

## Known pre-existing test failure (NOT ours)
`scripts/courseGenerator/test/IslandTest.lua:18` fails: expects 9900 island
vertices, gets 10201 (101×101 — over-samples both boundary rows). Deterministic,
in island detection, and unnoticed because CI's unit-test workflow runs only
CourseManagerTest / CpMathUtilTest / MovingAverageTest — not the courseGenerator
suite. Logged in IMPROVEMENTS.md as a candidate.
</content>
