-- lyrics_display.lua
-- Reads {"header","line","album","cover","start_ms","current_ms","end_ms",
-- "is_playing","ts"} from a bridge file and renders a Now Playing card
-- (album cover + artist/song + progress bar) with an optional sliding
-- lyric line beneath it. While the menu is open, the card is draggable
-- and a control row (prev/play-pause/next/lyrics toggle) is shown.
--
-- No os.* usage anywhere -- only io.* for file reads, everything pcall'd.

local M = {}
local embedded = rawget(_G, "FEMBOY_SPOTIFY_EMBED") and true or false

local FIILE = "aimwarelyrics.txt" -- kept the name/spelling you asked for
local CONTROL_PATH = "aimwarelyricscontrol.txt" -- Lua -> Python commands

-- ── theme ───────────────────────────────────────────────────────────────
local T = {
    accent  = { 139, 124, 246 },
    section = { 25, 25, 32, 255 },
    border  = { 44, 44, 56, 255 },
    texthi  = { 240, 240, 245, 255 },
    textdim = { 150, 150, 162, 255 },
}
local MUSIC_GLYPH = "\226\153\170" -- UTF-8 for ♪, used as a cover-art fallback

local CARD = {
    coverSize = 56,
    pad       = 10,
    gap       = 10,
    barH      = 5,
    barGap    = 10,
}

local floor, sqrt, mmin, mmax, mabs = math.floor, math.sqrt, math.min, math.max, math.abs
local function rnd(n) return floor(n + 0.5) end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

-- ── drawing helpers ─────────────────────────────────────────────────────
local ALPHA = 1
local function setcol(c) draw.Color(c[1], c[2], c[3], rnd((c[4] or 255) * ALPHA)) end
local function rect(x, y, w, h, c)
    setcol(c)
    pcall(function() draw.FilledRect(rnd(x), rnd(y), rnd(x + w), rnd(y + h)) end)
end

