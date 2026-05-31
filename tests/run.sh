#!/bin/sh
# Test runner for LuaJIT custom feature tests.
# Usage: ./tests/run.sh [filter]
#
# Locates the luajit binary, then runs each tests/*.test.lua file.
# For os_tmpname.test.lua, runs it twice: once with TMPDIR unset and
# once with a custom TMPDIR.
# Prints a summary and exits non-zero if any test file fails.
#
# Pure POSIX sh — no bashisms.

# --- Locate the luajit binary ---
LUAJIT=""
if [ -x src/luajit ]; then
  LUAJIT=src/luajit
elif [ -n "$LUAJIT" ] && [ -x "$LUAJIT" ]; then
  LUAJIT="$LUAJIT"
else
  echo "Error: luajit binary not found."
  echo "Try: make -C src"
  echo "Or set \$LUAJIT to the luajit binary path."
  exit 1
fi

# --- Set up Lua module path ---
export LUA_PATH="./tests/?.lua;;"

# --- Optional filter ---
FILTER="${1:-}"

# --- Counters ---
TOTAL_ERROR=0

# Find test files matching the filter (if any)
TEST_FILES=""
for f in tests/*.test.lua; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  if [ -n "$FILTER" ] && ! echo "$fname" | grep -q "$FILTER"; then
    continue
  fi
  TEST_FILES="$TEST_FILES $fname"
done

# Sort files alphabetically
SORTED=""
for f in $TEST_FILES; do
  SORTED="$SORTED
$f"
done
SORTED=$(echo "$SORTED" | sort -u)

TOTAL_COUNT=0
for f in $SORTED; do
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
done

if [ $TOTAL_COUNT -eq 0 ]; then
  echo "No test files matched."
  exit 0
fi

# --- Run each test file ---
for file in $SORTED; do
  case "$file" in
    os_tmpname.test.lua)
      # Run once with TMPDIR unset (tests default /tmp/ prefix)
      (
        unset TMPDIR
        "$LUAJIT" "tests/$file"
      )
      rc=$?
      [ $rc -ne 0 ] && TOTAL_ERROR=$((TOTAL_ERROR + 1))

      # Run once with a custom TMPDIR (tests TMPDIR override)
      TESTDIR="$(mktemp -d)"
      (
        TMPDIR="$TESTDIR"
        export TMPDIR
        "$LUAJIT" "tests/$file"
      )
      rc=$?
      [ $rc -ne 0 ] && TOTAL_ERROR=$((TOTAL_ERROR + 1))
      rmdir "$TESTDIR" 2>/dev/null || true
      ;;
    *)
      "$LUAJIT" "tests/$file"
      rc=$?
      [ $rc -ne 0 ] && TOTAL_ERROR=$((TOTAL_ERROR + 1))
      ;;
  esac
done

# --- Summary ---
echo ""
echo "--- Summary ---"
if [ $TOTAL_ERROR -gt 0 ]; then
  echo "Some test files failed."
  exit 1
else
  echo "All tests passed."
  exit 0
fi
