# Test Suite Implementation Plan

## Goal

Add a `tests/` directory containing `*.test.lua` files that verify the custom
features added to this LuaJIT fork. Tests must be runnable against the locally
built `src/luajit` binary and must pass without installing anything.

---

## Directory layout

```
tests/
  run.sh              # test runner script
  helpers.lua         # shared assert/report helpers (required by each test file)
  ffi_context.test.lua
  ffi_context_gc.test.lua
  os_tmpname.test.lua
```

---

## Test runner: `tests/run.sh`

A POSIX shell script. Usage: `./tests/run.sh [filter]`

Logic:

1. Locate the luajit binary. Search in order:
   - `src/luajit` (local build, relative to repo root)
   - `$LUAJIT` env var if set
   - Bail with a clear message if neither is found.
2. Set `LUA_PATH="./tests/?.lua;;"` so `require("helpers")` resolves.
3. For each `tests/*.test.lua` (sorted), run:
   ```
   $LUAJIT tests/<file>.test.lua
   ```
4. Collect exit codes. Print a summary: `X passed, Y failed`.
5. Exit non-zero if any test file failed.

The script must not use bashisms — plain `sh` only.

---

## Shared helpers: `tests/helpers.lua`

Provide a minimal test API. No external dependencies.

```lua
-- require("helpers") returns a T table
local T = {}
T.passed = 0
T.failed = 0
T.file = arg and arg[0] or "?"

function T.ok(cond, msg)
  if cond then
    T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    io.stderr:write(("[FAIL] %s: %s\n"):format(T.file, msg or "assertion failed"))
  end
end

function T.eq(a, b, msg)
  T.ok(a == b, (msg or "") .. (" (expected %s, got %s)"):format(tostring(b), tostring(a)))
end

function T.err(fn, msg)
  -- assert fn() raises an error
  local ok, e = pcall(fn)
  T.ok(not ok, (msg or "expected error") .. " (no error raised; got: " .. tostring(e) .. ")")
end

function T.done()
  io.write(("[%s] %d passed, %d failed\n"):format(T.file, T.passed, T.failed))
  if T.failed > 0 then os.exit(1) end
end

return T
```

Each test file ends with `T.done()`.

---

## Test files

### `tests/ffi_context.test.lua`

Tests the `ffi.context([prefix])` API added in `src/lib_ffi.c`.

**Section 1 — Basic construction**

- `ffi.context()` returns a non-nil value.
- `ffi.context("pfx")` returns a non-nil value.
- The returned object has all expected methods as callable fields:
  `cdef`, `new`, `cast`, `typeof`, `sizeof`, `alignof`, `offsetof`,
  `metatype`, `istype`, `load`.
- Calling `ffi.context` with no args and `ffi.context("")` do not error.

**Section 2 — Namespaced `cdef` and type resolution**

Setup: `local ctx = ffi.context("my")`

- `ctx:cdef("typedef struct { int x; int y; } Point;")` does not error.
- `ctx:sizeof("Point")` returns `8` (two 32-bit ints).
- `ctx:typeof("Point")` returns a ctype whose name contains `"myPoint"`.
- The global `ffi.typeof("myPoint")` resolves to the same type (the type
  really is registered under the prefixed name).
- `ffi.typeof("Point")` raises an error — the unprefixed name is NOT
  registered in the global FFI namespace.

**Section 3 — `ctx:new`**

Setup (reuse ctx from section 2, or redefine):
```lua
local ctx = ffi.context("ns")
ctx:cdef("typedef struct { double v; } Val;")
```

- `ctx:new("Val")` returns a cdata of the correct type.
- `ctx:new("Val").v` is `0` (zero-initialised).
- `ctx:new("Val", {v = 3.14}).v` is approximately `3.14`.
- `ffi.istype("nsVal", ctx:new("Val"))` returns true.

**Section 4 — `ctx:cast` and `ctx:istype`**

Setup:
```lua
local ctx = ffi.context("C")
ctx:cdef("typedef int32_t MyInt;")
```

- `ctx:cast("MyInt", 42)` returns a cdata equal to `42`.
- `ctx:istype("MyInt", ctx:cast("MyInt", 0))` returns true.
- `ctx:istype("MyInt", ffi.new("int", 0))` returns false (different type).

**Section 5 — `ctx:sizeof` and `ctx:alignof`**

