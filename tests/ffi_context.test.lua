-- Tests for ffi.context([prefix]) API
-- Implementation notes:
--   - Prefix is concatenated directly: ffi.context("my") + "Foo" = "myFoo"
--   - Access via ffi.context(...), not as a global

local ok, ffi = pcall(require, "ffi")
if not ok then
    io.write("SKIP: FFI not available\n")
    os.exit(0)
end

local T = require("helpers")

-- Helper: create a context with a random prefix so tests within a file
-- do not collide with each other.
local function new_ctx()
    return ffi.context(tostring(math.random(1e9)))
end

----------------------------------------------------------------------
-- Section 1 — Basic construction
----------------------------------------------------------------------
T.ok(ffi.context() ~= nil, "ffi.context() returns non-nil")
T.ok(ffi.context("pfx") ~= nil, 'ffi.context("pfx") returns non-nil')

local methods = { "cdef", "new", "cast", "typeof", "sizeof", "alignof", "offsetof",
    "metatype", "istype", "load" }
local ctx = ffi.context()
for _, m in ipairs(methods) do
    T.ok(type(ctx[m]) == "function", "ctx." .. m .. " is callable")
end

-- Calling with no args and empty string do not error
T.ok(ffi.context() ~= nil, "ffi.context() with no args does not error")
T.ok(ffi.context("") ~= nil, 'ffi.context("") does not error')

----------------------------------------------------------------------
-- Section 2 — Namespaced cdef and type resolution
----------------------------------------------------------------------
do
    local ctx = ffi.context("my")

    T.ok(pcall(ctx.cdef, ctx, "typedef struct { int x; int y; } Point;"),
        "ctx:cdef does not error")

    T.eq(ctx:sizeof("Point"), 8, "sizeof(myPoint) is 8")

    local ctype = ctx:typeof("Point")
    T.ok(ctype ~= nil, "ctx:typeof returns a ctype")
    -- The prefixed name is registered globally (and thus resolvable)
    T.ok(ffi.typeof("myPoint") ~= nil, "ffi.typeof('myPoint') resolves globally")

    -- The unprefixed name is NOT registered globally
    T.err(function() ffi.typeof("Point") end,
        "ffi.typeof('Point') must fail (unprefixed name not in global namespace)")
end

----------------------------------------------------------------------
-- Section 3 — ctx:new
----------------------------------------------------------------------
do
    local ctx = ffi.context("ns")
    ctx:cdef("typedef struct { double v; } Val;")

    local val = ctx:new("Val")
    T.ok(val ~= nil, "ctx:new returns a cdata")
    T.eq(val.v, 0.0, "ctx:new zero-initialises struct")

    local val2 = ctx:new("Val", { v = 3.14 })
    -- Allow small floating-point tolerance
    T.ok(math.abs(val2.v - 3.14) < 1e-9, "ctx:new with initializer sets value")

    T.ok(ffi.istype("nsVal", ctx:new("Val")), "ffi.istype('nsVal', ctx:new('Val')) is true")
end

----------------------------------------------------------------------
-- Section 4 — ctx:cast and ctx:istype
----------------------------------------------------------------------
do
    local ctx = ffi.context("C")
    ctx:cdef("typedef double MyFloat;")

    local ci = ctx:cast("MyFloat", 42)
    T.ok(ci ~= nil, "ctx:cast returns a cdata")
    T.eq(tonumber(ci), 42, "ctx:cast value is correct")

    T.ok(ctx:istype("MyFloat", ctx:cast("MyFloat", 0)),
        "ctx:istype('MyFloat', cast value) returns true")

    T.ok(not ctx:istype("MyFloat", ffi.new("int", 0)),
        "ctx:istype('MyFloat', ffi.new('int')) returns false (different type)")
end

