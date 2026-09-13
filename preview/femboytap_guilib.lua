local M = {}
M.VERSION = "1.0"

local T = {
    x = 360, y = 200, w = 600, h = 440,

    accent    = { 139, 124, 246 },
    accent_bg = { 40, 36, 64, 255 },
    bg        = { 20, 20, 26, 255 },
    bg2       = { 15, 15, 20, 255 },
    section   = { 25, 25, 32, 255 },
    border    = { 44, 44, 56, 255 },
    divider   = { 36, 36, 46, 255 },
    text      = { 188, 188, 198, 255 },
    textdim   = { 112, 112, 126, 255 },
    texthi    = { 240, 240, 245, 255 },
    widget    = { 33, 33, 42, 255 },
    widgethi  = { 45, 45, 57, 255 },

    title     = "FEMBOYTAP",
    title_tld = ".CC",
    titlebar  = 44,
    pad       = 14,
    sec_gap   = 12,

    font      = { "Oxanium", "Space Grotesk", "Varela Round", "Tahoma", "Verdana" },
    font_logo = { "Space Grotesk", "Oxanium", "Tahoma" },
    font_size = 14,

    notif_pos    = "bottom-right",
    notif_w      = 290,
    notif_margin = 18,
    notif_life   = 3.5,
    notif_info    = { 139, 124, 246 },
    notif_success = { 80, 200, 120 },
    notif_error   = { 235, 90, 90 },
}

local WH = { check = 28, button = 36, slider = 36, combo = 52, multicombo = 52, input = 52, color = 28 }
local function wheight(wd)
    if wd.kind == "listbox" then
        return ((wd.label and wd.label ~= "") and 18 or 0) + wd.h + 6
    end
    if wd.kind == "custom" then return wd._measured or wd.h end
    return WH[wd.kind] or 28
end

local ANIM = { open = 13, tab = 17 }

local floor, sqrt, mmin, mmax, mabs = math.floor, math.sqrt, math.min, math.max, math.abs
local function rnd(n) return floor(n + 0.5) end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function smooth(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end

local function decimalsOf(step)
    if not step or step >= 1 then return 0 end
    local d, s = 0, step
    while s < 1 and d < 6 do
        s = s * 10; d = d + 1
        if mabs(s - floor(s + 0.5)) < 1e-7 then break end
    end
    return d
end

local ALPHA = 1
local DT = 0
local clipTop, clipBottom

local function approach(cur, target, speed)
    return cur + (target - cur) * clamp(DT * speed, 0, 1)
end

local function lerpc(a, b, t)
    t = clamp(t, 0, 1)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        (a[4] or 255) + ((b[4] or 255) - (a[4] or 255)) * t,
    }
end

local ffi = ffi
local FONT_URLS = {
    { file = "femboytap_Oxanium.ttf",      url = "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/oxanium/Oxanium%5Bwght%5D.ttf" },
    { file = "femboytap_Orbitron.ttf",     url = "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/orbitron/Orbitron%5Bwght%5D.ttf" },
    { file = "femboytap_SpaceGrotesk.ttf", url = "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf" },
}

local FONT, FONT_B, FONT_LOGO
local function initFonts()
    local mk = function(list, size, weight)
        for _, name in ipairs(list) do
            local f
            pcall(function() f = draw.CreateFont(name, size, weight) end)
            if not f then pcall(function() f = draw.AddFont(name, size, weight) end) end
            if f then return f, name end
        end
    end
    local picked
    FONT,      picked = mk(T.font, T.font_size, 400)
    FONT_B            = mk(T.font, T.font_size, 600)
    FONT_LOGO         = mk(T.font_logo, T.font_size + 2, 700) or FONT_B
    print("[femboytap] font: " .. tostring(picked))
end

local function fontInitCoro()
    coroutine.yield()

    pcall(function()
        ffi.cdef[[
            unsigned long GetCurrentDirectoryA(unsigned long, char*);
            unsigned long GetFileAttributesA(const char*);
            int CreateDirectoryA(const char*, void*);
            int AddFontResourceExA(const char*, unsigned long, void*);
            long URLDownloadToFileA(void*, const char*, const char*, unsigned long, void*);
        ]]
    end)
    local gdi32, urlmon
    pcall(function() gdi32  = ffi.load("gdi32") end)
    pcall(function() urlmon = ffi.load("urlmon") end)

    local dir = "."
    pcall(function()
        local buf = ffi.new("char[600]")
        local n = ffi.C.GetCurrentDirectoryA(600, buf)
        if n and n > 0 then dir = ffi.string(buf, n) end
    end)
    dir = dir .. "\\femboytap_lua"
    pcall(function() ffi.C.CreateDirectoryA(dir, nil) end)
    M._dir = dir
    coroutine.yield()

    if gdi32 then
        for _, f in ipairs(FONT_URLS) do
            local path = dir .. "\\" .. f.file
            local exists = false
            pcall(function() exists = ffi.C.GetFileAttributesA(path) ~= 0xFFFFFFFF end)
            if not exists and urlmon then
                pcall(function() urlmon.URLDownloadToFileA(nil, f.url, path, 0, nil) end)
            end
            pcall(function() gdi32.AddFontResourceExA(path, 0x10, nil) end)
            coroutine.yield()
        end
    else
        print("[femboytap] ffi/gdi32 unavailable, using system fonts")
    end

    initFonts()
end

local function setcol(c) draw.Color(c[1], c[2], c[3], rnd((c[4] or 255) * ALPHA)) end

local function rect(x, y, w, h, c)
    setcol(c); draw.FilledRect(rnd(x), rnd(y), rnd(x + w), rnd(y + h))
end