Setup:
```lua
local ctx = ffi.context("sz")
ctx:cdef([[
  typedef struct { char a; int b; } Padded;
  typedef struct __attribute__((packed)) { char a; int b; } Packed;
]])
```

- `ctx:sizeof("Padded")` is `>= 5` (due to padding, likely 8).
- `ctx:sizeof("Packed")` is exactly `5`.
- `ctx:alignof("Padded")` is `>= 4`.
- `ctx:alignof("Packed")` is `1`.

**Section 6 — `ctx:offsetof`**

Setup:
```lua
local ctx = ffi.context("off")
ctx:cdef("typedef struct { int a; int b; int c; } Triple;")
```

- `ctx:offsetof("Triple", "a")` is `0`.
- `ctx:offsetof("Triple", "b")` is `4`.
- `ctx:offsetof("Triple", "c")` is `8`.

**Section 7 — Multiple independent contexts**

- Define `ctxA = ffi.context("A")` and `ctxB = ffi.context("B")`.
- `ctxA:cdef("typedef int Num;")` — registers `ANum`.
- `ctxB:cdef("typedef float Num;")` — registers `BNum`.
- `ctxA:sizeof("Num")` is `4` (int).
- `ctxB:sizeof("Num")` is `4` (float, same size but different type).
- `ctxA:istype("Num", ctxA:new("Num"))` is true.
- `ctxA:istype("Num", ctxB:new("Num"))` is false (different types).
- `ffi.typeof("ANum")` and `ffi.typeof("BNum")` both resolve without error.

**Section 8 — No-prefix context behaves like plain ffi**

Setup:
```lua
local ctx = ffi.context()   -- no prefix
ctx:cdef("typedef uint8_t Byte;")
```

- `ctx:sizeof("Byte")` is `1`.
- `ffi.typeof("Byte")` resolves (unprefixed, registered globally).
- `ctx:new("Byte", 255)` holds `255`.

**Section 9 — Prefix stacking is NOT supported**

- Define a type with `ctxA`, then create `ctxB` with a different prefix.
- Accessing a type from `ctxA` through `ctxB` must fail (the B prefix
  does not compose on top of the A prefix).
- Concretely: `ctxA:cdef("typedef int Foo;")`, then
  `T.err(function() ctxB:sizeof("Foo") end, "cross-context lookup must fail")`.

**Section 10 — `ctx:metatype`**

Setup:
```lua
local ctx = ffi.context("mt")
ctx:cdef("typedef struct { int n; } Counter;")
local CounterMT = {}
CounterMT.__index = CounterMT
function CounterMT:inc() self.n = self.n + 1 end
ctx:metatype("Counter", CounterMT)
```

- `local c = ctx:new("Counter"); c:inc(); T.eq(c.n, 1, "metatype inc")`
- Calling `ctx:metatype("Counter", {})` a second time should raise an error
  (metatype is final once set).

---

### `tests/ffi_context_gc.test.lua`

Tests GC-safety of the prefix string (regression for the fix in
`fix(ffi.context): anchor prefix string to prevent gc`).

**Test: prefix survives GC cycles**

```lua
local ffi = require("ffi")
local T = require("helpers")

-- Create a context, force several GC cycles, then use it.
-- If the prefix string is not anchored, this may segfault or produce
-- garbled type names on a build with aggressive GC.
local ctx = ffi.context("gc" .. tostring(math.random(1e6)))
ctx:cdef("typedef struct { int x; } Obj;")

-- Allocate a lot of garbage to encourage GC to run.
for i = 1, 100000 do
  local _ = tostring(i) .. "garbage"
end
collectgarbage("collect")
collectgarbage("collect")

-- If prefix was GC'd, this will either error or return a wrong size.
T.eq(ctx:sizeof("Obj"), 4, "sizeof after GC")
T.eq(ctx:typeof("Obj") ~= nil, true, "typeof after GC")

T.done()
```

---

### `tests/os_tmpname.test.lua`

Tests the `os.tmpname()` `$TMPDIR` override added in `src/lib_os.c`.

**Section 1 — Default behaviour (no TMPDIR)**

If `TMPDIR` is not set in the environment, `os.tmpname()` must return a path
starting with `/tmp/lua_`.