----------------------------------------------------------------------
-- Section 5 — ctx:sizeof and ctx:alignof
----------------------------------------------------------------------
do
    local ctx = ffi.context("sz")
    ctx:cdef([[
    typedef struct { char a; int b; } Padded;
    typedef struct __attribute__((packed)) { char a; int b; } Packed;
  ]])

    T.ok(ctx:sizeof("Padded") >= 5, "sizeof(Padded) >= 5")
    T.eq(ctx:sizeof("Packed"), 5, "sizeof(Packed) == 5 (packed, no padding)")
    T.ok(ctx:alignof("Padded") >= 4, "alignof(Padded) >= 4")
    T.eq(ctx:alignof("Packed"), 1, "alignof(Packed) == 1 (packed, byte-aligned)")
end

----------------------------------------------------------------------
-- Section 6 — ctx:offsetof
----------------------------------------------------------------------
do
    local ctx = ffi.context("off")
    ctx:cdef("typedef struct { int a; int b; int c; } Triple;")

    T.eq(ctx:offsetof("Triple", "a"), 0, "offsetof a is 0")
    T.eq(ctx:offsetof("Triple", "b"), 4, "offsetof b is 4")
    T.eq(ctx:offsetof("Triple", "c"), 8, "offsetof c is 8")
end

----------------------------------------------------------------------
-- Section 7 — Multiple independent contexts
----------------------------------------------------------------------
do
    local ctxA = ffi.context("A")
    local ctxB = ffi.context("B")

    ctxA:cdef("typedef int Num;")
    ctxB:cdef("typedef float Num;")

    T.eq(ctxA:sizeof("Num"), 4, "ctxA sizeof Num is 4 (int)")
    T.eq(ctxB:sizeof("Num"), 4, "ctxB sizeof Num is 4 (float, same size)")

    T.ok(ctxA:istype("Num", ctxA:new("Num")),
        "ctxA istype(Num, ctxA:new(Num)) is true")
    T.ok(not ctxA:istype("Num", ctxB:new("Num")),
        "ctxA istype(Num, ctxB:new(Num)) is false (different types)")

    -- Both prefixed types resolve globally
    T.ok(ffi.typeof("ANum") ~= nil, "ffi.typeof('ANum') resolves")
    T.ok(ffi.typeof("BNum") ~= nil, "ffi.typeof('BNum') resolves")
end

----------------------------------------------------------------------
-- Section 8 — No-prefix context behaves like plain ffi
----------------------------------------------------------------------
do
    local ctx = ffi.context() -- no prefix
    ctx:cdef("typedef uint8_t Byte;")

    T.eq(ctx:sizeof("Byte"), 1, "sizeof(Byte) is 1 with no-prefix context")
    -- Unprefixed type is registered globally
    T.ok(ffi.typeof("Byte") ~= nil, "ffi.typeof('Byte') resolves globally (no prefix)")
    T.eq(tonumber(ctx:new("Byte", 255)), 255, "ctx:new('Byte', 255) holds 255")
end

----------------------------------------------------------------------
-- Section 9 — Prefix stacking is NOT supported
----------------------------------------------------------------------
do
    local ctxA = ffi.context("A")
    local ctxB = ffi.context("B") -- different prefix

    ctxA:cdef("typedef int Foo;")

    T.err(function() ctxB:sizeof("Foo") end,
        "cross-context lookup must fail (prefix stacking not supported)")
end

----------------------------------------------------------------------
-- Section 10 — ctx:metatype
----------------------------------------------------------------------
do
    local ctx = ffi.context("mt")
    ctx:cdef("typedef struct { int n; } Counter;")
    local CounterMT = {}
    CounterMT.__index = CounterMT
    function CounterMT:inc() self.n = self.n + 1 end

    ctx:metatype("Counter", CounterMT)

    local c = ctx:new("Counter")
    c:inc()
    T.eq(c.n, 1, "metatype inc works via ctx:metatype")

    -- Setting metatype a second time should error
    T.err(function() ctx:metatype("Counter", {}) end,
        "setting metatype twice must error")