local function rfill(x, y, w, h, r, c)
    x, y, w, h = rnd(x), rnd(y), rnd(w), rnd(h)
    r = mmin(r, floor(w / 2), floor(h / 2))
    if r <= 0 then rect(x, y, w, h, c); return end
    rect(x, y + r, w, h - 2 * r, c)
    for dy = 0, r - 1 do
        local dx = r - floor(sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
        rect(x + dx, y + dy, w - 2 * dx, 1, c)
        rect(x + dx, y + h - 1 - dy, w - 2 * dx, 1, c)
    end
end

local function rbox(x, y, w, h, r, fill, brd)
    rfill(x, y, w, h, r, brd)
    rfill(x + 1, y + 1, w - 2, h - 2, r - 1, fill)
end

-- ── fonts ───────────────────────────────────────────────────────────────
local FONT_LIST = { "Oxanium", "Space Grotesk", "Tahoma" } -- fallback chain
-- Font family names must match what's embedded in each .ttf's own name
-- table (not the filename) for draw.CreateFont to find them afterward.
local FONT_DOWNLOAD_URLS = {
    "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/oxanium/Oxanium%5Bwght%5D.ttf",
    "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf",
}

local FONT, FONT_B
local fontsReady = false -- true as soon as ANY usable font is picked (even fallback)

local function pickFonts()
    local ok = pcall(function()
        local mk = function(size, weight)
            for _, name in ipairs(FONT_LIST) do
                local f
                pcall(function() f = draw.CreateFont(name, size, weight) end)
                if f then return f end
            end
        end
        FONT   = mk(14, 400)
        FONT_B = mk(14, 700)
    end)
    if ok and (FONT or FONT_B) then
        fontsReady = true
    end
    return ok
end

-- Downloads each custom font via the sandboxed http.Get and registers it
-- with draw.AddFontResource(bytes), then re-picks fonts so CreateFont can
-- find it by name. This replaces an earlier version that used raw win32
-- APIs via FFI (GetCurrentDirectoryA/AddFontResourceExA/URLDownloadToFileA)
-- to install fonts system-wide -- unnecessary once http.Get and
-- draw.AddFontResource turned out to be real, documented, sandboxed calls.
-- pickFonts() already ran synchronously below on load (Tahoma fallback), so
-- this only ever UPGRADES the font once each download finishes -- it can
-- never block the widget from rendering, and each call is independently
-- pcall'd so one failed download can't affect the others.
local function installFonts()
    for _, url in ipairs(FONT_DOWNLOAD_URLS) do
        pcall(function()
            http.Get(url, function(data)
                if data and #data > 100 then
                    pcall(function() draw.AddFontResource(data) end)
                    pickFonts()
                else
                    print("[lyrics_display] font download returned no data: " .. url)
                end
            end)
        end)
    end
end

local function textw(s) local w = 0; pcall(function() w = draw.GetTextSize(s) end); return w or 0 end
local function text(x, y, c, s, font, align)
    if font then pcall(function() draw.SetFont(font) end) end
    if align == "center" then x = x - textw(s) / 2
    elseif align == "right" then x = x - textw(s) end
    setcol(c)
    pcall(function() draw.Text(rnd(x), rnd(y), s) end)
end

-- ── mouse ───────────────────────────────────────────────────────────────
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

local ms = { x = 0, y = 0, down = false, pressed = false, consumed = false }
local function updateMouse()
    if _getMouse then
        local ok, x, y = pcall(_getMouse)
        if ok then ms.x, ms.y = x or ms.x, y or ms.y end
    end
    local down = false
    pcall(function() down = input.IsButtonDown(0x01) and true or false end)
    ms.pressed  = down and not ms.down
    ms.down     = down
    ms.consumed = false
end
local function hovering(x, y, w, h)
    return ms.x >= x and ms.x <= x + w and ms.y >= y and ms.y <= y + h
end

-- ── clock ───────────────────────────────────────────────────────────────
local _clock
local function resolveClock()
    local cands = {
        function() return globals.RealTime() end,
        function() return globals.CurTime() end,
    }
    for _, f in ipairs(cands) do
        local ok, v = pcall(f)
        if ok and type(v) == "number" then return f end
    end
end
local _t0 = 0 -- fallback monotonic-ish counter if no clock API is found
local function now()
    if _clock then
        local ok, v = pcall(_clock)
        if ok and type(v) == "number" then return v end
    end
    _t0 = _t0 + 0.016
    return _t0
end

-- ── file reading, no os, everything pcall'd ─────────────────────────────
-- aimware's sandbox exposes its own file.Open(path, mode) -> handle with
-- :Read()/:Write()/:Close(), the same API the wallbang helper's load_spots()
-- uses. Standard io.open may not be reliably present, so try file.* first
-- and fall back to io only if file.* isn't available.
local _checkedApis = false
local function debugApiCheckOnce()
    if _checkedApis then return end
    _checkedApis = true
    print("[lyrics_display] file table present: " .. tostring(file ~= nil))
    print("[lyrics_display] io table present: " .. tostring(io ~= nil))
end

local function readLastLine(path)
    debugApiCheckOnce()

    if file and file.Open then
        local ok, result = pcall(function()
            local f = file.Open(path, "r")
            if not f then return nil end
            local content
            pcall(function() content = f:Read() end)
            pcall(function() f:Close() end)
            return content
        end)
        if ok and result and result ~= "" then
            local last = nil
            for l in result:gmatch("[^\r\n]+") do
                if l ~= "" then last = l end
            end
            if last then return last end
        end
    end

    if io and io.open then
        local ok, last = pcall(function()
            local f = io.open(path, "r")
            if not f then return nil end
            local l2 = nil
            for l in f:lines() do
                if l and l ~= "" then l2 = l end
            end
            f:close()
            return l2
        end)
        if ok and last then return last end
    end

    return nil
end

-- writes a single line, used for the control channel (Lua -> Python).
-- Same file/io fallback pattern as readLastLine.
local function writeFile(path, content)
    local ok = false
    if file and file.Open then
        ok = pcall(function()
            local f = file.Open(path, "w")
            if f then
                pcall(function() f:Write(content) end)
                pcall(function() f:Close() end)
            end
        end)
    end
    if not ok and io and io.open then
        ok = pcall(function()
            local f = io.open(path, "w")
            if f then f:write(content); f:close() end
        end)
    end
    return ok
end

-- encodes a unicode codepoint as UTF-8 bytes
local function utf8Encode(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
    else
        return string.char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
end

-- decodes JSON string escapes (\", \\, \/, \n, \t, \u00e9, surrogate-pair
-- \uD83D\uDE00 emoji, etc.) into real UTF-8 text. Codepoints >= 0x10000
-- are dropped rather than encoded: none of the loaded fonts have glyphs
-- for them, so rendering them produced tofu boxes that also threw off
-- textw()'s width measurement and broke box sizing around them.
local function jsonUnescape(s)
    if not s or s == "" then return s end
    local ok, out = pcall(function()
        local buf, i, n = {}, 1, #s
        while i <= n do
            local c = s:sub(i, i)
            if c == "\\" and i < n then
                local nx = s:sub(i + 1, i + 1)
                if nx == '"' or nx == "\\" or nx == "/" then
                    buf[#buf + 1] = nx; i = i + 2
                elseif nx == "n" then buf[#buf + 1] = "\n"; i = i + 2
                elseif nx == "t" then buf[#buf + 1] = "\t"; i = i + 2
                elseif nx == "r" or nx == "b" or nx == "f" then i = i + 2 -- drop
                elseif nx == "u" then
                    local cp = tonumber(s:sub(i + 2, i + 5), 16)
                    i = i + 6
                    if cp then
                        if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
                            local cp2 = tonumber(s:sub(i + 2, i + 5), 16)
                            if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                                cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
                                i = i + 6
                            end
                        end
                        if cp < 0x10000 then buf[#buf + 1] = utf8Encode(cp) end
                    end
                else
                    buf[#buf + 1] = nx; i = i + 2
                end
            else
                buf[#buf + 1] = c; i = i + 1
            end
        end
        return table.concat(buf)
    end)
    return ok and out or s
end

-- drops any raw (non-escaped) 4-byte UTF-8 sequences -- always supplementary
-- -plane characters (emoji) that none of the loaded fonts have glyphs for.
local function stripAstral(s)
    if not s or s == "" then return s end
    local ok, out = pcall(function()
        local buf, i, n = {}, 1, #s
        while i <= n do
            local b = s:byte(i)
            if b and b >= 0xF0 then
                i = i + 4
            else
                buf[#buf + 1] = s:sub(i, i)
                i = i + 1
            end
        end
        return table.concat(buf)
    end)
    return ok and out or s
end

-- pulls the still-escaped raw text for "key": "..." out of raw, walking
-- char-by-char so an escaped quote/backslash inside the value (\" \\ \u...)
-- doesn't get mistaken for the closing quote and truncate the match early
local function extractJsonString(raw, key)
    local _, openEnd = raw:find('"' .. key .. '"%s*:%s*"')
    if not openEnd then return nil end
    local buf, j, n = {}, openEnd + 1, #raw
    while j <= n do
        local c = raw:sub(j, j)
        if c == "\\" and j < n then
            buf[#buf + 1] = c
            buf[#buf + 1] = raw:sub(j + 1, j + 1)
            j = j + 2
        elseif c == '"' then
            return table.concat(buf)
        else
            buf[#buf + 1] = c
            j = j + 1
        end
    end
    return nil -- unterminated string, malformed line
end

-- purpose-built parser for the bridge file's fixed schema -- not a general
-- JSON parser, just pulls the known fields out safely.
local function parseEntry(raw)
    if not raw or raw == "" then return nil end
    local ok, entry = pcall(function()
        local header = extractJsonString(raw, "header")
        local line   = extractJsonString(raw, "line")
        local album  = extractJsonString(raw, "album")
        local cover  = extractJsonString(raw, "cover")
        local ts        = raw:match('"ts"%s*:%s*([%d%.]+)')
        local startMs    = raw:match('"start_ms"%s*:%s*(%-?%d+)')
        local currentMs  = raw:match('"current_ms"%s*:%s*(%-?%d+)')
        local endMs       = raw:match('"end_ms"%s*:%s*(%-?%d+)')
        local isPlayingS   = raw:match('"is_playing"%s*:%s*(%a+)')
        if header == nil and line == nil then return nil end
        return {
            header    = stripAstral(jsonUnescape(header or "")),
            line      = stripAstral(jsonUnescape(line or "")),
            album     = stripAstral(jsonUnescape(album or "")),
            cover     = jsonUnescape(cover or ""), -- filesystem path, leave astral-untouched
            ts        = tonumber(ts) or 0,
            startMs   = tonumber(startMs) or 0,
            currentMs = tonumber(currentMs) or 0,
            endMs     = tonumber(endMs) or 0,
            isPlaying = isPlayingS == "true",
        }
    end)
    if ok then return entry end
    return nil
end

-- splits "Artist - Title" into artist/song. Matches the FIRST " - " only
-- (lazy match), which mirrors how the Python side builds the header
-- (f"{artist} - {title}"). NOTE: if an artist name itself contains " - ",
-- this will split in the wrong place -- ask the Python side to send
-- "artist"/"track" as separate JSON fields if that turns out to matter.
local function splitHeader(header)
    if not header or header == "" then return "", "" end
    local artist, song = header:match("^(.-) %- (.+)$")
    if artist then return artist, song end
    return "", header
end

local function fmtTime(ms)
    ms = mmax(0, ms or 0)
    local totalSec = floor(ms / 1000)
    local m = floor(totalSec / 60)
    local s = totalSec % 60
    return string.format("%d:%02d", m, s)
end

-- ── texture loading (album cover) ───────────────────────────────────────
-- draw.CreateTexture takes a raw RGBA buffer + width/height, not a file
-- path, so loading a cover means: read the jpeg bytes off disk, decode
-- with common.DecodeJPEG, hand the resulting buffer to CreateTexture, then
-- draw it with draw.SetTexture(tex) + draw.FilledRect(...) (there's no
-- separate "draw textured rect" call -- SetTexture just changes what the
-- next shape-drawing call uses). There's no documented texture-free call,
-- so a replaced texture is just dropped and left to the Lua GC.
local texState = { path = nil, id = nil }

-- file.* only accepts filenames relative to the aimware directory, but the
-- Python bridge writes an absolute Windows path into `cover` -- strip it
-- down to just the filename before handing it to file.Read.
local function basename(path)
    if not path or path == "" then return path end
    return path:match("([^\\/]+)$") or path
end

local function loadCover(path)
    if not path or path == "" then return end
    if texState.path == path and texState.id then return end -- already loaded

    local name = basename(path)
    local ok = pcall(function()
        local raw = file.Read(name)
        if not raw or raw == "" then
            print("[lyrics_display] cover file empty/missing: " .. tostring(name))
            return
        end
        local rgba, w, h = common.DecodeJPEG(raw)
        if not rgba then
            print("[lyrics_display] cover JPEG decode failed: " .. tostring(name))
            return
        end
        local id = draw.CreateTexture(rgba, w, h)
        if id then
            texState.id = id
            texState.path = path
        end
    end)
    if not ok then
        print("[lyrics_display] cover load errored for " .. tostring(name))
    end
end

local function drawCover(x, y, size)
    if not texState.id then return false end
    local ok = pcall(function()
        setcol({ 255, 255, 255, 255 }) -- full white -- otherwise the texture gets
        -- multiplied by whatever color was last set (e.g. the card's dim
        -- section/border fill), which is what was making it look dark
        draw.SetTexture(texState.id)
        draw.FilledRect(rnd(x), rnd(y), rnd(x + size), rnd(y + size))
        draw.SetTexture(nil) -- reset so later shapes (progress bar etc.) aren't textured too
    end)
    return ok
end

-- ── control channel (Lua -> Python) ────────────────────────────────────
-- Writes {"cmd":"...", "seq":N}. `seq` is our own clock in ms rather than
-- an incrementing counter, since a script reload would reset a counter
-- back to 0 -- the Python side needs a value that only ever goes up.
-- IMPORTANT: the Python bridge doesn't read this file yet. This just gets
-- the button wired and the schema locked in; Python needs a small addition
-- to poll CONTROL_PATH and call the matching spotipy playback call.
local function sendControl(cmd)
    local payload = string.format('{"cmd":"%s","seq":%d}', cmd, rnd(now() * 1000))
    writeFile(CONTROL_PATH, payload)
end

-- ── playback progress (client-side interpolation) ──────────────────────
-- The bridge file only updates every ~1.2s. To animate the progress bar
-- smoothly in between polls, we anchor to the last known (currentMs, our
-- own now()) pair and extrapolate forward using our own clock -- we can't
-- use wall-clock time here since there's no os.* access and the game
-- clock isn't epoch-based anyway.
local prog = { baseMs = 0, baseAt = 0, endMs = 0, isPlaying = false }

local function updateProgress(entry)
    prog.baseMs    = entry.currentMs
    prog.baseAt    = now()
    prog.endMs     = entry.endMs
    prog.isPlaying = entry.isPlaying
end

local function displayMs()
    local ms = prog.baseMs
    if prog.isPlaying then
        ms = ms + (now() - prog.baseAt) * 1000
    end
    return clamp(ms, 0, mmax(prog.endMs, 0)), prog.endMs
end

-- ── now playing card ────────────────────────────────────────────────────
-- Draws cover art (or a placeholder) + artist/song text + progress bar.
-- Used for both the live display and the drag-preview while the menu is
-- open, so positioning what you see is exactly what you get.
local function drawCard(cx, topY, alpha, artist, song, curMs, endMs)
    ALPHA = alpha
    local pad = CARD.pad
    local artistLabel = (artist ~= "" and artist) or "Unknown Artist"
    local songLabel   = (song ~= "" and song) or "Unknown Track"

    pcall(function() draw.SetFont(FONT_B) end)
    local wArtist = textw(artistLabel)
    pcall(function() draw.SetFont(FONT) end)
    local wSong = textw(songLabel)
    local textW = mmax(wArtist, wSong)

    local rowW  = pad + CARD.coverSize + CARD.gap + textW + pad
    local cardH = pad + CARD.coverSize + CARD.barGap + CARD.barH + pad
    local bx = floor(cx - rowW / 2 + 0.5)
    local by = floor(topY + 0.5)

    rbox(bx, by, rowW, cardH, 10, T.section, T.border)

    local coverX, coverY = bx + pad, by + pad
    if not drawCover(coverX, coverY, CARD.coverSize) then
        rbox(coverX, coverY, CARD.coverSize, CARD.coverSize, 6, { 40, 40, 50, 255 }, T.border)
        text(coverX + CARD.coverSize / 2, coverY + CARD.coverSize / 2 - 8, T.textdim, MUSIC_GLYPH, FONT_B, "center")
    end

    local tx = coverX + CARD.coverSize + CARD.gap
    local ty = by + pad + 4
    text(tx, ty, T.texthi, artistLabel, FONT_B)
    text(tx, ty + 22, T.textdim, songLabel, FONT)

    local barY = by + pad + CARD.coverSize + CARD.barGap - CARD.barH
    local barW = rowW - pad * 2
    rfill(bx + pad, barY, barW, CARD.barH, CARD.barH / 2, { 44, 44, 56, 255 })
    if endMs > 0 then
        local frac = clamp(curMs / endMs, 0, 1)
        if frac > 0.01 then
            rfill(bx + pad, barY, barW * frac, CARD.barH, CARD.barH / 2, T.accent)
        end
        ALPHA = alpha * 0.85
        text(bx + pad, barY - 15, T.textdim, fmtTime(curMs), FONT)
        text(bx + rowW - pad, barY - 15, T.textdim, fmtTime(endMs), FONT, "right")
        ALPHA = alpha
    end

    ALPHA = 1
    return { x = bx, y = by, w = rowW, h = cardH }
end

-- ── lyric line (unchanged slide/crossfade look) ─────────────────────────
local function drawLyricLine(px, py, label, a, hH, dy, color)
    if label == nil or label == "" then return end
    color = color or T.accent
    local padX = 12
    local boxW = padX * 2 + textw(label)
    local bx = floor(px - boxW / 2 + 0.5)
    local by = floor(py - hH / 2 + dy + 0.5)
    ALPHA = a
    rbox(bx, by, boxW, hH, 8, T.section, T.border)
    rfill(bx, by, 3, hH, 3, color)
    text(bx + padX, by + (hH - 16) / 2, T.texthi, label, FONT)
    ALPHA = 1
end

-- picks a random, reasonably bright RGB triple for the lyric accent stripe
local function randColor()
    local ok, c = pcall(function()
        return { math.random(90, 255), math.random(90, 255), math.random(90, 255) }
    end)
    if ok then return c end
    return { T.texthi[1], T.texthi[2], T.texthi[3] }
end

-- ── state ───────────────────────────────────────────────────────────────
local current = nil
local lastPoll = 0
local POLL_INTERVAL = 0.35

local cardArtist, cardSong = "", ""
local lyricsEnabled = true

local prevLine = nil
local lyricCur, lyricPrev = "", nil
local lyricT = 1
local LYRIC_TRANS_SPEED = 7
local lyricColor     = { T.texthi[1], T.texthi[2], T.texthi[3] }
local lyricPrevColor = nil

-- two independently draggable elements: the now-playing card and the
-- lyric line. Each gets its own position/drag state; makeDragState's
-- defaultY lets each pick its own starting spot before the user has
-- dragged it anywhere.
local function makeDragState(defaultY)
    return {
        x_off = 0, y_off = nil, defaultY = defaultY,
        drag = false, snapX = false, snapY = false,
        pendX = 0, pendY = 0,
        rect = nil, lmx = 0, lmy = 0,
    }
end

local cardBox  = makeDragState(function(sh) return sh - 180 end)
local lyricBox = makeDragState(function(sh) return sh - 70 end)

local reveal = 0
local ANIM_OPEN = 13
local HL_SNAP_IN, HL_SNAP_OUT, HL_DEAD = 12, 18, 28

local DT, last = 0, nil

local function boxPos(state, sw, sh)
    local px = sw / 2 + state.x_off
    local py = state.y_off and (sh / 2 + state.y_off) or state.defaultY(sh)
    return px, py
end

-- Handles grab/drag/snap-to-center/clamp for one draggable box. Mutates
-- `state` in place and returns its resolved (x, y) for this frame. Shared
-- by cardBox and lyricBox so the drag behavior stays identical for both
-- without duplicating the snap math twice.
local function updateDrag(state, sw, sh, cx, cy, mx, my)
    local x, y = boxPos(state, sw, sh)

    if ms.pressed and not ms.consumed then
        local grab = state.rect
        if grab and mx >= grab.x and mx <= grab.x + grab.w and my >= grab.y and my <= grab.y + grab.h then
            state.drag = true; ms.consumed = true
        end
        state.snapX, state.snapY = mabs(x - cx) < 0.5, mabs(y - cy) < 0.5
        state.pendX, state.pendY = 0, 0
        state.lmx, state.lmy = mx, my
    end
    if not ms.down then state.drag = false; state.pendX, state.pendY = 0, 0 end

    local hw, hh = (state.rect and state.rect.w / 2 or 90), (state.rect and state.rect.h / 2 or 40)
    local minX, maxX = HL_DEAD + hw, sw - HL_DEAD - hw
    local minY, maxY = HL_DEAD + hh, sh - HL_DEAD - hh

    if state.drag then
        ms.consumed = true
        local dx, dy = mx - state.lmx, my - state.lmy
        if dx ~= 0 then
            if state.snapX then
                state.pendX = state.pendX + dx
                if mabs(state.pendX) > HL_SNAP_OUT then
                    x = cx + (state.pendX >= 0 and 1 or -1) * (mabs(state.pendX) - HL_SNAP_OUT)
                    state.snapX, state.pendX = false, 0
                else x = cx end
            else
                x = x + dx
                if mabs(x - cx) < HL_SNAP_IN then x, state.snapX, state.pendX = cx, true, 0 end
            end
        end
        if dy ~= 0 then
            if state.snapY then
                state.pendY = state.pendY + dy
                if mabs(state.pendY) > HL_SNAP_OUT then
                    y = cy + (state.pendY >= 0 and 1 or -1) * (mabs(state.pendY) - HL_SNAP_OUT)
                    state.snapY, state.pendY = false, 0
                else y = cy end
            else
                y = y + dy
                if mabs(y - cy) < HL_SNAP_IN then y, state.snapY, state.pendY = cy, true, 0 end
            end
        end
        if minX <= maxX then x = clamp(x, minX, maxX) end
        if minY <= maxY then y = clamp(y, minY, maxY) end
        state.x_off, state.y_off = x - cx, y - cy

        ALPHA = 0.55
        if state.snapX or mabs(x - cx) < 0.5 then rect(cx, 0, 1, sh, T.accent) end
        if state.snapY or mabs(y - cy) < 0.5 then rect(0, cy, sw, 1, T.accent) end
        ALPHA = 1
    end
    state.lmx, state.lmy = mx, my

    return x, y
end

local function easeOutCubic(t) t = clamp(t, 0, 1); local u = 1 - t; return 1 - u * u * u end
local function smoother(x)
    x = clamp(x, 0, 1)
    return x * x * x * (x * (x * 6 - 15) + 10)
end

-- ── menu reference (fade when menu is closed vs open) ────────────────────
local menuRef
local function resolveMenuRef()
    pcall(function() menuRef = gui.Reference("MENU") end)
end

local _lastDebugPrint = 0

local function pollFile(t)
    if t - lastPoll < POLL_INTERVAL then return end
    lastPoll = t
    local raw = readLastLine(FIILE)

    if t - _lastDebugPrint > 2 then
        _lastDebugPrint = t
        if raw == nil then
            print("[lyrics_display] no line read from '" .. FIILE .. "' -- file missing, empty, or wrong path")
        else
            print("[lyrics_display] raw: " .. tostring(raw))
        end
    end

    local entry = parseEntry(raw)
    if not entry then return end
    current = entry

    cardArtist, cardSong = splitHeader(entry.header)
    updateProgress(entry)
    loadCover(entry.cover)

    if entry.line ~= "" and entry.line ~= prevLine then
        lyricPrev = lyricCur
        lyricCur  = entry.line
        lyricT    = 0
        prevLine  = entry.line
        lyricPrevColor = lyricColor
        lyricColor     = randColor()
    elseif entry.line == "" and prevLine ~= "" then
        lyricPrev = lyricCur
        lyricCur  = ""
        lyricT    = 0
        prevLine  = ""
        lyricPrevColor = lyricColor
    end
end

local function on_draw()
    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end

    if not fontsReady then return end

    updateMouse()

    local open = true
    if menuRef then
        local ok, v = pcall(function() return menuRef:IsActive() end)
        if ok then open = v end
    end

    local t = now()
    DT = last and clamp(t - last, 0, 0.1) or 0
    last = t

    pollFile(t)
    lyricT = clamp(lyricT + DT * LYRIC_TRANS_SPEED, 0, 1)

    reveal = reveal + ((open and 1 or 0) - reveal) * clamp(DT * ANIM_OPEN, 0, 1)

    pcall(function() draw.SetFont(FONT) end)
    local rowH = 30
    pcall(function()
        local _, h1 = draw.GetTextSize("Ayg")
        if h1 and h1 > 4 then rowH = floor(h1 + 0.5) + 16 end
    end)

    local cx, cy = sw / 2, sh / 2
    local mx, my = ms.x, ms.y
    local curMs, endMs = displayMs()

    -- ── menu OPEN: both boxes independently draggable + control row ────
    if reveal > 0.02 then
        local e = easeOutCubic(reveal)
        local slide = (1 - e) * 10

        -- card: drag first so it gets first claim on the click (buttons
        -- below it are checked after, guarded by ms.consumed)
        local cardX, cardY = updateDrag(cardBox, sw, sh, cx, cy, mx, my)
        local cardRect = drawCard(cardX, cardY + slide, e, cardArtist, cardSong, curMs, endMs)
        cardBox.rect = cardRect

        -- control row lives under the card specifically, not the lyric box
        local btnH, btnGap = 26, 6
        local btnW = { prev = 34, play = 34, next = 34, lyrics = 92 }
        local totalW = btnW.prev + btnW.play + btnW.next + btnW.lyrics + btnGap * 3
        local rowX = cardRect.x + cardRect.w / 2 - totalW / 2
        local rowY = cardRect.y + cardRect.h + 10 + slide

        local defs = {
            { label = "<<",                                             w = btnW.prev,   action = function() sendControl("prev") end },
            { label = prog.isPlaying and "||" or ">",                   w = btnW.play,   action = function() sendControl("toggle_play") end },
            { label = ">>",                                             w = btnW.next,   action = function() sendControl("next") end },
            { label = lyricsEnabled and "Lyrics: ON" or "Lyrics: OFF",  w = btnW.lyrics, action = function() lyricsEnabled = not lyricsEnabled end },
        }

        local cursorX = rowX
        for _, b in ipairs(defs) do
            local bx2, by2 = cursorX, rowY
            local hov = hovering(bx2, by2, b.w, btnH)
            ALPHA = e
            local fill = hov and { 34, 34, 44, 255 } or T.section
            rbox(bx2, by2, b.w, btnH, 7, fill, hov and T.accent or T.border)
            text(bx2 + b.w / 2, by2 + (btnH - 14) / 2, T.texthi, b.label, FONT_B, "center")
            ALPHA = 1
            if hov and ms.pressed and not ms.consumed then
                ms.consumed = true
                b.action()
            end
            cursorX = cursorX + b.w + btnGap
        end

        ALPHA = e
        local cardHint = "drag card to move"
        text(cardX + 1, rowY + btnH + 9, { 0, 0, 0, 235 }, cardHint, FONT, "center")
        text(cardX, rowY + btnH + 8, T.texthi, cardHint, FONT, "center")
        ALPHA = 1

        -- lyric line: independent position, dragged/previewed separately.
        -- Shows the real current line if there is one, otherwise a sample
        -- so there's something to grab and position.
        local lyricX, lyricY = updateDrag(lyricBox, sw, sh, cx, cy, mx, my)
        local previewLabel = (lyricCur ~= "" and lyricCur) or "Sample lyric line"
        drawLyricLine(lyricX, lyricY + slide, previewLabel, e, rowH, 0, lyricColor)
        local lw = 12 * 2 + textw(previewLabel)
        lyricBox.rect = { x = lyricX - lw / 2, y = lyricY + slide - rowH / 2, w = lw, h = rowH }

        ALPHA = e
        local lyricHint = "drag lyrics to move"
        text(lyricX + 1, lyricY + slide + rowH / 2 + 15, { 0, 0, 0, 235 }, lyricHint, FONT, "center")
        text(lyricX, lyricY + slide + rowH / 2 + 14, T.texthi, lyricHint, FONT, "center")
        ALPHA = 1
        return
    end

    -- ── menu CLOSED: live card + optional sliding lyric line ───────────
    local cardX, cardY = boxPos(cardBox, sw, sh)
    drawCard(cardX, cardY, 1, cardArtist, cardSong, curMs, endMs)

    if lyricsEnabled and (lyricCur ~= "" or (lyricPrev and lyricPrev ~= "" and lyricT < 1)) then
        local lyricX, lyricY = boxPos(lyricBox, sw, sh)
        local slideDist = 16
        local eNew = smoother(lyricT)
        if lyricCur ~= "" then
            drawLyricLine(lyricX, lyricY, lyricCur, eNew, rowH, (1 - eNew) * slideDist, lyricColor)
        end
        if lyricPrev and lyricPrev ~= "" and lyricT < 1 then
            drawLyricLine(lyricX, lyricY, lyricPrev, 1 - eNew, rowH, -eNew * slideDist, lyricPrevColor)
        end
    end
end

pickFonts() -- synchronous fallback font, immediately usable
installFonts() -- kicks off async http.Get downloads; upgrades fonts whenever each lands
_getMouse = resolveMouse()
_clock    = resolveClock()
resolveMenuRef()
pcall(function() math.randomseed(floor(now() * 1000) % 2147483647) end)

if not embedded then
    callbacks.Register("Draw", on_draw)
end

print("[lyrics_display] loaded, reading from " .. tostring(FIILE))

if embedded then
    return { Draw = on_draw }
end

return M