```lua
-- Only valid when TMPDIR is unset. The run.sh script must unset TMPDIR
-- before running this test, or the test should skip gracefully.
if os.getenv("TMPDIR") then
  io.write("SKIP: TMPDIR is set, skipping default-path test\n")
else
  local name = os.tmpname()
  T.ok(name:sub(1, 5) == "/tmp/", "default prefix is /tmp/")
  T.ok(name:find("lua_"), "contains lua_")
end
```

**Section 2 — Respects `TMPDIR` env var**

This section requires the test runner to set `TMPDIR` before launching
luajit. The runner must pass it via the environment (e.g., `env TMPDIR=/var/tmp
luajit ...`), OR the test file can set it using `os.setenv` if available.
Since standard Lua has no `os.setenv`, the runner must handle this externally.

Approach: run the test file twice from `run.sh`:
- Once with `TMPDIR` unset.
- Once with `TMPDIR=/tmp/luajit_test_tmpdir` pre-created.

Within the test file, detect which mode via the env var:

```lua
local tmpdir = os.getenv("TMPDIR")
if tmpdir then
  local name = os.tmpname()
  -- Path must start with $TMPDIR/
  T.ok(name:sub(1, #tmpdir + 1) == tmpdir .. "/",
       "path starts with TMPDIR (" .. tmpdir .. ")")
  T.ok(name:find("lua_"), "contains lua_")
  -- The file must actually exist (mkstemp creates it).
  local f = io.open(name, "r")
  T.ok(f ~= nil, "tmpfile exists on disk")
  if f then f:close() os.remove(name) end
end
```

**Section 3 — Returned path is usable**

Regardless of `TMPDIR`:

- `os.tmpname()` returns a non-empty string.
- The file it names actually exists and can be opened for writing.
- Calling `os.tmpname()` twice returns two distinct paths.

```lua
local a = os.tmpname()
local b = os.tmpname()
T.ok(a ~= b, "two calls return distinct paths")
T.ok(#a > 0, "non-empty path")
local f = io.open(a, "w")
T.ok(f ~= nil, "file is writable")
if f then f:close() end
os.remove(a)
os.remove(b)
```

---

## Makefile integration

Add a `test` target to the top-level `Makefile`, after the existing targets:

```makefile
test:
	@./tests/run.sh
```

And extend the CI workflow (`.github/workflows/build.yml`) to add a test step
after each Linux x86-64 GNU build:

```yaml
- name: Run tests
  if: matrix.platform == 'linux' && matrix.arch == 'x86-64' && matrix.libc == 'gnu'
  run: ./tests/run.sh
```

---

## Implementation notes for DeepSeek

1. **FFI availability**: All `ffi_context` tests must `require("ffi")` at the
   top and skip gracefully if FFI is disabled:
   ```lua
   local ok, ffi = pcall(require, "ffi")
   if not ok then
     io.write("SKIP: FFI not available\n")
     os.exit(0)
   end
   ```

2. **`ffi.context` is on the ffi table**: It is registered as `ffi.context`,
   not as a global. Always access it as `ffi.context(...)`.

3. **Type names are concatenated without separator**: The prefix is
   concatenated directly — `ffi.context("my")` + type `"Foo"` = `"myFoo"`.
   There is no underscore. Tests must reflect this.

4. **`ctx:cdef` signature**: The first argument is `self` (the context
   userdata), second is the C declaration string. In method-call syntax:
   `ctx:cdef("...")` is correct.

5. **`ffi_context_gc` test** must use a uniquely-suffixed prefix to avoid
   colliding with types defined in other test files that may run in the same
   process (though `run.sh` runs each file as a separate process, so
   cross-file collision is not an issue — but keep names distinct for clarity).

6. **`os_tmpname` TMPDIR test**: The shell script must create the custom
   `TMPDIR` directory before passing it, and clean it up after:
   ```sh
   TESTDIR="$(mktemp -d)"
   TMPDIR="$TESTDIR" $LUAJIT tests/os_tmpname.test.lua
   rmdir "$TESTDIR" 2>/dev/null || true
   ```

7. **Exit codes**: Each test file exits 0 on full pass, 1 on any failure.
   `run.sh` accumulates failures and exits 1 if any file fails.

8. **No third-party test framework**: Use only `helpers.lua` and standard
   Lua/LuaJIT libraries. The test suite must work with a freshly built
   `src/luajit` and nothing else installed.
