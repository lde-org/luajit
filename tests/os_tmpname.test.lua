-- Tests for os.tmpname() $TMPDIR override.
-- This file is run TWICE by the test runner:
--   1) With TMPDIR unset (tests default /tmp/ prefix)
--   2) With TMPDIR set to a custom directory (tests TMPDIR override)

local T = require("helpers")

----------------------------------------------------------------------
-- Section 1 — Default behaviour (no TMPDIR)
----------------------------------------------------------------------
if os.getenv("TMPDIR") then
    io.write("SKIP: TMPDIR is set, skipping default-path test\n")
else
    local name = os.tmpname()
    T.ok(name:sub(1, 5) == "/tmp/", "default prefix is /tmp/")
    T.ok(name:find("lua_"), "contains lua_")
end

----------------------------------------------------------------------
-- Section 2 — Respects TMPDIR env var
----------------------------------------------------------------------
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
    if f then
        f:close()
        os.remove(name)
    end
end

----------------------------------------------------------------------
-- Section 3 — Returned path is usable
----------------------------------------------------------------------
local a = os.tmpname()
local b = os.tmpname()
T.ok(a ~= b, "two calls return distinct paths")
T.ok(#a > 0, "non-empty path")
local f = io.open(a, "w")
T.ok(f ~= nil, "file is writable")
if f then f:close() end
os.remove(a)
os.remove(b)

T.done()