local function rfill(x, y, w, h, r, c, tl, tr, br, bl)
    x, y, w, h = rnd(x), rnd(y), rnd(w), rnd(h)
    r = mmin(r, floor(w / 2), floor(h / 2))
    if r <= 0 then rect(x, y, w, h, c); return end
    if tl == nil then tl, tr, br, bl = true, true, true, true end
    rect(x, y + r, w, h - 2 * r, c)
    for dy = 0, r - 1 do
        local dx = r - floor(sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
        local lt, rt = tl and dx or 0, tr and dx or 0
        local lb, rb = bl and dx or 0, br and dx or 0
        rect(x + lt, y + dy, w - lt - rt, 1, c)
        rect(x + lb, y + h - 1 - dy, w - lb - rb, 1, c)
    end
end

local function rbox(x, y, w, h, r, fill, brd)
    rfill(x, y, w, h, r, brd)
    rfill(x + 1, y + 1, w - 2, h - 2, r - 1, fill)
end

local function frame(x, y, w, h, c)
    rect(x, y, w, 1, c); rect(x, y + h - 1, w, 1, c)
    rect(x, y, 1, h, c); rect(x + w - 1, y, 1, h, c)
end

local function rgb2hsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local mx, mn = mmax(r, g, b), mmin(r, g, b)
    local v, d = mx, mx - mn
    local s = mx == 0 and 0 or d / mx
    local h = 0
    if d ~= 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6; if h < 0 then h = h + 1 end
    end
    return h, s, v
end

local function hsv2rgb(h, s, v)
    local i = floor(h * 6) % 6
    local f = h * 6 - floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return rnd(r * 255), rnd(g * 255), rnd(b * 255)
end

local function textw(s) local w = draw.GetTextSize(s); return w or 0 end

local function text(x, y, c, s, font, align)
    if font then draw.SetFont(font) end
    if align == "center" then x = x - textw(s) / 2
    elseif align == "right" then x = x - textw(s) end
    setcol(c); draw.Text(rnd(x), rnd(y), s)
end

local _getMouse
local function resolveMouse()
    local cands = {
        function() local p = input.GetMousePos();    return p.x or p[1], p.y or p[2] end,
        function() local p = input.GetCursorPos();    return p.x or p[1], p.y or p[2] end,
        function() local x, y = input.GetMousePos();  return x, y end,
        function() local x, y = input.GetCursorPos(); return x, y end,
    }
    for _, f in ipairs(cands) do
        local ok, x, y = pcall(f)
        if ok and type(x) == "number" and type(y) == "number" then return f end
    end
end

local _clock
local function resolveClock()
    local cands = {
        function() return globals.RealTime() end,
        function() return globals.CurTime() end,
        function() return os.clock() end,
    }
    for _, f in ipairs(cands) do
        local ok, v = pcall(f)
        if ok and type(v) == "number" then return f end
    end
end
local function now() if _clock then local ok, v = pcall(_clock); if ok then return v end end return 0 end

local _getWheel
local function resolveWheel()
    local cands = {
        function() return input.GetMouseWheel() end,
        function() return input.GetMouseWheelDelta() end,
        function() return input.GetScrollDelta() end,
        function() return input.GetScroll() end,
    }
    for _, f in ipairs(cands) do
        local ok, v = pcall(f)
        if ok and type(v) == "number" then return f end
    end
end
local function readWheel() if _getWheel then local ok, v = pcall(_getWheel); if ok and type(v) == "number" then return v end end return 0 end

local SHIFT_DIGITS = { [0x30] = ")", [0x31] = "!", [0x32] = "@", [0x33] = "#", [0x34] = "$",
                       [0x35] = "%", [0x36] = "^", [0x37] = "&", [0x38] = "*", [0x39] = "(" }
local OEM = {
    [0xBA] = { ";", ":" }, [0xBB] = { "=", "+" }, [0xBC] = { ",", "<" }, [0xBD] = { "-", "_" },
    [0xBE] = { ".", ">" }, [0xBF] = { "/", "?" }, [0xC0] = { "`", "~" }, [0xDB] = { "[", "{" },
    [0xDC] = { "\\", "|" }, [0xDD] = { "]", "}" }, [0xDE] = { "'", '"' },
}
local function keyPressed(k) local v = false; pcall(function() v = input.IsButtonPressed(k) end); return v end
local function keyDown(k)    local v = false; pcall(function() v = input.IsButtonDown(k)  end); return v end

pcall(function() ffi.cdef[[
    int    OpenClipboard(void*);
    int    CloseClipboard(void);
    int    EmptyClipboard(void);
    void*  GetClipboardData(unsigned int);
    void*  SetClipboardData(unsigned int, void*);
    void*  GlobalAlloc(unsigned int, size_t);
    void*  GlobalLock(void*);
    int    GlobalUnlock(void*);
]] end)

local function clipGet()
    local out
    pcall(function()
        if ffi.C.OpenClipboard(nil) == 0 then return end
        local h = ffi.C.GetClipboardData(1)
        if h ~= nil then
            local p = ffi.C.GlobalLock(h)
            if p ~= nil then out = ffi.string(ffi.cast("char*", p)); ffi.C.GlobalUnlock(h) end
        end
        ffi.C.CloseClipboard()
    end)
    if out then out = out:gsub("[\r\n\t]", "") end
    return out
end

local function clipSet(s)
    s = tostring(s or "")
    pcall(function()
        if ffi.C.OpenClipboard(nil) == 0 then return end
        ffi.C.EmptyClipboard()
        local n = #s + 1
        local h = ffi.C.GlobalAlloc(2, n)
        if h ~= nil then
            local p = ffi.C.GlobalLock(h)
            if p ~= nil then
                local dst = ffi.cast("char*", p)
                for i = 0, n - 1 do dst[i] = (i < #s) and s:byte(i + 1) or 0 end
                ffi.C.GlobalUnlock(h)
                ffi.C.SetClipboardData(1, h)
            end
        end
        ffi.C.CloseClipboard()
    end)
end

local _kr = {}
local REPEAT_DELAY, REPEAT_RATE = 0.40, 0.035
local function keyRepeat(k, t)
    if not keyDown(k) then _kr[k] = nil; return false end
    local s = _kr[k]
    if not s then _kr[k] = { first = t, last = t }; return true end
    if (t - s.first) >= REPEAT_DELAY and (t - s.last) >= REPEAT_RATE then s.last = t; return true end
    return false
end

local function selBounds(wd)
    local c = wd._caret or #wd.value
    local a = wd._anchor or c
    if a > c then a, c = c, a end
    return a, c
end
local function hasSel(wd) return (wd._anchor or wd._caret or 0) ~= (wd._caret or 0) end
local function delSel(wd)
    local a, b = selBounds(wd)
    if a == b then return false end
    wd.value = wd.value:sub(1, a) .. wd.value:sub(b + 1)
    wd._caret = a; wd._anchor = a
    return true
end

local function inputView(wd, avail)
    local v, n = wd.value, #wd.value
    local caret = clamp(wd._caret or n, 0, n); wd._caret = caret
    if wd._anchor then wd._anchor = clamp(wd._anchor, 0, n) end
    local off = clamp(wd._off or 0, 0, n)
    if caret < off then off = caret end
    while off < caret and textw(v:sub(off + 1, caret)) > avail do off = off + 1 end
    local e = n
    while e > off and textw(v:sub(off + 1, e)) > avail do e = e - 1 end
    if e < caret then e = caret end
    wd._off = off
    return v:sub(off + 1, e), off, e
end

local function caretFromX(wd, relx, off)
    local v, n = wd.value, #wd.value
    if relx <= 0 then return off end
    for i = off + 1, n do
        local w = textw(v:sub(off + 1, i))
        if w >= relx then
            local wp = textw(v:sub(off + 1, i - 1))
            return ((relx - wp) < (w - relx)) and (i - 1) or i
        end
    end
    return n
end

local function pollText(wd, t)
    local ctrl  = keyDown(0x11)
    local shift = keyDown(0x10)
    local n = #wd.value
    wd._caret  = clamp(wd._caret or n, 0, n)
    wd._anchor = wd._anchor and clamp(wd._anchor, 0, n) or wd._caret

    if ctrl then
        if keyPressed(0x41) then wd._anchor = 0; wd._caret = n end
        if keyPressed(0x43) then local a, b = selBounds(wd); clipSet(a ~= b and wd.value:sub(a + 1, b) or wd.value) end
        if keyPressed(0x58) then
            local a, b = selBounds(wd)
            if a ~= b then clipSet(wd.value:sub(a + 1, b)); delSel(wd)
            else clipSet(wd.value); wd.value = ""; wd._caret = 0; wd._anchor = 0 end
        end
        if keyPressed(0x56) then
            local s = clipGet()
            if s then
                delSel(wd)
                local c = wd._caret
                wd.value = wd.value:sub(1, c) .. s .. wd.value:sub(c + 1)
                wd._caret = c + #s; wd._anchor = wd._caret
            end
        end
        return
    end

    local function move(to)
        wd._caret = clamp(to, 0, #wd.value)
        if not shift then wd._anchor = wd._caret end
    end
    local function ins(ch)
        delSel(wd)
        local c = wd._caret
        wd.value = wd.value:sub(1, c) .. ch .. wd.value:sub(c + 1)
        wd._caret = c + 1; wd._anchor = wd._caret
    end

    if keyRepeat(0x25, t) then
        local a, b = selBounds(wd)
        if not shift and a ~= b then wd._caret = a; wd._anchor = a else move(wd._caret - 1) end
    end
    if keyRepeat(0x27, t) then
        local a, b = selBounds(wd)
        if not shift and a ~= b then wd._caret = b; wd._anchor = b else move(wd._caret + 1) end
    end
    if keyPressed(0x24) then move(0) end
    if keyPressed(0x23) then move(#wd.value) end

    if keyRepeat(0x08, t) then
        if not delSel(wd) then
            local c = wd._caret
            if c > 0 then wd.value = wd.value:sub(1, c - 1) .. wd.value:sub(c + 1); wd._caret = c - 1; wd._anchor = c - 1 end
        end
    end
    if keyRepeat(0x2E, t) then
        if not delSel(wd) then
            local c = wd._caret
            if c < #wd.value then wd.value = wd.value:sub(1, c) .. wd.value:sub(c + 2) end
        end
    end

    if keyRepeat(0x20, t) then ins(" ") end
    for k = 0x41, 0x5A do
        if keyRepeat(k, t) then local ch = string.char(k); ins(shift and ch or ch:lower()) end
    end
    for k = 0x30, 0x39 do
        if keyRepeat(k, t) then ins(shift and SHIFT_DIGITS[k] or string.char(k)) end
    end
    for k, pair in pairs(OEM) do
        if keyRepeat(k, t) then ins(shift and pair[2] or pair[1]) end
    end
    if keyPressed(0x0D) or keyPressed(0x1B) then M._focus = nil end
end

local ms = { x = 0, y = 0, down = false, pressed = false, released = false, consumed = false }
local function updateMouse()
    if _getMouse then
        local ok, x, y = pcall(_getMouse)
        if ok then ms.x, ms.y = x or ms.x, y or ms.y end
    end
    local down = false
    pcall(function() down = input.IsButtonDown(0x01) and true or false end)
    ms.pressed  = down and not ms.down
    ms.released = (not down) and ms.down
    ms.down     = down
    ms.consumed = false
    ms.wheel    = readWheel()
end

local function hovering(x, y, w, h)
    return ms.x >= x and ms.x <= x + w and ms.y >= y and ms.y <= y + h
end

local function clicked(x, y, w, h)
    if ms.consumed or not ms.pressed then return false end
    if hovering(x, y, w, h) then ms.consumed = true; return true end
    return false
end

local function handle(w)
    return {
        Get = function() return w.value end,
        Set = function(_, v) w.value = v end,
    }
end

local UI = {
    T = T, now = now, clamp = clamp, lerp = lerpc,
    rect  = function(x, y, w, h, c) rect(x, y, w, h, c) end,
    rfill = function(x, y, w, h, r, c) rfill(x, y, w, h, r, c) end,
    rbox  = function(x, y, w, h, r, f, b) rbox(x, y, w, h, r, f, b or T.border) end,
    text  = function(x, y, s, col, align) text(x, y, col or T.text, tostring(s), FONT, align) end,
    title = function(x, y, s, col, align) text(x, y, col or T.texthi, tostring(s), FONT_B, align) end,
    textw = function(s) return textw(tostring(s)) end,
    hover = function(x, y, w, h) return hovering(x, y, w, h) end,
    click = function(x, y, w, h) return clicked(x, y, w, h) end,
    mouse = function() return ms.x, ms.y, ms.down end,
    screen = function() local w, h = 0, 0; pcall(function() w, h = draw.GetScreenSize() end); return w, h end,
}

local IM = {}
UI._x, UI._cy, UI._w = 0, 0, 200
UI.layout = function(x, y, w) UI._x = x; UI._cy = y; if w then UI._w = w end end

local Section = {}
Section.__index = Section

function Section.new(title) return setmetatable({ title = title, ws = {} }, Section) end

function Section:_add(w) self.ws[#self.ws + 1] = w; return handle(w) end

function Section:Checkbox(label, def)
    return self:_add({ kind = "check", label = label, value = def and true or false })
end

function Section:Button(label, cb)
    return self:_add({ kind = "button", label = label, cb = cb })
end

function Section:Slider(label, def, mn, mx, step, fmt)
    step = step or 1
    return self:_add({ kind = "slider", label = label, value = def, min = mn, max = mx,
                       step = step, dec = decimalsOf(step), fmt = fmt })
end

function Section:SliderFloat(label, def, mn, mx, fmt, step)
    return self:Slider(label, def, mn, mx, step or 0.01, fmt)
end

function Section:Combo(label, options, def)
    return self:_add({ kind = "combo", label = label, options = options, value = def or 1 })
end

function Section:MultiCombo(label, options, defaults)
    local sel = {}
    if defaults then for _, i in ipairs(defaults) do sel[i] = true end end
    return self:_add({ kind = "multicombo", label = label, options = options, value = sel })
end

function Section:Input(label, def, placeholder)
    return self:_add({ kind = "input", label = label, value = def or "", placeholder = placeholder })
end

function Section:ColorPicker(label, col)
    col = col or { 255, 255, 255, 255 }
    return self:_add({ kind = "color", label = label, value = { col[1], col[2], col[3], col[4] or 255 } })
end

function Section:Listbox(label, items, height, def)
    local fill = (height == "fill")
    if fill then self._hasFill = true end
    return self:_add({ kind = "listbox", label = label, items = items or {}, value = def or 1,
                       h = fill and 120 or (height or 200), fill = fill, scroll = 0 })
end

function Section:Custom(height, fn)
    return self:_add({ kind = "custom", h = height or 60, fn = fn })
end

function Section:height()
    local h = 42 + 10
    for _, wd in ipairs(self.ws) do h = h + wheight(wd) end
    return h
end

function Section:render(x, y, w)
    -- Layout height: explicit row stretch (_layoutH), else natural.
    -- Fill-to-window only when NOT in a measured row (auto-pack),
    -- so Row() siblings cannot inflate and push later panels off-screen.
    local natural = self:height()
    local h = natural
    if self._layoutH then
        h = mmax(natural, self._layoutH)
    elseif self._hasFill and clipBottom then
        local fh = (clipBottom - 12) - y
        if fh > h then h = fh end
    end

    if clipBottom and y >= clipBottom then return h end
    if clipTop and (y + h) <= clipTop then return h end

    local boxH = h
    if clipBottom and (y + boxH) > clipBottom then
        boxH = mmax(0, clipBottom - y)
    end
    if boxH > 0 and (not clipTop or y + boxH > clipTop) then
        local drawY = y
        local drawH = boxH
        if clipTop and drawY < clipTop then
            drawH = drawH - (clipTop - drawY)
            drawY = clipTop
        end
        if drawH > 0 then
            rbox(x, drawY, w, drawH, 6, T.section, T.border)
        end
        if (not clipTop or y + 26 > clipTop) and (not clipBottom or y + 12 < clipBottom) then
            rfill(x + 14, y + 12, 3, 14, 1, T.accent)
            text(x + 23, y + 12, T.texthi, self.title, FONT_B)
            if (not clipBottom or y + 33 < clipBottom) and (not clipTop or y + 34 > clipTop) then
                rect(x + 14, y + 33, w - 28, 1, T.divider)
            end
        end
    end

    local iy = y + 44
    local ix = x + 14
    local iw = w - 28
    for _, wd in ipairs(self.ws) do
        local wh
        if wd.kind == "listbox" and wd.fill then
            local labelH = (wd.label and wd.label ~= "") and 18 or 0
            local remain = (y + h - 12) - (iy + labelH)
            wd._fillH = mmax(wd.h or 120, remain)
            wh = labelH + wd._fillH + 6
        else
            wh = wheight(wd)
        end
        local visible = true
        if clipBottom and iy >= clipBottom then visible = false end
        if clipTop and (iy + wh) <= clipTop then visible = false end
        if visible then
            self:_widget(wd, ix, iy, iw)
        end
        iy = iy + wh
        if clipBottom and iy >= clipBottom then break end
    end
    return h
end

function Section:_widget(wd, x, y, w)
    if wd.kind == "check" then
        local box = 15
        local by  = y + 1
        local hov = hovering(x, by, w, box)
        wd._h  = approach(wd._h or 0, hov and 1 or 0, 16)
        wd._on = approach(wd._on or 0, wd.value and 1 or 0, 16)
        local fill = lerpc(lerpc(T.widget, T.widgethi, wd._h), T.accent, wd._on)
        rbox(x, by, box, box, 4, fill, lerpc(T.border, T.accent, wd._on))
        text(x + box + 9, y + 2, lerpc(T.text, T.texthi, mmax(wd._h, wd._on)), wd.label, FONT)
        if clicked(x, by, w, box) then wd.value = not wd.value end

    elseif wd.kind == "button" then
        local bh  = 22
        local hov = hovering(x, y + 1, w, bh)
        wd._h = approach(wd._h or 0, hov and 1 or 0, 16)
        rbox(x, y + 1, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), T.border)
        text(x + w / 2, y + 6, lerpc(T.text, T.texthi, wd._h), wd.label, FONT, "center")
        if clicked(x, y + 1, w, bh) then
            local ok, err = pcall(wd.cb); if not ok then print("[femboytap] button error: " .. tostring(err)) end
        end

    elseif wd.kind == "slider" then
        local active = (M._slider == wd)
        wd._h = approach(wd._h or 0, (active or hovering(x, y + 18 - 6, w, 18)) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        local valstr
        if wd.fmt then valstr = string.format(wd.fmt, wd.value)
        elseif wd.dec > 0 then valstr = string.format("%." .. wd.dec .. "f", wd.value)
        else valstr = tostring(rnd(wd.value)) end
        text(x + w, y, T.texthi, valstr, FONT, "right")
        local ty, th = y + 18, 6
        local frac = clamp((wd.value - wd.min) / (wd.max - wd.min), 0, 1)
        rbox(x, ty, w, th, 3, lerpc(T.widget, T.widgethi, wd._h), T.border)
        if frac > 0 then rfill(x, ty, mmax(th, w * frac), th, 3, T.accent, true, false, false, true) end
        if ms.pressed and not ms.consumed and hovering(x, ty - 6, w, th + 12) then
            ms.consumed = true; M._slider = wd
        end
        if active then
            if ms.down and w > 0 then
                local raw = wd.min + clamp((ms.x - x) / w, 0, 1) * (wd.max - wd.min)
                if raw ~= raw then raw = wd.min end
                local v = wd.min + floor((raw - wd.min) / wd.step + 0.5) * wd.step
                v = clamp(v, wd.min, wd.max)
                if wd.dec > 0 then v = tonumber(string.format("%." .. wd.dec .. "f", v)) or v end
                wd.value = v
            elseif not ms.down then
                M._slider = nil
            end
        end

    elseif wd.kind == "combo" then
        local by, bh = y + 18, 22
        local open = (M._combo == wd)
        local hov  = hovering(x, by, w, bh)
        wd._h = approach(wd._h or 0, (hov or open) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        rbox(x, by, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), open and T.accent or T.border)
        text(x + 9, by + 5, open and T.texthi or lerpc(T.text, T.texthi, wd._h), wd.options[wd.value] or "?", FONT)
        text(x + w - 16, by + 5, open and T.accent or T.textdim, open and "-" or "v", FONT)
        if clicked(x, by, w, bh) then M._combo = open and nil or wd end
        if M._combo == wd then M._dd = { wd = wd, x = x, y = by + bh, w = w, bh = bh } end

    elseif wd.kind == "multicombo" then
        local by, bh = y + 18, 22
        local open = (M._combo == wd)
        local hov  = hovering(x, by, w, bh)
        wd._h = approach(wd._h or 0, (hov or open) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        rbox(x, by, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), open and T.accent or T.border)
        local parts, count = {}, 0
        for i, o in ipairs(wd.options) do if wd.value[i] then count = count + 1; parts[#parts + 1] = o end end
        local shown = count == 0 and "None" or (count > 2 and (count .. " selected") or table.concat(parts, ", "))
        text(x + 9, by + 5, open and T.texthi or lerpc(T.text, T.texthi, wd._h), shown, FONT)
        text(x + w - 16, by + 5, open and T.accent or T.textdim, open and "-" or "v", FONT)
        if clicked(x, by, w, bh) then M._combo = open and nil or wd end
        if M._combo == wd then M._dd = { wd = wd, x = x, y = by + bh, w = w, bh = bh } end

    elseif wd.kind == "input" then
        local by, bh = y + 18, 22
        local focused = (M._focus == wd)
        local hov = hovering(x, by, w, bh)
        wd._h = approach(wd._h or 0, (hov or focused) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        rbox(x, by, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), focused and T.accent or T.border)
        local pad, avail = 9, w - 16
        local tx, ty = x + pad, by + 5
        if wd.value ~= "" or focused then
            local vis, off = inputView(wd, avail)
            if focused then
                local a, b = selBounds(wd)
                if a ~= b then
                    local va, vb = clamp(a, off, off + #vis), clamp(b, off, off + #vis)
                    local sx = textw(wd.value:sub(off + 1, va))
                    local sw = textw(wd.value:sub(off + 1, vb)) - sx
                    if sw > 0 then rfill(tx + sx - 1, by + 4, mmin(sw + 2, avail), bh - 8, 3, { T.accent[1], T.accent[2], T.accent[3], 110 }) end
                end
            end
            text(tx, ty, focused and T.texthi or T.text, vis, FONT)
            if focused and not hasSel(wd) and (floor(now() * 1.6) % 2 == 0) then
                rfill(tx + textw(wd.value:sub(off + 1, wd._caret)), by + 4, 1, bh - 8, 0, T.accent)
            end
        else
            text(tx, ty, T.textdim, wd.placeholder or "", FONT)
        end
        if ms.pressed and not ms.consumed and hovering(x, by, w, bh) then
            ms.consumed = true; M._focus = wd
            local c = caretFromX(wd, ms.x - tx, wd._off or 0)
            wd._caret, wd._anchor, M._inputDrag = c, c, wd
        end
        if M._inputDrag == wd then
            if ms.down and M._focus == wd then wd._caret = caretFromX(wd, ms.x - tx, wd._off or 0)
            else M._inputDrag = nil end
        end
        if focused then pollText(wd, now()) end

    elseif wd.kind == "color" then
        local hov = hovering(x, y, w, 20)
        wd._h = approach(wd._h or 0, hov and 1 or 0, 16)
        text(x, y + 4, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        local sw, shh = 32, 14
        local bx, by = x + w - sw, y + 3
        rbox(bx, by, sw, shh, 3, { wd.value[1], wd.value[2], wd.value[3], 255 }, (M._cp == wd) and T.accent or T.border)
        if clicked(bx, by, sw, shh) then
            if M._cp == wd then M._cp = nil
            else M._cp = wd; wd._hsv = { rgb2hsv(wd.value[1], wd.value[2], wd.value[3]) } end
        end
        if M._cp == wd then
            M._cpRect = { x = x, y = y + 24, sx = bx, sy = by, sw = sw, sh = shh }
        end

    elseif wd.kind == "listbox" then
        local ly = y
        if wd.label and wd.label ~= "" then text(x, y, T.text, wd.label, FONT); ly = y + 18 end
        local lh, itemH = (wd._fillH or wd.h), 20
        rbox(x, ly, w, lh, 5, T.bg2, T.border)
        local n = #wd.items
        local visible = floor(lh / itemH)
        local maxScroll = mmax(0, n - visible)
        if (ms.wheel or 0) ~= 0 and hovering(x, ly, w, lh) then
            wd.scroll = wd.scroll - (ms.wheel > 0 and 1 or -1)
            ms.wheel = 0
        end
        wd.scroll = clamp(wd.scroll, 0, maxScroll)
        local hasBar = n > visible
        local listW = hasBar and (w - 9) or w
        for vi = 0, visible - 1 do
            local idx = vi + 1 + floor(wd.scroll)
            if idx <= n then
                local iy = ly + vi * itemH
                local sel = (idx == wd.value)
                local hov = hovering(x + 2, iy, listW - 4, itemH)
                if sel then
                    rfill(x + 3, iy + 1, listW - 6, itemH - 2, 3, T.accent_bg)
                    rfill(x + 3, iy + 1, 2, itemH - 2, 1, T.accent)
                elseif hov then
                    rfill(x + 3, iy + 1, listW - 6, itemH - 2, 3, T.widget)
                end
                text(x + 11, iy + 3, (sel or hov) and T.texthi or T.text, tostring(wd.items[idx]), FONT)
                if clicked(x + 2, iy, listW - 4, itemH) then wd.value = idx end
            end
        end
        if hasBar then
            local trackX = x + w - 6
            local thumbH = mmax(20, lh * visible / n)
            local thumbY = ly + (lh - thumbH) * (maxScroll > 0 and wd.scroll / maxScroll or 0)
            rfill(trackX, ly + 2, 4, lh - 4, 2, T.widget)
            rfill(trackX, thumbY, 4, thumbH, 2, T.widgethi)
            if ms.pressed and not ms.consumed and hovering(trackX - 2, ly, 8, lh) then
                ms.consumed = true; M._scrollbar = wd
            end
            if M._scrollbar == wd then
                if ms.down then wd.scroll = rnd(clamp((ms.y - ly) / lh, 0, 1) * maxScroll)
                else M._scrollbar = nil end
            end
        end

    elseif wd.kind == "custom" then
        if wd.fn then
            UI._x, UI._cy, UI._w = x, y, w
            local ok, err = pcall(wd.fn, UI, x, y, w)
            if not ok then print("[femboytap] custom widget error: " .. tostring(err)) end
            local used = UI._cy - y
            wd._measured = used > 0 and used or wd.h
        end
    end
end

local function imWidget(id, factory)
    local wd = IM[id]
    if not wd then wd = factory(); IM[id] = wd end
    return wd
end
local function imEmit(wd)
    Section._widget(Section, wd, UI._x, UI._cy, UI._w)
    UI._cy = UI._cy + wheight(wd)
end

function UI.checkbox(id, def)
    local wd = imWidget(id, function() return { kind = "check", label = id, value = def and true or false } end)
    imEmit(wd); return wd.value
end
function UI.slider(id, def, mn, mx, step, fmt)
    local wd = imWidget(id, function() local s = step or 1
        return { kind = "slider", label = id, value = def, min = mn, max = mx, step = s, dec = decimalsOf(s), fmt = fmt } end)
    wd.min, wd.max = mn, mx
    imEmit(wd); return wd.value
end
function UI.combo(id, options, def)
    local wd = imWidget(id, function() return { kind = "combo", label = id, options = options, value = def or 1 } end)
    wd.options = options
    imEmit(wd); return wd.value
end
function UI.button(id)
    local wd = imWidget(id, function() return { kind = "button", label = id } end)
    wd._clicked = false
    wd.cb = function() wd._clicked = true end
    imEmit(wd); return wd._clicked
end
function UI.colorpicker(id, def)
    local wd = imWidget(id, function() local c = def or { 255, 255, 255, 255 }
        return { kind = "color", label = id, value = { c[1], c[2], c[3], c[4] or 255 } } end)
    imEmit(wd); return wd.value
end
function UI.label(s, col)
    text(UI._x, UI._cy, col or T.text, tostring(s), FONT); UI._cy = UI._cy + 18
end

local function renderSectionAt(s, x, y, w)
    local h = 40
    pcall(function() h = s:height() end)
    if s._layoutH then h = mmax(h, s._layoutH) end
    if clipBottom and y >= clipBottom then return h end
    if clipTop and (y + h) <= clipTop then return h end
    local rh = h
    local ok, err = pcall(function() rh = s:render(x, y, w) or h end)
    if not ok then print("[femboytap] section '" .. tostring(s.title) .. "' error: " .. tostring(err)); return h end
    return rh
end

local function renderAutoPack(secs, x, y, w, cols)
    cols = cols or 2
    local colW = (w - (cols - 1) * T.pad) / cols
    local colY, colX = {}, {}
    for c = 1, cols do colY[c] = y; colX[c] = x + (c - 1) * (colW + T.pad) end
    for _, s in ipairs(secs) do
        local best = 1
        for c = 2, cols do if colY[c] < colY[best] then best = c end end
        colY[best] = colY[best] + renderSectionAt(s, colX[best], colY[best], colW) + T.sec_gap
    end
end

local function renderRows(rows, x, y, w)
    local cy = y
    for _, row in ipairs(rows) do
        local n = #row
        if n > 0 then
            local gap = 8
            local colW = (w - (n - 1) * gap) / n
            -- Pass 1: natural heights per column
            local colH = {}
            local rowH = 0
            for ci, col in ipairs(row) do
                local h = 0
                for _, s in ipairs(col) do
                    s._layoutH = nil
                    local sh = 40
                    pcall(function() sh = s:height() end)
                    h = h + sh + T.sec_gap
                end
                colH[ci] = h
                if h > rowH then rowH = h end
            end
            -- Pass 2: stretch fill sections to row height, then render
            for ci, col in ipairs(row) do
                local cxx = x + (ci - 1) * (colW + gap)
                local yy = cy
                local stretch = rowH - colH[ci]
                if stretch > 0 then
                    for _, s in ipairs(col) do
                        if s._hasFill then
                            local sh = 40
                            pcall(function() sh = s:height() end)
                            s._layoutH = sh + stretch
                            break
                        end
                    end
                end
                for _, s in ipairs(col) do
                    yy = yy + renderSectionAt(s, cxx, yy, colW) + T.sec_gap
                    s._layoutH = nil
                end
            end
            cy = cy + rowH
        end
    end
end

local function renderContainer(cont, x, y, w)
    if cont._rows and #cont._rows > 0 then renderRows(cont._rows, x, y, w)
    else renderAutoPack(cont.secs, x, y, w, cont._cols) end
end

local function measureSecs(secs)
    local total = 0
    for _, s in ipairs(secs) do local h = 40; pcall(function() h = s:height() end); total = total + h + T.sec_gap end
    return total
end

local function containerHeight(cont)
    if cont._rows and #cont._rows > 0 then
        local total = 0
        for _, row in ipairs(cont._rows) do
            local rowH = 0
            for _, col in ipairs(row) do local h = measureSecs(col); if h > rowH then rowH = h end end
            total = total + rowH
        end
        return total
    end
    local cols = cont._cols or 2
    local colY = {}
    for c = 1, cols do colY[c] = 0 end
    for _, s in ipairs(cont.secs) do
        local best = 1
        for c = 2, cols do if colY[c] < colY[best] then best = c end end
        local h = 40; pcall(function() h = s:height() end)
        colY[best] = colY[best] + h + T.sec_gap
    end
    local mx = 0
    for c = 1, cols do if colY[c] > mx then mx = colY[c] end end
    return mx
end

local function tabContentHeight(tab)
    if #tab.subs == 0 then return containerHeight(tab) end
    local sub = tab.subs[tab._activeSub]
    return 28 + T.sec_gap + (sub and containerHeight(sub) or 0)
end

local function addSection(cont, title)
    local s = Section.new(title)
    if cont._rows and #cont._rows > 0 then
        local row = cont._rows[#cont._rows]
        local col = row[#row]
        col[#col + 1] = s
    else
        cont.secs[#cont.secs + 1] = s
    end
    return s
end
local function contRow(cont) cont._rows[#cont._rows + 1] = { {} }; return cont end
local function contCol(cont)
    if #cont._rows == 0 then cont._rows[#cont._rows + 1] = { {} } end
    local row = cont._rows[#cont._rows]
    row[#row + 1] = {}
    return cont
end

local Sub = {}
Sub.__index = Sub
function Sub.new(name) return setmetatable({ name = name, secs = {}, _rows = {} }, Sub) end
function Sub:Section(title) return addSection(self, title) end
function Sub:Row() return contRow(self) end
function Sub:Col() return contCol(self) end
function Sub:Columns(n) self._cols = n; return self end

local Tab = {}
Tab.__index = Tab

function Tab.new(name)
    return setmetatable({ name = name, secs = {}, subs = {}, _rows = {}, _activeSub = 1, _subT = 1 }, Tab)
end

function Tab:Section(title) return addSection(self, title) end
function Tab:Row() return contRow(self) end
function Tab:Col() return contCol(self) end
function Tab:Columns(n) self._cols = n; return self end

function Tab:Sub(name)
    local s = Sub.new(name)
    self.subs[#self.subs + 1] = s
    return s
end

function Tab:render(x, y, w)
    if #self.subs == 0 then
        renderContainer(self, x, y, w)
        return
    end

    local barH = 28
    local sx = x
    local pos, tgtX, tgtW = {}, x, 0
    for i, sub in ipairs(self.subs) do
        local tw = textw(sub.name) + 24
        pos[i] = { x = sx, w = tw }
        if i == self._activeSub then tgtX, tgtW = sx, tw end
        sx = sx + tw
    end

    local relX = tgtX - x
    self._subX = approach(self._subX or relX, relX, 16)
    self._subW = approach(self._subW or tgtW, tgtW, 16)
    rfill(x + self._subX + 6, y + barH - 6, self._subW - 12, 2, 1, T.accent)

    for i, sub in ipairs(self.subs) do
        local p = pos[i]
        local active = (i == self._activeSub)
        local hov = hovering(p.x, y, p.w, barH)
        sub._h = approach(sub._h or 0, (active or hov) and 1 or 0, 16)
        text(p.x + p.w / 2, y + 6, lerpc(T.textdim, T.texthi, sub._h), sub.name, FONT, "center")
        if clicked(p.x, y, p.w, barH) and self._activeSub ~= i then self._activeSub = i; self._subT = 0 end
    end
    rect(x, y + barH, w, 1, T.divider)

    self._subT = self._subT + (1 - self._subT) * clamp(DT * ANIM.tab, 0, 1)
    local e = smooth(self._subT)
    local sub = self.subs[self._activeSub]
    if sub then renderContainer(sub, x + (1 - e) * 16, y + barH + T.sec_gap, w) end
end

M._tabs   = {}
M._active = 1
M._win    = { x = T.x, y = T.y, w = T.w, h = T.h }
M._t      = 0
M._tabT   = 1
M._last   = nil
M._toasts = {}
M._notifPos = T.notif_pos
M._onframe = {}

M._hitlog = {
    queue     = {},
    enabled   = true,
    pos       = nil,
    x_off     = 0,
    y_off     = nil,
    font_size = T.font_size,
    life      = 2.8,
    fade_in   = 0.16,
    fade_out  = 0.40,
    max       = 6,
    colors    = {
        miss = { 235, 90, 90 },
        hit  = { 139, 124, 246 },
        hurt = { 245, 170, 70 },
        kill = { 80, 200, 120 },
    },
}

M._watermark = {
    enabled    = false,
    parts      = { cheat = false, lua = true, user = false, nick = true, fps = true, ping = true },
    cheat_name = "AIMWARE.NET",
    lua_name   = "FEMBOYTAP.CC",
    user       = nil,
    nick       = nil,
    ping       = nil,
    pos        = "top-right",
    _fps       = 0,
    _killTry   = -1,
}

local WM_MISC_KEYS = { "misc.watermark", "misc.watermark.enable", "misc.indicators.watermark" }

function M:Watermark(on) self._watermark.enabled = on and true or false; return self end

function M:WatermarkSet(opts)
    local wm = self._watermark
    if opts.enabled    ~= nil then wm.enabled = opts.enabled and true or false end
    if opts.cheat_name ~= nil then wm.cheat_name = opts.cheat_name end
    if opts.lua_name   ~= nil then wm.lua_name = opts.lua_name end
    if opts.user       ~= nil then wm.user = opts.user end
    if opts.nick       ~= nil then wm.nick = opts.nick end
    if opts.ping       ~= nil then wm.ping = opts.ping end
    if opts.pos        ~= nil then wm.pos = opts.pos end
    if opts.parts then
        for k, v in pairs(opts.parts) do wm.parts[k] = v and true or false end
    end
    return self
end

function M:OnFrame(fn) self._onframe[#self._onframe + 1] = fn; return self end

function M:Tab(name)
    local t = Tab.new(name)
    self._tabs[#self._tabs + 1] = t
    return t
end

local function smoother(x) x = clamp(x, 0, 1); return x * x * x * (x * (x * 6 - 15) + 10) end

function M:Notify(text, kind)
    self._toasts[#self._toasts + 1] = { text = tostring(text), kind = kind or "info", born = now(), life = T.notif_life }
    while #self._toasts > 6 do table.remove(self._toasts, 1) end
end
function M:Info(t)    self:Notify(t, "info")    end
function M:Success(t) self:Notify(t, "success") end
function M:Error(t)   self:Notify(t, "error")   end

function M:SetNotifPos(p) self._notifPos = p end
function M:GetNotifPos() return self._notifPos end

local HITLOG_TEXT = { miss = "missed", hit = "hit", hurt = "hurt", kill = "killed enemy" }

local function hitlogLabel(e)
    if e.text and e.text ~= "" then return e.text end
    local base = HITLOG_TEXT[e.kind] or e.kind
    if e.dmg then return base .. "  " .. tostring(e.dmg) end
    return base
end

function M:Hitlog(kind, dmg, txt)
    local hl = self._hitlog
    hl.queue[#hl.queue + 1] = {
        kind = tostring(kind or "hit"):lower(),
        dmg  = dmg, text = txt, born = now(),
    }
    while #hl.queue > (hl.max or 6) do table.remove(hl.queue, 1) end
    return self
end

function M:HitlogSet(opts)
    local hl = self._hitlog
    if opts.enabled   ~= nil then hl.enabled   = opts.enabled   end
    if opts.pos       ~= nil then hl.pos       = opts.pos       end
    if opts.x_off     ~= nil then hl.x_off     = opts.x_off     end
    if opts.y_off     ~= nil then hl.y_off     = opts.y_off     end
    if opts.font_size        then hl.font_size = opts.font_size end
    if opts.life             then hl.life      = opts.life      end
    if opts.colors then
        for k, v in pairs(opts.colors) do if v then hl.colors[tostring(k):lower()] = v end end
    end
    return self
end

function M:HitlogPos() return self._hitlog.x_off or 0, self._hitlog.y_off end
function M:HitlogResetPos() self._hitlog.x_off, self._hitlog.y_off = 0, nil; return self end

function M:HitlogColor(kind, col)
    if col then self._hitlog.colors[tostring(kind):lower()] = col end
    return self
end

function M:HitlogClear() self._hitlog.queue = {}; return self end

function M:_drawToasts()
    local toasts = self._toasts
    if #toasts == 0 then return end

    local SLIDE_IN, SLIDE_OUT, SLIDE_DIST, GAP = 0.32, 0.45, 24, 8
    local W, M_OFF = T.notif_w, T.notif_margin
    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end

    local pos   = self._notifPos
    local right = pos:find("right") ~= nil
    local top   = pos:find("top") ~= nil
    local x0    = right and (sw - M_OFF - W) or M_OFF

    local i = 1
    while i <= #toasts do
        if (now() - toasts[i].born) >= toasts[i].life + SLIDE_OUT + 0.05 then table.remove(toasts, i)
        else i = i + 1 end
    end

    local y = top and M_OFF or (sh - M_OFF)

    local order = {}
    if top then for k = 1, #toasts do order[#order + 1] = k end
    else for k = #toasts, 1, -1 do order[#order + 1] = k end end

    for _, k in ipairs(order) do
        local tw = toasts[k]
        local age = now() - tw.born
        local inE  = smoother(clamp(age / SLIDE_IN, 0, 1))
        local outE = smoother(clamp((age - tw.life) / SLIDE_OUT, 0, 1))
        local dx   = (1 - inE) * SLIDE_DIST + outE * SLIDE_DIST
        local a    = inE * (1 - outE)
        local h    = 46

        local bx = right and (x0 + dx) or (x0 - dx)
        local by = top and y or (y - h)

        ALPHA = a
        local kc = (tw.kind == "success" and T.notif_success) or (tw.kind == "error" and T.notif_error) or T.notif_info
        rbox(bx, by, W, h, 8, T.section, T.border)
        rfill(bx, by, 3, h, 3, kc, true, false, false, true)
        text(bx + 14, by + 9, T.texthi, tw.text, FONT)

        local prog = 1 - clamp(age / tw.life, 0, 1)
        rect(bx + 12, by + h - 9, W - 24, 3, T.widget)
        if prog > 0 then rfill(bx + 12, by + h - 9, (W - 24) * prog, 3, 1, kc, true, false, false, true) end

        y = top and (y + (h + GAP) * a) or (y - (h + GAP) * a)
    end
end

local HITLOG_DEMO = {
    { kind = "hit",  label = "hit player in head for 90hp" },
    { kind = "hurt", label = "hurt by player in chest for 20hp" },
    { kind = "miss", label = "missed shot" },
    { kind = "kill", label = "killed player in head for 100hp" },
}
local HL_SNAP_IN, HL_SNAP_OUT, HL_DEAD = 12, 18, 28
local HL_BOTTOM = 160
local function easeOutCubic(t) t = clamp(t, 0, 1); local u = 1 - t; return 1 - u * u * u end

local function hitlogPos(hl, sw, sh)
    local px = sw / 2 + (hl.x_off or 0)
    local py = hl.y_off and (sh / 2 + hl.y_off) or (sh - HL_BOTTOM)
    return px, py
end

local function hitlogEdit(hl, sw, sh, cx, cy, rowH, gap, reveal, row)
    local x, y = hitlogPos(hl, sw, sh)
    local grab = hl._rect

    local dragging = hl._drag or false
    local snapX, snapY = hl._snapX or false, hl._snapY or false
    local pendX, pendY = hl._pendX or 0, hl._pendY or 0
    local mx, my = ms.x, ms.y

    if ms.pressed then
        if grab and mx >= grab.x and mx <= grab.x + grab.w
               and my >= grab.y and my <= grab.y + grab.h then
            dragging = true; ms.consumed = true
        end
        snapX = mabs(x - cx) < 0.5
        snapY = mabs(y - cy) < 0.5
        pendX, pendY = 0, 0
        hl._lmx, hl._lmy = mx, my
    end
    if not ms.down then dragging = false; pendX, pendY = 0, 0 end

    local hw = grab and grab.w / 2 or 90
    local hh = grab and grab.h / 2 or 50
    local minX, maxX = HL_DEAD + hw, sw - HL_DEAD - hw
    local minY, maxY = HL_DEAD + hh, sh - HL_DEAD - hh

    if dragging then
        ms.consumed = true
        local dx = mx - (hl._lmx or mx)
        local dy = my - (hl._lmy or my)
        if dx ~= 0 then
            if snapX then
                pendX = pendX + dx
                if mabs(pendX) > HL_SNAP_OUT then
                    x = cx + (pendX >= 0 and 1 or -1) * (mabs(pendX) - HL_SNAP_OUT)
                    snapX, pendX = false, 0
                else x = cx end
            else
                x = x + dx
                if mabs(x - cx) < HL_SNAP_IN then x, snapX, pendX = cx, true, 0 end
            end
        end
        if dy ~= 0 then
            if snapY then
                pendY = pendY + dy
                if mabs(pendY) > HL_SNAP_OUT then
                    y = cy + (pendY >= 0 and 1 or -1) * (mabs(pendY) - HL_SNAP_OUT)
                    snapY, pendY = false, 0
                else y = cy end
            else
                y = y + dy
                if mabs(y - cy) < HL_SNAP_IN then y, snapY, pendY = cy, true, 0 end
            end
        end
        if minX <= maxX then x = clamp(x, minX, maxX) end
        if minY <= maxY then y = clamp(y, minY, maxY) end
    end

    hl._lmx, hl._lmy = mx, my
    hl._drag, hl._snapX, hl._snapY, hl._pendX, hl._pendY = dragging, snapX, snapY, pendX, pendY

    if dragging then hl.x_off, hl.y_off = x - cx, y - cy end

    if dragging then
        ALPHA = 0.55
        if snapX or mabs(x - cx) < 0.5 then rect(cx, 0, 1, sh, T.accent) end
        if snapY or mabs(y - cy) < 0.5 then rect(0, cy, sw, 1, T.accent) end
        ALPHA = 1
    end

    local n = #HITLOG_DEMO
    local STAGGER = 0.18
    local span = 1 + STAGGER * (n - 1)
    local cyTop = y
    local lx, rx, ty, by2 = 1 / 0, -1 / 0, 1 / 0, -1 / 0
    for i = 1, n do
        local d = HITLOG_DEMO[i]
        local e = easeOutCubic(reveal * span - (i - 1) * STAGGER)
        if e > 0.004 then
            local slide = (1 - e) * 10
            local ry = cyTop + (i - 1) * (rowH + gap) + slide
            local boxW = row(d.kind, d.label, x, ry, e)
            if x - boxW / 2 < lx then lx = x - boxW / 2 end
            if x + boxW / 2 > rx then rx = x + boxW / 2 end
            if ry < ty then ty = ry end
            if ry + rowH > by2 then by2 = ry + rowH end
        end
    end

    if by2 > ty then
        hl._rect = { x = lx, y = ty, w = rx - lx, h = by2 - ty }
        ALPHA = reveal
        local hint = "preview · drag to move"
        text(x + 1, by2 + 7, { 0, 0, 0, 235 }, hint, FONT, "center")
        text(x, by2 + 6, T.texthi, hint, FONT, "center")
        ALPHA = 1
    end
end

function M:_drawHitlog()
    local hl = self._hitlog
    if not hl.enabled then return end

    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end
    local cx, cy = sw / 2, sh / 2

    pcall(function() draw.SetFont(FONT) end)
    local padX, padY, dotR, dotGap = 11, 5, 3, 8

    local txtH = floor((hl.font_size or T.font_size) + 0.5)
    pcall(function() local _, h = draw.GetTextSize("Ayg"); if h and h > 4 then txtH = floor(h + 0.5) end end)
    local rowH = txtH + padY * 2
    local gap  = 6

    local function row(kind, label, px, by, a)
        local col  = hl.colors[kind] or hl.colors.hit or T.accent
        local boxW = floor(padX * 2 + dotR * 2 + dotGap + textw(label) + 0.5)
        local bx   = floor(px - boxW / 2 + 0.5)
        by         = floor(by + 0.5)
        ALPHA = a
        local fill = lerpc(T.section, { col[1], col[2], col[3], 255 }, 0.12)
        local brd  = lerpc(T.border,  { col[1], col[2], col[3], 255 }, 0.45)
        rbox(bx, by, boxW, rowH, 6, fill, brd)

        rfill(bx + 2, by + 4, 2, rowH - 8, 1, col)

        local dcy = by + floor((rowH - dotR * 2) / 2 + 0.5)
        rfill(bx + padX, dcy, dotR * 2, dotR * 2, dotR, col)
        text(bx + padX + dotR * 2 + dotGap, by + padY, T.texthi, label, FONT)
        ALPHA = 1
        return boxW
    end

    local reveal = self._t or 0

    if reveal > 0.02 then
        if self._open ~= false then
            hitlogEdit(hl, sw, sh, cx, cy, rowH, gap, reveal, row)
        else

            local x, y = hitlogPos(hl, sw, sh)
            local n = #HITLOG_DEMO
            local cyTop = y
            for i = 1, n do
                local d = HITLOG_DEMO[i]
                local e = easeOutCubic(reveal)
                if e > 0.004 then row(d.kind, d.label, x, cyTop + (i - 1) * (rowH + gap), e) end
            end
        end
        return
    end

    local q = hl.queue
    local life, fadeIn, fadeOut = hl.life, hl.fade_in, hl.fade_out
    local i = 1
    while i <= #q do
        if (now() - q[i].born) >= life + fadeOut + 0.05 then table.remove(q, i)
        else i = i + 1 end
    end
    if #q == 0 then return end

    local px, py = hitlogPos(hl, sw, sh)
    local n = #q
    local cyTop = py
    for k = 1, n do
        local e   = q[k]
        local age = now() - e.born
        local inE  = smoother(clamp(age / fadeIn, 0, 1))
        local outE = smoother(clamp((age - life) / fadeOut, 0, 1))
        local a    = inE * (1 - outE)
        if a > 0.004 then
            local rowY = cyTop + (n - k) * (rowH + gap) + (1 - inE) * 14
            row(e.kind, hitlogLabel(e), px, rowY, a)
        end
    end
end

local function killMiscWatermark()
    for _, k in ipairs(WM_MISC_KEYS) do
        pcall(function()
            local v = gui.GetValue(k)
            if v == true or v == 1 then gui.SetValue(k, false) end
        end)
    end
end

function M:_drawWatermark()
    local wm = self._watermark
    if not wm.enabled then return end

    if DT and DT > 0 then
        local inst = 1 / DT
        wm._fps = wm._fps > 0 and (wm._fps + (inst - wm._fps) * 0.12) or inst
    end

    local t = now()
    if t - (wm._killTry or -1) > 1 then wm._killTry = t; killMiscWatermark() end

    local function nameSeg(s)
        s = tostring(s or "")
        local dot
        for i = #s, 2, -1 do if s:sub(i, i) == "." then dot = i; break end end
        if dot and dot >= 2 and dot < #s then
            return { { s:sub(1, dot - 1), T.texthi, FONT_LOGO }, { s:sub(dot), T.accent, FONT_LOGO } }
        end
        return { { s, T.texthi, FONT_LOGO } }
    end

    local segs = {}
    if wm.parts.cheat then segs[#segs + 1] = nameSeg(wm.cheat_name or "AIMWARE.NET") end
    if wm.parts.lua   then segs[#segs + 1] = nameSeg(wm.lua_name or "FEMBOYTAP.CC") end
    if wm.parts.user  then segs[#segs + 1] = { { tostring(wm.user or "?"), T.text, FONT } } end
    if wm.parts.nick  then segs[#segs + 1] = { { tostring(wm.nick or "?"), T.text, FONT } } end
    if wm.parts.fps   then segs[#segs + 1] = { { floor(wm._fps + 0.5) .. " fps", T.text, FONT } } end
    if wm.parts.ping  then
        segs[#segs + 1] = { { (wm.ping and (floor(wm.ping + 0.5) .. " ms") or "- ms"), T.text, FONT } }
    end
    if #segs == 0 then return end

    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end

    local PADX, PADY, DIVPAD = 11, 6, 9
    local function runW(run)
        if run[3] then pcall(function() draw.SetFont(run[3]) end) end
        return textw(run[1])
    end

    local totalW = PADX * 2
    for si, seg in ipairs(segs) do
        if si > 1 then totalW = totalW + DIVPAD * 2 + 1 end
        for _, run in ipairs(seg) do totalW = totalW + runW(run) end
    end

    local txtH = T.font_size
    pcall(function() draw.SetFont(FONT) end)
    pcall(function() local _, h = draw.GetTextSize("Ayg"); if h and h > 4 then txtH = floor(h + 0.5) end end)
    local barH = txtH + PADY * 2

    local margin = 14
    local pos    = wm.pos or "top-right"
    local right  = pos:find("right") ~= nil
    local bottom = pos:find("bottom") ~= nil
    local bx = right  and (sw - margin - totalW) or margin
    local by = bottom and (sh - margin - barH)   or margin

    ALPHA = 1
    rbox(bx, by, totalW, barH, 6, T.section, T.border)
    rfill(bx, by, totalW, 2, 6, T.accent, true, true, false, false)

    local cx = bx + PADX
    local ty = by + PADY
    for si, seg in ipairs(segs) do
        if si > 1 then
            rect(cx + DIVPAD, by + 6, 1, barH - 12, T.divider)
            cx = cx + DIVPAD * 2 + 1
        end
        for _, run in ipairs(seg) do
            text(cx, ty, run[2], run[1], run[3])
            cx = cx + textw(run[1])
        end
    end
end

local function tabLayout(tabs, win)
    pcall(function() draw.SetFont(FONT_LOGO) end)
    local startX = win.x + 16 + textw(T.title) + textw(T.title_tld) + 14
    pcall(function() draw.SetFont(FONT) end)
    local pos, tx = {}, startX
    for i, t in ipairs(tabs) do
        local tw = textw(t.name) + 28
        pos[i] = { x = tx, w = tw }
        tx = tx + tw
    end
    return pos
end

function M:_tabInput(win)
    local pos = tabLayout(self._tabs, win)
    for i, p in ipairs(pos) do
        if clicked(p.x, win.y, p.w, T.titlebar) and self._active ~= i then
            self._active = i; M._combo = nil; self._tabT = 0
        end
    end
end

function M:_drawTabBar(win)
    text(win.x + 16, win.y + 17, T.texthi, T.title, FONT_LOGO)
    local logoW = textw(T.title)
    text(win.x + 16 + logoW, win.y + 17, T.accent, T.title_tld, FONT_LOGO)
    local pos = tabLayout(self._tabs, win)

    local act = pos[self._active]
    local tgtX, tgtW = act and act.x or win.x, act and act.w or 0
    local relX = tgtX - win.x
    if not self._pillX then self._pillX, self._pillW = relX, tgtW end
    self._pillX = approach(self._pillX, relX, 16)
    self._pillW = approach(self._pillW, tgtW, 16)
    rfill(win.x + self._pillX + 3, win.y + 9, self._pillW - 6, T.titlebar - 18, 5, T.accent_bg)

    for i, t in ipairs(self._tabs) do
        local p = pos[i]
        local active = (i == self._active)
        local hov = hovering(p.x, win.y, p.w, T.titlebar)
        t._h = approach(t._h or 0, (active or hov) and 1 or 0, 16)
        text(p.x + p.w / 2, win.y + 16, lerpc(T.textdim, T.texthi, t._h), t.name, FONT, "center")
    end
end

local DD_ITEMH, DD_MAXVIS = 22, 9

function M:_dropdownInput()
    if not M._combo or not M._dd or M._dd.wd ~= M._combo then return end
    local d, wd = M._dd, M._dd.wd
    local n = #wd.options
    local visible = mmin(n, DD_MAXVIS)
    local listH = visible * DD_ITEMH
    local maxScroll = mmax(0, n - visible)
    wd._ddScroll = clamp(wd._ddScroll or 0, 0, maxScroll)

    if (ms.wheel or 0) ~= 0 and hovering(d.x, d.y, d.w, listH) then
        wd._ddScroll = clamp(wd._ddScroll - (ms.wheel > 0 and 1 or -1), 0, maxScroll)
        ms.wheel = 0
    end

    if maxScroll > 0 then
        local trackX = d.x + d.w - 7
        if ms.pressed and not ms.consumed and hovering(trackX - 2, d.y, 10, listH) then
            ms.consumed = true; M._ddScrollbar = wd
        end
        if M._ddScrollbar == wd then
            if ms.down then wd._ddScroll = rnd(clamp((ms.y - d.y) / listH, 0, 1) * maxScroll)
            else M._ddScrollbar = nil end
            return
        end
    end

    if not ms.pressed or ms.consumed then return end
    if hovering(d.x, d.y, d.w, listH) then
        for vi = 0, visible - 1 do
            if hovering(d.x, d.y + vi * DD_ITEMH, d.w, DD_ITEMH) then
                local i = vi + 1 + floor(wd._ddScroll)
                if i <= n then
                    if wd.kind == "multicombo" then wd.value[i] = not wd.value[i] or nil
                    else wd.value = i; M._combo = nil end
                end
                break
            end
        end
        ms.consumed = true
    elseif not hovering(d.x, d.y - d.bh, d.w, d.bh) then
        M._combo = nil
    end
end

function M:_drawDropdown()
    if not M._combo or not M._dd or M._dd.wd ~= M._combo then return end
    local d, wd = M._dd, M._dd.wd
    local multi = (wd.kind == "multicombo")
    local n = #wd.options
    local visible = mmin(n, DD_MAXVIS)
    local listH = visible * DD_ITEMH
    local maxScroll = mmax(0, n - visible)
    local scroll = clamp(wd._ddScroll or 0, 0, maxScroll)
    local hasBar = maxScroll > 0
    local iw = hasBar and (d.w - 9) or d.w
    rbox(d.x, d.y, d.w, listH, 5, T.widget, T.accent)
    for vi = 0, visible - 1 do
        local i = vi + 1 + floor(scroll)
        if i <= n then
            local opt = wd.options[i]
            local iy = d.y + vi * DD_ITEMH
            local sel = multi and wd.value[i] or (not multi and wd.value == i)
            local hov = hovering(d.x, iy, iw, DD_ITEMH)
            if hov then rect(d.x + 1, iy, iw - 2, DD_ITEMH, T.widgethi) end
            if multi then
                rbox(d.x + 8, iy + 5, 12, 12, 3, sel and T.accent or T.widget, sel and T.accent or T.border)
                text(d.x + 26, iy + 5, (sel or hov) and T.texthi or T.text, opt, FONT)
            else
                if sel then rect(d.x + 1, iy, 3, DD_ITEMH, T.accent) end
                text(d.x + 9, iy + 5, (sel or hov) and T.texthi or T.text, opt, FONT)
            end
        end
    end
    if hasBar then
        local trackX = d.x + d.w - 6
        local thumbH = mmax(20, listH * visible / n)
        local thumbY = d.y + (listH - thumbH) * (scroll / maxScroll)
        rfill(trackX, d.y + 2, 4, listH - 4, 2, T.widget)
        rfill(trackX, thumbY, 4, thumbH, 2, T.accent)
    end
end

local CP = { pad = 12, svW = 138, svH = 128, barW = 14, gap = 10, sw = 22, sgap = 6, slots = 5 }
local function cpWidth()  return CP.pad * 2 + CP.svW + CP.gap * 2 + CP.barW * 2 end
local function cpHeight() return CP.pad * 2 + CP.svH + 52 end

function M:_cpInput()
    if not M._cp or not M._cpRect then return end
    if not ms.pressed or ms.consumed then return end
    local r = M._cpRect
    if hovering(r.x, r.y, cpWidth(), cpHeight()) then ms.consumed = true
    elseif not hovering(r.sx, r.sy, r.sw, r.sh) then M._cp = nil end
end

function M:_cpDraw()
    if not M._cp or not M._cpRect then return end
    local wd, r = M._cp, M._cpRect
    if not wd._hsv then wd._hsv = { rgb2hsv(wd.value[1], wd.value[2], wd.value[3]) } end
    local hsv = wd._hsv
    local w = cpWidth()

    if self._win then r.x = mmin(r.x, self._win.x + self._win.w - w - 6) end

    rbox(r.x, r.y, w, cpHeight(), 6, T.section, T.accent)
    local svX, svY, svW, svH = r.x + CP.pad, r.y + CP.pad, CP.svW, CP.svH
    local hueX   = svX + svW + CP.gap
    local alphaX = hueX + CP.barW + CP.gap

    if ms.pressed and not M._cpDrag then
        if hovering(svX, svY, svW, svH) then M._cpDrag = "sv"
        elseif hovering(hueX, svY, CP.barW, svH) then M._cpDrag = "hue"
        elseif hovering(alphaX, svY, CP.barW, svH) then M._cpDrag = "alpha" end
    end
    if M._cpDrag then
        if ms.down then
            if M._cpDrag == "sv" then
                hsv[2] = clamp((ms.x - svX) / svW, 0, 1)
                hsv[3] = clamp(1 - (ms.y - svY) / svH, 0, 1)
            elseif M._cpDrag == "hue" then
                hsv[1] = clamp((ms.y - svY) / svH, 0, 1)
            elseif M._cpDrag == "alpha" then
                wd.value[4] = rnd(clamp(1 - (ms.y - svY) / svH, 0, 1) * 255)
            end
        else M._cpDrag = nil end
    end

    M._swatches = M._swatches or {}
    local sy   = svY + svH + 28
    local addX = svX
    local addHov = hovering(addX, sy, CP.sw, CP.sw)
    local pre = { hsv2rgb(hsv[1], hsv[2], hsv[3]) }
    if ms.pressed and addHov then
        table.insert(M._swatches, 1, { pre[1], pre[2], pre[3], wd.value[4] or 255 })
        while #M._swatches > CP.slots do table.remove(M._swatches) end
    end
    for i = 1, CP.slots do
        local c = M._swatches[i]
        local cxs = addX + i * (CP.sw + CP.sgap)
        if c and ms.pressed and hovering(cxs, sy, CP.sw, CP.sw) then
            hsv[1], hsv[2], hsv[3] = rgb2hsv(c[1], c[2], c[3])
            wd.value[4] = c[4] or 255
        end
    end

    local h, s, v = hsv[1], hsv[2], hsv[3]
    local cr, cg, cb = hsv2rgb(h, s, v)
    local av = wd.value[4] or 255

    local hr, hg, hb = hsv2rgb(h, 1, 1)
    rect(svX, svY, svW, svH, { hr, hg, hb })
    for dx = 0, svW - 1, 2 do
        rect(svX + dx, svY, 2, svH, { 255, 255, 255, 255 * (1 - dx / svW) })
    end
    for dy = 0, svH - 1, 2 do
        rect(svX, svY + dy, svW, 2, { 0, 0, 0, 255 * (dy / svH) })
    end
    frame(svX, svY, svW, svH, T.border)
    local cxp = svX + clamp(s, 0, 1) * svW
    local cyp = svY + (1 - clamp(v, 0, 1)) * svH
    rbox(cxp - 5, cyp - 5, 10, 10, 5, { cr, cg, cb }, { 255, 255, 255 })

    for dy = 0, svH - 1, 2 do
        rect(hueX, svY + dy, CP.barW, 2, { hsv2rgb(dy / svH, 1, 1) })
    end
    frame(hueX, svY, CP.barW, svH, T.border)
    rfill(hueX - 2, svY + clamp(h, 0, 1) * svH - 2, CP.barW + 4, 4, 1, { 255, 255, 255 })

    rect(alphaX, svY, CP.barW, svH, T.widget)
    for dy = 0, svH - 1, 2 do
        rect(alphaX, svY + dy, CP.barW, 2, { cr, cg, cb, 255 * (1 - dy / svH) })
    end
    frame(alphaX, svY, CP.barW, svH, T.border)
    rfill(alphaX - 2, svY + (1 - av / 255) * svH - 2, CP.barW + 4, 4, 1, { 255, 255, 255 })

    wd.value[1], wd.value[2], wd.value[3] = cr, cg, cb
    local ty = svY + svH + 6
    text(svX, ty, T.textdim, string.format("R %d  G %d  B %d  A %d", cr, cg, cb, av), FONT)

    rbox(addX, sy, CP.sw, CP.sw, 4, addHov and T.widgethi or T.widget, T.border)
    text(addX + CP.sw / 2, sy + 3, addHov and T.texthi or T.textdim, "+", FONT, "center")
    for i = 1, CP.slots do
        local c = M._swatches[i]
        local cxs = addX + i * (CP.sw + CP.sgap)
        rbox(cxs, sy, CP.sw, CP.sw, 4, c and { c[1], c[2], c[3], 255 } or T.bg2, T.border)
    end
end

function M:_drag(win)
    if ms.pressed and not ms.consumed and hovering(win.x, win.y, win.w, T.titlebar) then
        ms.consumed = true
        self._dragWin = { dx = ms.x - win.x, dy = ms.y - win.y }
    end
    if self._dragWin then
        if ms.down then win.x = ms.x - self._dragWin.dx; win.y = ms.y - self._dragWin.dy
        else self._dragWin = nil end
    end
end

function M:_frame()
    local real = self._win
    local tab = self._tabs[self._active]

    local contentH = 0
    if tab then pcall(function() contentH = tabContentHeight(tab) end) end
    local chrome = T.titlebar + T.pad * 2

    local screenW, screenH = 1920, 1080
    pcall(function() screenW, screenH = draw.GetScreenSize() end)
    screenW = screenW or 1920
    screenH = screenH or 1080

    -- resize grip (bottom-right)
    local grip = 14
    if self._resizeEnabled ~= false then
        local gx, gy = real.x + real.w - grip, real.y + real.h - grip
        if ms.pressed and not ms.consumed and hovering(gx, gy, grip, grip) then
            ms.consumed = true
            self._resize = { ox = ms.x, oy = ms.y, ow = real.w, oh = real.h }
            self._autoH = false
        end
        if self._resize then
            if ms.down then
                real.w = clamp(self._resize.ow + (ms.x - self._resize.ox), 520, screenW - 40)
                real.h = clamp(self._resize.oh + (ms.y - self._resize.oy), 300, screenH - 40)
            else
                self._resize = nil
            end
        end
    end

    if self._autoH then
        local targetH = clamp(contentH + chrome + 8, 280, screenH - 60)
        real.h = real.h + (targetH - real.h) * clamp(DT * 14, 0, 1)
    end

    local ease = smooth(self._t)
    ALPHA = ease
    local oy = (1 - ease) * 14
    local win = { x = real.x, y = real.y - oy, w = real.w, h = real.h }

    rbox(win.x, win.y, win.w, win.h, 7, T.bg, T.border)
    rfill(win.x + 1, win.y + T.titlebar, win.w - 2, win.h - T.titlebar - 1, 6, T.bg2, false, false, true, true)

    self:_tabInput(win)
    self:_drag(win)
    self:_dropdownInput()
    self:_cpInput()

    local availH = win.h - chrome
    local maxScroll = mmax(0, contentH - availH)
    self._scroll = clamp(self._scroll or 0, 0, maxScroll)

    -- scrollbar drag
    if maxScroll > 0 then
        local barX, barW = win.x + win.w - 7, 4
        local th = mmax(20, (availH / contentH) * availH)
        local ty = win.y + T.titlebar + (availH - th) * (self._scroll / maxScroll)
        if ms.pressed and not ms.consumed and hovering(barX - 2, win.y + T.titlebar, barW + 6, availH) then
            ms.consumed = true
            self._scrollDrag = true
        end
        if self._scrollDrag then
            if ms.down then
                local frac = clamp((ms.y - (win.y + T.titlebar) - th * 0.5) / mmax(1, availH - th), 0, 1)
                self._scroll = frac * maxScroll
            else
                self._scrollDrag = nil
            end
        end
    end

    local tabEase = smooth(self._tabT)
    local cx = win.x + T.pad + (1 - tabEase) * 18
    local cy = win.y + T.titlebar + T.pad - self._scroll
    local cw = win.w - T.pad * 2 - 8
    clipTop, clipBottom = win.y + T.titlebar, win.y + win.h - 2
    if tab then
        local ok, err = pcall(function() tab:render(cx, cy, cw) end)
        if not ok then print("[femboytap] tab '" .. tostring(tab.name) .. "' error: " .. tostring(err)) end
    end
    clipTop, clipBottom = nil, nil

    if maxScroll > 0 and (ms.wheel or 0) ~= 0 and hovering(win.x, win.y + T.titlebar, win.w, win.h - T.titlebar) then
        self._scroll = clamp(self._scroll - (ms.wheel > 0 and 36 or -36), 0, maxScroll)
        ms.wheel = 0
    end

    rfill(win.x + 1, win.y + 1, win.w - 2, T.titlebar - 1, 6, T.bg, true, true, false, false)
    rfill(win.x, win.y, win.w, 2, 7, T.accent, true, true, false, false)
    rect(win.x + 1, win.y + T.titlebar, win.w - 2, 1, T.border)
    self:_drawTabBar(win)

    if maxScroll > 0 then
        local th = mmax(20, (availH / contentH) * availH)
        local ty = win.y + T.titlebar + (availH - th) * (self._scroll / maxScroll)
        rfill(win.x + win.w - 6, win.y + T.titlebar + 2, 3, availH - 4, 1, T.widget)
        rfill(win.x + win.w - 6, ty, 3, th, 1, T.accent)
    end

    -- resize grip visual
    if self._resizeEnabled ~= false then
        local gx, gy = win.x + win.w - 11, win.y + win.h - 11
        rect(gx, gy + 6, 8, 1, T.textdim)
        rect(gx + 3, gy + 3, 5, 1, T.textdim)
        rect(gx + 6, gy, 2, 1, T.textdim)
    end

    self:_drawDropdown()
    self:_cpDraw()

    if M._focus and ms.pressed and not ms.consumed then M._focus = nil end

    real.x = win.x
    real.y = win.y + oy
end

function M:OpenFolder()
    pcall(function()
        ffi.cdef[[ int ShellExecuteA(void*, const char*, const char*, const char*, const char*, int); ]]
    end)
    pcall(function()
        local shell = ffi.load("shell32")
        shell.ShellExecuteA(nil, "open", M._dir or ".", nil, nil, 1)
    end)
end

function M:_initScreen()
    local win = self._win
    ALPHA = smooth(self._t)
    rbox(win.x, win.y, win.w, win.h, 7, T.bg, T.border)
    rfill(win.x, win.y, win.w, 2, 7, T.accent, true, true, false, false)
    local dots = string.rep(".", floor(now() * 2) % 4)
    text(win.x + win.w / 2, win.y + win.h / 2 - 12, T.texthi, "Initialization in progress" .. dots, FONT_B, "center")
    text(win.x + win.w / 2, win.y + win.h / 2 + 12, T.textdim, "fetching fonts, please wait", FONT, "center")
end

function M:Build(opts)
    opts = opts or {}
    if opts.w then self._win.w = opts.w end
    if opts.h then self._win.h = opts.h end
    if opts.x then self._win.x = opts.x end
    if opts.y then self._win.y = opts.y end
    if opts.autoH ~= nil then
        self._autoH = opts.autoH and true or false
    else
        self._autoH = (opts.h == nil)
    end
    if opts.resize ~= nil then
        self._resizeEnabled = opts.resize and true or false
    else
        self._resizeEnabled = true
    end

    _getMouse = resolveMouse()
    _getWheel = resolveWheel()
    _clock    = resolveClock()
    initFonts()
    self._initco = coroutine.create(fontInitCoro)
    if not _getMouse then print("[femboytap] WARNING: mouse position API not found -- cursor won't track") end

    local menuRef
    pcall(function() menuRef = gui.Reference("MENU") end)

    callbacks.Register("Draw", function()
        local open = true
        if menuRef then pcall(function() open = menuRef:IsActive() end) end
        self._open = open
        if not open then self._focus = nil; self._inputDrag = nil end

        local t  = now()
        local dt = 1
        if _clock then dt = self._last and clamp(t - self._last, 0, 0.1) or 0 end
        self._last = t
        DT = dt

        self._t    = self._t    + ((open and 1 or 0) - self._t) * clamp(dt * ANIM.open, 0, 1)
        self._tabT = self._tabT + (1 - self._tabT)              * clamp(dt * ANIM.tab,  0, 1)

        if self._initco then
            pcall(function()
                if coroutine.status(self._initco) ~= "dead" then coroutine.resume(self._initco) end
            end)
            if coroutine.status(self._initco) == "dead" then self._initco = nil end
            pcall(function() self:_initScreen() end)
            return
        end

        updateMouse()
        pcall(function() self:_drawToasts() end)
        pcall(function() self:_drawHitlog() end)
        pcall(function() self:_drawWatermark() end)

        ALPHA = 1
        for _, fn in ipairs(self._onframe) do pcall(fn, UI) end

        if not open and self._t < 0.005 then self._t = 0; return end

        local ok, err = pcall(function() self:_frame() end)
        if not ok then print("[femboytap] frame error: " .. tostring(err)) end
    end)

    pcall(function() callbacks.Register("CreateMove", function(cmd)
        if not (M._open and M._focus) or not cmd then return end
        pcall(function() cmd.forwardmove = 0 end)
        pcall(function() cmd.sidemove = 0 end)
        pcall(function() cmd.upmove = 0 end)
        pcall(function() cmd.buttons = 0 end)
        pcall(function() cmd:SetForwardMove(0) end)
        pcall(function() cmd:SetSideMove(0) end)
        pcall(function() cmd:SetUpMove(0) end)
        pcall(function() cmd:SetButtons(0) end)
    end) end)

    print(string.format("[femboytap.cc] guilib v%s ready: %d tabs, mouse=%s clock=%s",
        tostring(M.VERSION), #self._tabs, _getMouse and "ok" or "NIL", _clock and "ok" or "NIL"))
    return self
end

return M
