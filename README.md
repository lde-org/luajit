# luajit

This is `lde`'s fork of LuaJIT.

It contains features for the sake of improved cross platform capabilities, and those that would benefit the lde runtime.

## Supported Platforms

Here's a table of supported platforms and download links to the `luajit` binary.

| Platform    | Architecture            | libc          | Download                                                                                                        |
| ----------- | ----------------------- | ------------- | --------------------------------------------------------------------------------------------------------------- |
| **Linux**   | x86-64                  | glibc (2.35+) | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-linux-x86-64-gnu.tar.gz)    |
| **Linux**   | x86-64                  | musl          | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-linux-x86-64-musl.tar.gz)    |
| **Linux**   | aarch64 (ARM64)         | glibc (2.35+) | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-linux-aarch64-gnu.tar.gz)   |
| **Linux**   | aarch64 (ARM64)         | musl          | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-linux-aarch64-musl.tar.gz)  |
| **Linux**   | aarch64 (ARM64)         | android       | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-linux-aarch64-android.tar.gz) |
| **Windows** | x86-64                  | -             | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-windows-x86-64-gnu.tar.gz)  |
| **Windows** | aarch64 (ARM64)         | -             | [✅ Download](https://github.com/lde-org/luajit/releases/latest/download/luajit-windows-aarch64-gnu.tar.gz) |
| **macOS**   | x86-64 (Intel)          | -             | [✅ Download](https://github.com/lde-org/luajit/releases/download/latest/luajit-macos-x86-64.tar.gz)        |
| **macOS**   | aarch64 (Apple Silicon) | -             | [✅ Download](https://github.com/lde-org/luajit/releases/download/latest/luajit-macos-aarch64.tar.gz)       |

If you need to get the library instead, check out the [release](https://github.com/lde-org/luajit/releases/latest) page manually and download the corresponding `libluajit`, although you would usually do this programmatically.

## Extensions

### `ffi.context([prefix])`

Creates a namespaced FFI context that isolates C type declarations under an optional
prefix, preventing collisions with the global type namespace.

**Methods** (same API as the `ffi` module, operating on the context's namespace):
- `ctx:cdef(code)` — declare types, adding `prefix` to each top-level name
- `ctx:new(ctype, ...)` — allocate a cdata object
- `ctx:cast(ctype, init)` — cast to a C type
- `ctx:typeof(ctype)` — get the ctype of a type name
- `ctx:sizeof(ctype)` — get the size of a type
- `ctx:alignof(ctype)` — get the alignment of a type
- `ctx:offsetof(ctype, field)` — get the offset of a struct field
- `ctx:metatype(ctype, mt)` — set a metatype for a type
- `ctx:istype(val, ctype)` — check if a value is a given type
- `ctx:load(libname [, global])` — load a shared library

**Example**:
```lua
local ffi = require("ffi")

-- Create a context with prefix "foo", all types get "foo" prepended
local ctx = ffi.context("foo")
ctx:cdef([[ typedef int num; typedef struct { double v; } inner; ]])

-- Types are named "foonum", "fooinner" — no collisions with globals
local a = ctx:new("num")      -- cdata<int>
local b = ffi.new("foonum")   -- equivalent

-- Multiple contexts with different prefixes can use the same names
local a_ctx = ffi.context("a")
local b_ctx = ffi.context("b")
a_ctx:cdef("typedef int num;")   -- creates "anum" (int)
b_ctx:cdef("typedef double num;") -- creates "bnum" (double)

-- No-prefix context still useful for scoped cdef
local scoped = ffi.context()
scoped:cdef("typedef int foo;")
```

Types declared inside a context are stored in the global type namespace with the
prefix applied, so they are accessible globally (e.g., via `ffi.C` or `ffi.new`).
The prefix simply ensures each context gets unique names.

### `os.tmpname()` uses `TMPDIR`

The `os.tmpname()` function now resolves the temporary directory dynamically
instead of hardcoding `/tmp`. It checks the `TMPDIR` environment variable
(POSIX standard), falling back to `/tmp` if unset.

This makes `os.tmpname()` work correctly on platforms where `/tmp` is not
writable or does not exist, such as:
- **Termux** (Android) — `TMPDIR` points to `$PREFIX/tmp`
- Containerized or sandboxed environments with custom temp locations
- Any system that follows the POSIX convention of setting `TMPDIR`