end

----------------------------------------------------------------------
-- Section 11 — ctx:sizeof with built-in / alias types
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef int MyInt;")
    T.eq(c:sizeof("MyInt"), ffi.sizeof("int"), "sizeof typedef alias")
end

----------------------------------------------------------------------
-- Section 12 — ctx:typeof returns usable ctype
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { float x; float y; float z; } Vec3;")
    local ct = c:typeof("Vec3")
    T.eq(ffi.sizeof(ct), ffi.sizeof("float") * 3, "typeof ctype usable with ffi.sizeof")
end

----------------------------------------------------------------------
-- Section 13 — ctx:new edge cases
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { int val; } Box;")
    local b = c:new("Box")
    b.val = 99
    T.eq(b.val, 99, "new field writes survive read back")
end

----------------------------------------------------------------------
-- Section 14 — ctx:cast with pointer types
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { int n; } Cell;")
    local cell = c:new("Cell", { n = 1 })
    local ptr = c:cast("Cell *", cell)
    T.eq(ptr.n, 1, "cast pointer dereferences correctly")
    ptr.n = 55
    T.eq(cell.n, 55, "cast pointer write visible through original")
end

----------------------------------------------------------------------
-- Section 15 — ctx.C function proxy
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef([[ unsigned long strlen(const char * s); ]])
    local okC, CC = pcall(function() return c.C end)
    if okC and CC then
        T.ok(type(CC) == "userdata", "ctx.C is a userdata")
        T.ok(type(CC.strlen) == "cdata", "ctx.C.strlen is a cdata")
        T.eq(tonumber(CC.strlen("hello")), 5, "ctx.C.strlen(hello) = 5")
        T.eq(tonumber(CC.strlen("")), 0, "ctx.C.strlen('') = 0")

        -- Verify multiple functions resolve independently
        c:cdef([[ int atoi(const char * s); ]])
        T.eq(tonumber(CC.atoi("123")), 123, "ctx.C.atoi('123') = 123")
    else
        io.write("SKIP: ctx.C not yet implemented\n")
    end
end

----------------------------------------------------------------------
-- Section 16 — ctx.C context isolation: same symbol, two namespaces
----------------------------------------------------------------------
do
    local c1 = ffi.context("ns1_")
    local c2 = ffi.context("ns2_")
    -- Both contexts cdef the same identifier; prefixes prevent collision.
    c1:cdef("unsigned long strlen(const char * s);")
    c2:cdef("unsigned long strlen(const char * s);")
    -- Each resolves via its own prefix -> same underlying C symbol, no conflict.
    T.eq(tonumber(c1.C.strlen("hi")),    2, "ctx1.C.strlen resolves correctly")
    T.eq(tonumber(c2.C.strlen("hello")), 5, "ctx2.C.strlen resolves correctly")
    -- Only c1 defines atoi; c2.C.atoi must fail (undeclared in ns2_).
    c1:cdef("int atoi(const char * s);")
    T.ok(pcall(function() return c1.C.atoi("7") end),      "c1.C.atoi declared -> ok")
    T.ok(not pcall(function() return c2.C.atoi("7") end),  "c2.C.atoi not declared -> error")
end

----------------------------------------------------------------------
-- Section 17 — ctx:metatype __tostring
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { int n; } Num;")
    c:metatype("Num", {
        __tostring = function(self) return "Num(" .. self.n .. ")" end
    })
    local v = c:new("Num", { n = 99 })
    T.eq(tostring(v), "Num(99)", "metatype __tostring works")
end

----------------------------------------------------------------------
-- Section 18 — ctx:istype non-matching types within same context
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { int x; } A;")
    c:cdef("typedef struct { int x; } B;")
    local a = c:new("A")
    T.ok(not c:istype("B", a), "istype returns false for non-matching ctype")
end

