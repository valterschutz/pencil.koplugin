--[[--
Pen notes: blank canvases attached to the book, a chapter, a page or a
highlight. Pure functions over plain tables so the store can be tested
without KOReader.

A note is { anchor = <anchor>, datetime = <os.time()>, pages = { <page>, ... } }
with at least one page; a page is { strokes = {...} }. Version 1 stored a
single flat strokes array, which loads as a one-page note.
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

Notes.VERSION = 2
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

function Notes.newPage()
    return { strokes = {} }
end

function Notes.newNote(anchor, now)
    Notes.assertAnchor(anchor)
    assert(type(now) == "number", "now must be a timestamp")
    return { anchor = anchor, datetime = now, pages = { Notes.newPage() } }
end

local function assertNote(note)
    assert(type(note) == "table" and note.anchor and type(note.pages) == "table" and #note.pages >= 1,
        "not a note")
end

--- Inserts a blank page after page `after` (default: at the end).
-- Returns the new page and its index.
function Notes.addPage(note, after)
    assertNote(note)
    after = after or #note.pages
    assert(type(after) == "number" and after >= 0 and after <= #note.pages,
        "page index out of range: " .. tostring(after))
    local page = Notes.newPage()
    table.insert(note.pages, after + 1, page)
    return page, after + 1
end

--- Removes the page at index. A note always keeps one page, so removing
-- the last remaining page leaves a blank one. Returns the removed page.
function Notes.removePage(note, index)
    assertNote(note)
    assert(type(index) == "number" and index >= 1 and index <= #note.pages,
        "page index out of range: " .. tostring(index))
    local page = table.remove(note.pages, index)
    if #note.pages == 0 then
        note.pages[1] = Notes.newPage()
    end
    return page
end

function Notes.isPageEmpty(page)
    return #page.strokes == 0
end

--- Drops blank pages, keeping at least one so the note stays openable.
-- Returns the number of pages removed.
function Notes.prunePages(note)
    assertNote(note)
    local removed = 0
    for i = #note.pages, 1, -1 do
        if #note.pages > 1 and Notes.isPageEmpty(note.pages[i]) then
            table.remove(note.pages, i)
            removed = removed + 1
        end
    end
    return removed
end

--- Empties the note in place: one blank page, nothing else.
function Notes.clearNote(note)
    assertNote(note)
    for i = #note.pages, 1, -1 do
        note.pages[i] = nil
    end
    note.pages[1] = Notes.newPage()
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
    assertNote(note)
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
    for _, page in ipairs(note.pages) do
        if not Notes.isPageEmpty(page) then return false end
    end
    return true
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

local function convertStrokes(strokes, convert)
    local out = {}
    for i, stroke in ipairs(strokes) do
        out[i] = convert(stroke)
    end
    return out
end

--- Store as written to disk, blank pages left out. convert(stroke) strips
-- non-serialisable fields (colors are cdata); see Pencil:strokeToSaveable.
function Notes.toSaveable(store, convert)
    local notes = {}
    for i, note in ipairs(store.notes) do
        local pages = {}
        for _, page in ipairs(note.pages) do
            if not Notes.isPageEmpty(page) then
                table.insert(pages, { strokes = convertStrokes(page.strokes, convert) })
            end
        end
        notes[i] = { anchor = note.anchor, datetime = note.datetime, pages = pages }
    end
    return { version = Notes.VERSION, notes = notes }
end

-- Pages of a saved note with their strokes converted, blank and malformed
-- pages left out. Version 1 notes carry a flat strokes array.
local function loadPages(saved, convert)
    local saved_pages = saved.pages
    if type(saved_pages) ~= "table" and type(saved.strokes) == "table" then
        saved_pages = { { strokes = saved.strokes } }
    end
    if type(saved_pages) ~= "table" then return {} end
    local pages = {}
    for _, page in ipairs(saved_pages) do
        if type(page) == "table" and type(page.strokes) == "table" and #page.strokes > 0 then
            table.insert(pages, { strokes = convertStrokes(page.strokes, convert) })
        end
    end
    return pages
end

--- Store rebuilt from disk data. Malformed or empty notes are dropped;
-- convert(saved_stroke) is the inverse of the one given to toSaveable.
function Notes.fromSaved(data, convert)
    local store = Notes.newStore()
    if type(data) ~= "table" or type(data.notes) ~= "table" then
        return store
    end
    for _, saved in ipairs(data.notes) do
        if type(saved) == "table" and pcall(Notes.assertAnchor, saved.anchor) then
            local pages = loadPages(saved, convert)
            if #pages > 0 then
                table.insert(store.notes, {
                    anchor = saved.anchor,
                    datetime = saved.datetime or 0,
                    pages = pages,
                })
            end
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
