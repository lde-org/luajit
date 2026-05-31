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