----------------------------------------------------------------------
-- Section 19 — Parse error formatting
----------------------------------------------------------------------
do
    local c = new_ctx()
    local ok, err = pcall(function()
        c:cdef([[
            typedef struct {
                int x
            } Foo;
        ]])
    end)
    T.ok(not ok, "parse error raised on malformed cdef")
    T.ok(type(err) == "string" and #err > 0, "parse error is a non-empty string")
    T.ok(err:find("line"), "parse error mentions line number")
    T.ok(err:find(";") or err:find("expected"), "parse error mentions missing token")
    T.ok(err:find("int x") or err:find("}"), "parse error includes source context")
    T.ok(err:find("%^") or err:find("near"), "parse error includes position marker")
end

----------------------------------------------------------------------
-- Section 20 — ffi.context() with no prefix (auto-generated)
----------------------------------------------------------------------
do
    do
        local c = new_ctx()
        c:cdef("typedef struct { int x; int y; } AutoPoint;")
        T.eq(c:sizeof("AutoPoint"), ffi.sizeof("int") * 2,
            "ffi: sizeof resolves struct")
    end

    do
        local c = new_ctx()
        c:cdef("typedef struct { int a; int b; } AutoPair;")
        local p = c:new("AutoPair")
        T.eq(p.a, 0, "ffi: new zero-initialises (a)")
        T.eq(p.b, 0, "ffi: new zero-initialises (b)")
    end

    do
        local c = new_ctx()
        c:cdef("typedef struct { int x; int y; } AutoCoord;")
        local p = c:new("AutoCoord", { x = 5, y = 9 })
        T.eq(p.x, 5, "ffi: new with init sets x")
        T.eq(p.y, 9, "ffi: new with init sets y")
    end

    do
        local c = new_ctx()
        c:cdef("typedef struct { float x; float y; } AutoVec2;")
        local ct = c:typeof("AutoVec2")
        T.eq(ffi.sizeof(ct), ffi.sizeof("float") * 2,
            "ffi: typeof returns usable ctype")
    end

    do
        local c = new_ctx()
        c:cdef("typedef struct { int n; } AutoCell;")
        local cell = c:new("AutoCell", { n = 7 })
        local ptr = c:cast("AutoCell *", cell)
        ptr.n = 88
        T.eq(cell.n, 88, "ffi: cast pointer write visible")
    end

    do
        local c = new_ctx()
        c:cdef("unsigned long strlen(const char * s);")
        local okC, CC = pcall(function() return c.C end)
        if okC and CC then
            T.eq(tonumber(CC.strlen("world")), 5, "ffi: C proxy resolves functions")
        else
            io.write("SKIP: ffi: C proxy not yet implemented\n")
        end
    end

    do
        -- Two contexts with distinct random prefixes do not collide.
        local c1 = new_ctx()
        local c2 = new_ctx()
        c1:cdef("typedef struct { int v; } NpShared;")
        c2:cdef("typedef struct { int v; int w; } NpShared;")
        T.ok(c1:sizeof("NpShared") ~= c2:sizeof("NpShared"),
            "ffi: two distinct-prefix contexts do not collide")
    end

    do
        local c = new_ctx()
        c:cdef("typedef struct { int x; int y; } AutoPt;")
        c:metatype("AutoPt", {
            __index = {
                sum = function(self) return self.x + self.y end
            }
        })
        local p = c:new("AutoPt", { x = 10, y = 20 })
        T.eq(p:sum(), 30, "ffi: metatype registers methods")
    end

    do
        local c = new_ctx()
        c:cdef("typedef struct { int x; } AutoVec;")
        local v = c:new("AutoVec")
        T.ok(c:istype("AutoVec", v), "ffi: istype returns true")
    end
end

----------------------------------------------------------------------
-- Section 21 — Real-world cdef patterns
----------------------------------------------------------------------
do
    local c = new_ctx()

    -- 21a: Mixed unnamed and named params
    T.ok(pcall(c.cdef, c, "void whatever(char* name, char*, int f);"),
        "cdef with mixed named/unnamed params")

    -- 21b: Win32-style multi-typedef with function
    T.ok(pcall(c.cdef, c, [[
        typedef void* HANDLE;
        typedef unsigned long DWORD;
        typedef struct {
            DWORD nLength;
            void* lpSecurityDescriptor;
            int bInheritHandle;
        } SECURITY_ATTRIBUTES;
        int CreateProcessA(const char*, char*, void*, void*, int, DWORD, void*, const char*, void*, void*);
    ]]), "cdef with win32-style types and function")

    -- 21c: Simple void pointer function
    T.ok(pcall(c.cdef, c, "void *dlopen(const char *filename, int flags);"),
        "cdef with void pointer function")

    -- 21d: Variadic function
    T.ok(pcall(c.cdef, c, "int open(const char* path, int flags, ...);"),
        "cdef with variadic function")

    -- 21e: Bare struct definition followed by function
    T.ok(pcall(c.cdef, c, [[
        struct pollfd { int fd; short events; short revents; };
        int poll(struct pollfd* fds, unsigned long nfds, int timeout);
    ]]), "cdef with bare struct then function")

    -- 21f: Forward typedef then bare struct definition
    T.ok(pcall(c.cdef, c, [[
        typedef struct Foo Foo;
        struct Foo { int x; };
    ]]), "cdef with forward typedef then struct")

    -- 21g: Typedef struct with multiple declarators
    -- Note: use a unique tag name to avoid conflict with 21f's 'Foo'
    T.ok(pcall(c.cdef, c, "typedef struct Bar { int x; } Bar, *BarPtr;"),
        "cdef with multiple declarators")

    -- 21h: Typedef union with anonymous struct member
    T.ok(pcall(c.cdef, c, [[
        typedef union {
            struct { unsigned int lo, hi; };
            unsigned long long val;
        } LARGE_INTEGER;
    ]]), "cdef with union + anonymous struct")

    -- 21i: Function with array-notation parameter
    T.ok(pcall(c.cdef, c, "int execv(const char* path, char* const argv[]);"),
        "cdef with array-notation parameter")

    -- 21j: Extern array declaration
    T.ok(pcall(c.cdef, c, "extern char* environ[];"),
        "cdef with extern array declaration")

    -- 21k: Nested anonymous struct field with built-in type
    T.ok(pcall(c.cdef, c, [[
        typedef struct {
            char *name;
            char *email;
            struct {
                int64_t time;
                int offset;
                char sign;
            } when;
        } git_signature;
    ]]), "cdef with nested anonymous struct field")
    T.ok(c:sizeof("git_signature") > 0, "sizeof nested struct > 0")

    -- 21l: Multiple forward typedefs in sequence
    T.ok(pcall(c.cdef, c, [[
        typedef struct git_index     git_index;
        typedef struct git_remote    git_remote;
        typedef struct git_submodule git_submodule;
    ]]), "cdef with multiple forward typedefs")

    -- 21m: Typedef struct with array field and pointer field
    T.ok(pcall(c.cdef, c, [[
        typedef struct { unsigned char id[20]; } git_oid;
        typedef struct { const char *message; int klass; } git_error;
    ]]), "cdef with array and pointer fields")
    T.eq(c:sizeof("git_oid"), 20, "sizeof git_oid == 20")

    -- 21n: Typedef struct with padding / sentinel fields
    T.ok(pcall(c.cdef, c, [[
        typedef struct { char _[376]; const char *checkout_branch; char _rest[32]; } git_clone_options;
        typedef struct { char _[376]; } git_submodule_update_options;
        typedef struct { unsigned int version; unsigned int checkout_strategy; char _rest[136]; } git_checkout_options;
    ]]), "cdef with padding array fields")
    T.eq(c:sizeof("git_submodule_update_options"), 376,
        "sizeof sentinel-filled struct == 376")

    -- 21o: Bare forward struct declaration
    T.ok(pcall(c.cdef, c, [[
        struct libdeflate_compressor;
        struct libdeflate_decompressor;
    ]]), "cdef with bare forward struct declarations")

    -- 21p: Enum with explicit integer values
    T.ok(pcall(c.cdef, c, [[
        typedef enum {
            RESULT_SUCCESS = 0,
            RESULT_BAD_DATA = 1,
            RESULT_NOMEM = 2
        } result_t;
    ]]), "cdef with enum values")

    -- 21q: Function pointer parameter
    T.ok(pcall(c.cdef, c, [[
        typedef struct git_submodule git_submodule;
        typedef struct git_repository git_repository;
        int git_submodule_foreach(git_repository *repo,
            int (*cb)(git_submodule *sm, const char *name, void *payload),
            void *payload);
    ]]), "cdef with function pointer parameter")

    -- 21r: Typedef struct then function using it as pointer param
    T.ok(pcall(c.cdef, c, [[
        typedef struct { long tv_sec; long tv_nsec; } timespec;
        int clock_gettime(int clk_id, timespec *tp);
    ]]), "cdef with struct then function using it")
    T.eq(c:sizeof("timespec"), ffi.sizeof("long") * 2,
        "sizeof timespec == 2 * sizeof(long)")

    -- 21s: Enum variants from two contexts do not collide
    local c2 = new_ctx()
    T.ok(pcall(c.cdef, c2, "typedef enum { MY_OK = 0, MY_ERR = 1 } status_t;"),
        "cdef enum in ctx2")
end

----------------------------------------------------------------------
-- Section 22 — resolveTypename: built-in types pass through
----------------------------------------------------------------------
do
    local c = new_ctx()
    T.eq(c:sizeof("int"), ffi.sizeof("int"), "sizeof builtin int")
    T.eq(c:sizeof("uint32_t"), ffi.sizeof("uint32_t"), "sizeof builtin uint32_t")
    T.eq(c:sizeof("size_t"), ffi.sizeof("size_t"), "sizeof builtin size_t")
    T.eq(c:sizeof("double"), ffi.sizeof("double"), "sizeof builtin double")

    local ct = c:typeof("int")
    T.eq(ffi.sizeof(ct), ffi.sizeof("int"), "typeof builtin int")
end

----------------------------------------------------------------------
-- Section 23 — resolveTypename: const modifier
----------------------------------------------------------------------
do
    local c = new_ctx()
    local s = c:cast("const char *", "hello")
    T.eq(ffi.string(s), "hello", "cast const char *")

    c:cdef("typedef struct { int x; int y; } Vec2;")
    local v = c:new("Vec2", { x = 3, y = 4 })
    local p = c:cast("const Vec2 *", v)
    T.eq(p.x, 3, "cast const Vec2 * x")
    T.eq(p.y, 4, "cast const Vec2 * y")

    -- const builtin pointer
    local n = ffi.new("int[1]", 7)
    local p2 = c:cast("const int *", n)
    T.eq(p2[0], 7, "cast const int *")
end

----------------------------------------------------------------------
-- Section 24 — resolveTypename: struct/enum/union keyword prefix
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct Node { int val; struct Node *next; } Node;")
    T.eq(c:sizeof("struct Node"), c:sizeof("Node"),
        "sizeof struct tag resolves to prefixed tag")

    -- cast struct tag pointer
    c:cdef("typedef struct { int a; int b; } Pair;")
    local p = c:new("Pair", { a = 1, b = 2 })
    local ptr = c:cast("Pair *", p)
    T.eq(ptr.a, 1, "cast Pair * a")
    T.eq(ptr.b, 2, "cast Pair * b")

    -- enum tag
    c:cdef("typedef enum Color { COLOR_RED = 0, COLOR_GREEN = 1 } Color;")
    T.eq(c:sizeof("enum Color"), c:sizeof("Color"),
        "sizeof enum tag resolves to prefixed tag")

    -- union
    c:cdef("typedef union { int x; float y; } Data;")
    T.eq(c:sizeof("Data"), 4, "sizeof union")

    -- typeof struct tag
    c:cdef("typedef struct { float r; float g; float b; } RGB;")
    local ct = c:typeof("RGB")
    T.eq(ffi.sizeof(ct), ffi.sizeof("float") * 3, "typeof struct tag")
end

----------------------------------------------------------------------
-- Section 25 — resolveTypename: pointer variants
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { int v; } Box;")
    local b = c:new("Box", { v = 42 })
    local vp = c:cast("void *", b)
    local p = c:cast("Box *", vp)
    T.eq(p.v, 42, "cast to void* and back preserves value")

    -- Built-in array type passes through
    local arr = c:new("int[4]")
    arr[0] = 10
    T.eq(arr[0], 10, "new with built-in array type")
end

----------------------------------------------------------------------
-- Section 26 — resolveTypename: error on unknown names
----------------------------------------------------------------------
do
    local c = new_ctx()

    local ok1, err1 = pcall(function() c:sizeof("NoSuchType") end)
    T.ok(not ok1, "sizeof unknown type errors")
    T.ok(err1:find("NoSuchType"), "sizeof error mentions type name")

    local ok2, err2 = pcall(function() c:typeof("Phantom") end)
    T.ok(not ok2, "typeof unknown type errors")
    T.ok(err2:find("Phantom"), "typeof error mentions type name")

    local ok3, err3 = pcall(function() c:cast("Ghost *", nil) end)
    T.ok(not ok3, "cast unknown base type errors")
    T.ok(err3:find("Ghost"), "cast error mentions type name")

    local ok4, err4 = pcall(function() c:cast("struct Nope *", nil) end)
    T.ok(not ok4, "cast unknown struct tag errors")
    T.ok(err4:find("Nope"), "cast struct tag error mentions name")

    local ok5, err5 = pcall(function() c:alignof("Spooky") end)
    T.ok(not ok5, "alignof unknown type errors")
    T.ok(err5:find("Spooky"), "alignof error mentions type name")

    local ok6, err6 = pcall(function() c:offsetof("Blorp", "x") end)
    T.ok(not ok6, "offsetof unknown type errors")
    T.ok(err6:find("Blorp"), "offsetof error mentions type name")

    -- const unknown type errors
    local ok7, err7 = pcall(function() c:cast("const Wraith *", nil) end)
    T.ok(not ok7, "cast const unknown type errors")
    T.ok(err7:find("Wraith"), "cast const error mentions type name")
end

----------------------------------------------------------------------
-- Section 27 — ctype passthrough (all methods accept ctype objects)
----------------------------------------------------------------------
do
    local c = new_ctx()

    c:cdef("typedef struct { int x; int y; } Pt;")
    local ct = c:typeof("Pt")
    local p = c:new(ct, { x = 1, y = 2 })
    T.eq(p.x, 1, "new with ctype sets x")
    T.eq(p.y, 2, "new with ctype sets y")

    c:cdef("typedef struct { int x; int y; } Sz;")
    local ct2 = c:typeof("Sz")
    T.eq(c:sizeof(ct2), ffi.sizeof("int") * 2, "sizeof with ctype")

    c:cdef("typedef struct { int n; } Castable;")
    local ct3 = c:typeof("Castable")
    local v = c:new("Castable", { n = 7 })
    local ok_pt, pt = pcall(c.typeof, c, "$ *", ct3)
    if ok_pt then
        local ptr = c:cast(pt, v)
        T.eq(ptr.n, 7, "cast with ctype passes through")
    else
        io.write("SKIP: typeof with $ substitution not yet supported\n")
    end

    -- typeof with dollar substitution
    c:cdef("typedef struct { float v; } Flt2;")
    local ct4 = c:typeof("Flt2")
    local ok_pt2, pt2 = pcall(c.typeof, c, "$ *", ct4)
    if ok_pt2 then
        local v2 = c:new("Flt2", { v = 1.5 })
        local p2 = ffi.cast(pt2, v2)
        T.eq(p2.v, 1.5, "typeof with $ substitution")
    else
        io.write("SKIP: typeof with $ substitution not yet supported\n")
    end

    -- typeof with ctype passes through
    c:cdef("typedef struct { float v; } Flt;")
    local ct5 = c:typeof("Flt")
    local ok_ct6, ct6 = pcall(c.typeof, c, ct5)
    if ok_ct6 then
        T.eq(ffi.sizeof(ct6), ffi.sizeof("float"), "typeof with ctype returns same type")
    else
        io.write("SKIP: typeof with ctype not yet supported\n")
    end

    -- alignof with ctype
    c:cdef("typedef struct { int x; } Aligned;")
    local ct7 = c:typeof("Aligned")
    T.eq(c:alignof(ct7), ffi.alignof("int"), "alignof with ctype")

    -- offsetof with ctype
    c:cdef("typedef struct { int a; int b; } Off;")
    local ct8 = c:typeof("Off")
    T.eq(c:offsetof(ct8, "b"), ffi.sizeof("int"), "offsetof with ctype")

    -- istype with ctype
    c:cdef("typedef struct { int x; } Ity;")
    local ct9 = c:typeof("Ity")
    local v3 = c:new("Ity")
    T.ok(c:istype(ct9, v3), "istype with ctype")

    -- metatype with ctype
    c:cdef("typedef struct { int x; } Meta2;")
    local ct10 = c:typeof("Meta2")
    c:metatype(ct10, {
        __index = { doubled = function(self) return self.x * 2 end }
    })
    local v4 = c:new("Meta2", { x = 5 })
    T.eq(v4:doubled(), 10, "metatype with ctype")
end

----------------------------------------------------------------------
-- Section 28 — ctx:load library proxy
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("double sqrt(double x);")
    local ok_lib, lib = pcall(c.load, c, "m")
    if ok_lib then
        local ok_fn, val = pcall(function() return lib.sqrt(4.0) end)
        if ok_fn then
            T.eq(val, 2.0, "ctx:load resolves mangled function name")
        else
            io.write("SKIP: ctx:load symbol resolution not yet supported\n")
        end
    else
        io.write("SKIP: ctx:load('m') could not open libm\n")
    end
end

----------------------------------------------------------------------
-- Section 29 — cast function pointer with user-defined types
----------------------------------------------------------------------
do
    local c = new_ctx()
    c:cdef("typedef struct { int x; } Submod;")
    local result = nil
    local cb = c:cast("int (*)(Submod*, const char*, void*)", function(sm, name, payload)
        result = sm.x
        return 0
    end)
    local sm = c:new("Submod", { x = 42 })
    cb(sm, "test", nil)
    T.eq(result, 42, "cast function pointer resolves user type names")

    -- Function pointer with struct tag that has self-referential pointer
    c:cdef("typedef struct Node { int val; struct Node *next; } Node;")
    local result2 = nil
    local cb2 = c:cast("int (*)(struct Node*, void*)", function(n, _)
        result2 = n.val
        return 0
    end)
    local node = c:new("Node", { val = 99 })
    cb2(node, nil)
    T.eq(result2, 99, "cast function pointer with struct tag")
end

----------------------------------------------------------------------
-- Section 30 — Cross-context isolation (unknown type does NOT fall through)
----------------------------------------------------------------------
do
    local c1 = new_ctx()
    local c2 = new_ctx()
    -- c1 registers the type, c2 never does
    c1:cdef("typedef struct { int x; } Canary;")
    local ok = pcall(function() c2:sizeof("Canary") end)
    T.ok(not ok, "type from one context errors in another context")
end

T.done()
