-- Tests GC-safety of the prefix string in ffi.context.
-- Regression test: ensure the prefix string is anchored to prevent GC.

local ok, ffi = pcall(require, "ffi")
if not ok then
    io.write("SKIP: FFI not available\n")
    os.exit(0)
end

local T = require("helpers")

-- Use a uniquely-suffixed prefix to avoid collisions (though each test file
-- runs in its own process, this keeps names distinct for clarity).
local prefix = "gc" .. tostring(math.random(1e6))
local ctx = ffi.context(prefix)
ctx:cdef("typedef struct { int x; } Obj;")

-- Allocate a lot of garbage to encourage GC to run.
for i = 1, 100000 do
    local _ = tostring(i) .. "garbage"
end
collectgarbage("collect")
collectgarbage("collect")

-- If prefix was GC'd, this will either error or return a wrong size.
T.eq(ctx:sizeof("Obj"), 4, "sizeof after GC")
T.ok(ctx:typeof("Obj") ~= nil, "typeof after GC")

T.done()
