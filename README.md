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

There may be extensions or slight divergence from standard LuaJIT in order to support more platforms and for functionality that would significantly benefit lde. But they will be minimal as to avoid the maintenance burden.

### `os.tmpname()` uses `TMPDIR`

The `os.tmpname()` function now resolves the temporary directory dynamically
instead of hardcoding `/tmp`. It checks the `TMPDIR` environment variable
(POSIX standard), falling back to `/tmp` if unset.

This makes `os.tmpname()` work correctly on platforms where `/tmp` is not
writable or does not exist, such as:
- **Termux** (Android) — `TMPDIR` points to `$PREFIX/tmp`
- Containerized or sandboxed environments with custom temp locations
- Any system that follows the POSIX convention of setting `TMPDIR`
