--[[--
Pen notes: blank canvases attached to the book, a chapter, a page or a
highlight. Pure functions over plain tables so the store can be tested
without KOReader.

A note is { anchor = <anchor>, datetime = <os.time()>, strokes = {...} }.
Anchor shapes:
  book:      { kind = "book" }
  chapter:   { kind = "chapter", page = N, xpointer = str|nil, title = str }
             (page/xpointer identify the TOC entry)
  page:      { kind = "page", page = N, xpointer = str|nil }
  highlight: { kind = "highlight", datetime = str, page = N|nil, text = str|nil }
             (datetime is KOReader's immutable annotation id)

@module pencil.lib.notes
--]]--

local Geometry = require("lib/geometry")

local Notes = {}

Notes.VERSION = 1
Notes.KIND_BOOK = "book"
Notes.KIND_CHAPTER = "chapter"
Notes.KIND_PAGE = "page"
Notes.KIND_HIGHLIGHT = "highlight"

local KINDS = {
    [Notes.KIND_BOOK] = true,
    [Notes.KIND_CHAPTER] = true,
    [Notes.KIND_PAGE] = true,
    [Notes.KIND_HIGHLIGHT] = true,
}

function Notes.isKind(kind)
    return KINDS[kind] == true
end

function Notes.assertAnchor(anchor)
    assert(type(anchor) == "table", "anchor must be a table")
    assert(Notes.isKind(anchor.kind), "unknown anchor kind: " .. tostring(anchor.kind))
    if anchor.kind == Notes.KIND_HIGHLIGHT then
        assert(type(anchor.datetime) == "string" and anchor.datetime ~= "",
            "highlight anchor needs the annotation datetime")
    elseif anchor.kind ~= Notes.KIND_BOOK then
        assert(anchor.page ~= nil or anchor.xpointer ~= nil,
            anchor.kind .. " anchor needs a page or an xpointer")
    end
end

function Notes.newStore()
    return { version = Notes.VERSION, notes = {} }
end

function Notes.newNote(anchor, now)
    Notes.assertAnchor(anchor)
    assert(type(now) == "number", "now must be a timestamp")
    return { anchor = anchor, datetime = now, strokes = {} }
end

local function identityPage(anchor)
    return anchor.page
end

--- Whether two anchors denote the same place.
-- resolve_page(anchor) maps a page anchor to its page in the current layout;
-- rolling documents re-derive it from the xpointer because page numbers
-- shift with font and layout changes. Defaults to the stored page.
function Notes.sameAnchor(a, b, resolve_page)
    Notes.assertAnchor(a)
    Notes.assertAnchor(b)
    resolve_page = resolve_page or identityPage
    if a.kind ~= b.kind then return false end
    if a.kind == Notes.KIND_BOOK then
        return true
    elseif a.kind == Notes.KIND_HIGHLIGHT then
        return a.datetime == b.datetime
    elseif a.kind == Notes.KIND_CHAPTER then
        if a.xpointer and b.xpointer then
            return a.xpointer == b.xpointer
        end
        return a.page == b.page
    else
        if a.xpointer and a.xpointer == b.xpointer then
            return true
        end
        return resolve_page(a) == resolve_page(b)
    end
end

--- Returns the note for the anchor and its index, or nil.
function Notes.find(store, anchor, resolve_page)
    for i, note in ipairs(store.notes) do
        if Notes.sameAnchor(note.anchor, anchor, resolve_page) then
            return note, i
        end
    end
    return nil
end

function Notes.add(store, note)
    assert(note.anchor and note.strokes, "not a note")
    table.insert(store.notes, note)
    return note
end

--- Removes the note (by identity). Returns true if it was in the store.
function Notes.remove(store, note)
    for i, candidate in ipairs(store.notes) do
        if candidate == note then
            table.remove(store.notes, i)
            return true
        end
    end
    return false
end

function Notes.isEmpty(note)
    return #note.strokes == 0
end

--- Removes every stroke within threshold pixels of (x, y).
-- Returns the removed strokes as { {index = i, stroke = s}, ... } in
-- ascending index order, so Notes.restore can put them back, or nil.
function Notes.eraseAt(strokes, x, y, threshold)
    assert(type(threshold) == "number" and threshold > 0, "threshold must be positive")
    local removed = nil
    for i = #strokes, 1, -1 do
        if Geometry.isPointNearStroke(x, y, strokes[i], threshold) then
            removed = removed or {}
            table.insert(removed, 1, { index = i, stroke = table.remove(strokes, i) })
        end
    end
    return removed
end

--- Re-inserts strokes removed by Notes.eraseAt at their original indices.
function Notes.restore(strokes, removed)
    for _, entry in ipairs(removed) do
        table.insert(strokes, entry.index, entry.stroke)
    end
end

--- Store as written to disk. convert(stroke) strips non-serialisable
-- fields (colors are cdata); see Pencil:strokeToSaveable.
function Notes.toSaveable(store, convert)
    local notes = {}
    for i, note in ipairs(store.notes) do
        local strokes = {}
        for j, stroke in ipairs(note.strokes) do
            strokes[j] = convert(stroke)
        end
        notes[i] = { anchor = note.anchor, datetime = note.datetime, strokes = strokes }
    end
    return { version = Notes.VERSION, notes = notes }
end

local function isValidSavedNote(saved)
    if type(saved) ~= "table" or type(saved.strokes) ~= "table" then return false end
    return pcall(Notes.assertAnchor, saved.anchor)
end

--- Store rebuilt from disk data. Malformed or empty notes are dropped;
-- convert(saved_stroke) is the inverse of the one given to toSaveable.
function Notes.fromSaved(data, convert)
    local store = Notes.newStore()
    if type(data) ~= "table" or type(data.notes) ~= "table" then
        return store
    end
    for _, saved in ipairs(data.notes) do
        if isValidSavedNote(saved) and #saved.strokes > 0 then
            local strokes = {}
            for j, stroke in ipairs(saved.strokes) do
                strokes[j] = convert(stroke)
            end
            table.insert(store.notes, {
                anchor = saved.anchor,
                datetime = saved.datetime or 0,
                strokes = strokes,
            })
        end
    end
    return store
end

--- First max_chars characters of a UTF-8 string, with an ellipsis if cut.
-- Newlines and runs of whitespace collapse to a single space.
function Notes.snippet(text, max_chars)
    assert(type(max_chars) == "number" and max_chars > 0, "max_chars must be positive")
    if type(text) ~= "string" then return "" end
    text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local chars = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #chars == max_chars then
            return table.concat(chars) .. "…"
        end
        chars[#chars + 1] = char
    end
    return table.concat(chars)
end

return Notes
