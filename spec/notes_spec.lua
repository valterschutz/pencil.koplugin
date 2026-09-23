--[[--
Unit tests for the pen note store (lib/notes.lua).
Run with: busted spec/notes_spec.lua
--]]--

package.path = package.path .. ";pencil.koplugin/?.lua"

local Notes = require("lib/notes")

local function stroke(x, y)
    return { tool = "pen", width = 3, points = { { x = x, y = y } }, color = "cdata" }
end

describe("Notes", function()

    describe("assertAnchor", function()
        it("accepts every kind with its required fields", function()
            Notes.assertAnchor({ kind = "book" })
            Notes.assertAnchor({ kind = "page", page = 3 })
            Notes.assertAnchor({ kind = "page", xpointer = "/body/p[1]" })
            Notes.assertAnchor({ kind = "chapter", page = 10, title = "One" })
            Notes.assertAnchor({ kind = "highlight", datetime = "2026-09-23 10:00:00" })
        end)

        it("rejects unknown kinds and missing identity", function()
            assert.has_error(function() Notes.assertAnchor({ kind = "paragraph" }) end)
            assert.has_error(function() Notes.assertAnchor({ kind = "page" }) end)
            assert.has_error(function() Notes.assertAnchor({ kind = "chapter" }) end)
            assert.has_error(function() Notes.assertAnchor({ kind = "highlight", datetime = "" }) end)
            assert.has_error(function() Notes.assertAnchor("book") end)
        end)
    end)

    describe("sameAnchor", function()
        it("never matches across kinds", function()
            assert.is_false(Notes.sameAnchor({ kind = "page", page = 1 }, { kind = "chapter", page = 1 }))
            assert.is_false(Notes.sameAnchor({ kind = "book" }, { kind = "page", page = 1 }))
        end)

        it("treats every book anchor as the same note", function()
            assert.is_true(Notes.sameAnchor({ kind = "book" }, { kind = "book" }))
        end)

        it("matches highlights by annotation datetime only", function()
            local a = { kind = "highlight", datetime = "d1", page = 1, text = "x" }
            assert.is_true(Notes.sameAnchor(a, { kind = "highlight", datetime = "d1", page = 9 }))
            assert.is_false(Notes.sameAnchor(a, { kind = "highlight", datetime = "d2", page = 1 }))
        end)

        it("matches chapters by xpointer when both have one, else by page", function()
            local a = { kind = "chapter", page = 10, xpointer = "/x/1", title = "A" }
            assert.is_true(Notes.sameAnchor(a, { kind = "chapter", page = 99, xpointer = "/x/1" }))
            assert.is_false(Notes.sameAnchor(a, { kind = "chapter", page = 10, xpointer = "/x/2" }))
            local paged = { kind = "chapter", page = 10, title = "A" }
            assert.is_true(Notes.sameAnchor(paged, { kind = "chapter", page = 10, title = "B" }))
            assert.is_false(Notes.sameAnchor(paged, { kind = "chapter", page = 11 }))
        end)

        it("matches pages by stored page without a resolver", function()
            assert.is_true(Notes.sameAnchor({ kind = "page", page = 4 }, { kind = "page", page = 4 }))
            assert.is_false(Notes.sameAnchor({ kind = "page", page = 4 }, { kind = "page", page = 5 }))
        end)

        it("matches pages through the resolver when xpointers differ", function()
            local layout = { ["/a"] = 7, ["/b"] = 7, ["/c"] = 8 }
            local resolve = function(anchor) return layout[anchor.xpointer] or anchor.page end
            local a = { kind = "page", page = 12, xpointer = "/a" }
            assert.is_true(Notes.sameAnchor(a, { kind = "page", page = 30, xpointer = "/b" }, resolve))
            assert.is_false(Notes.sameAnchor(a, { kind = "page", page = 12, xpointer = "/c" }, resolve))
        end)

        it("matches pages by identical xpointer before resolving", function()
            local resolve = function() error("resolver must not run") end
            local a = { kind = "page", page = 1, xpointer = "/same" }
            assert.is_true(Notes.sameAnchor(a, { kind = "page", page = 2, xpointer = "/same" }, resolve))
        end)
    end)

    describe("store", function()
        it("finds, adds and removes notes by identity", function()
            local store = Notes.newStore()
            assert.is_nil(Notes.find(store, { kind = "book" }))
            local note = Notes.add(store, Notes.newNote({ kind = "book" }, 100))
            local found, index = Notes.find(store, { kind = "book" })
            assert.equals(note, found)
            assert.equals(1, index)
            assert.is_true(Notes.isEmpty(note))
            assert.is_true(Notes.remove(store, note))
            assert.is_false(Notes.remove(store, note))
            assert.is_nil(Notes.find(store, { kind = "book" }))
        end)

        it("requires a timestamp for a new note", function()
            assert.has_error(function() Notes.newNote({ kind = "book" }) end)
        end)

        it("rejects notes without pages", function()
            assert.has_error(function() Notes.add(Notes.newStore(), { anchor = { kind = "book" }, strokes = {} }) end)
            assert.has_error(function() Notes.add(Notes.newStore(), { anchor = { kind = "book" }, pages = {} }) end)
        end)
    end)

    describe("pages", function()
        it("starts with one blank page and adds pages after a given one", function()
            local note = Notes.newNote({ kind = "book" }, 1)
            assert.equals(1, #note.pages)
            assert.is_true(Notes.isPageEmpty(note.pages[1]))
            local last, last_index = Notes.addPage(note)
            assert.equals(2, last_index)
            assert.equals(last, note.pages[2])
            local middle, middle_index = Notes.addPage(note, 1)
            assert.equals(2, middle_index)
            assert.equals(middle, note.pages[2])
            assert.equals(last, note.pages[3])
            assert.has_error(function() Notes.addPage(note, 4) end)
        end)

        it("is empty only when every page is blank", function()
            local note = Notes.newNote({ kind = "book" }, 1)
            Notes.addPage(note)
            assert.is_true(Notes.isEmpty(note))
            table.insert(note.pages[2].strokes, stroke(1, 1))
            assert.is_false(Notes.isEmpty(note))
        end)

        it("prunes blank pages but keeps one", function()
            local note = Notes.newNote({ kind = "book" }, 1)
            Notes.addPage(note)
            Notes.addPage(note)
            table.insert(note.pages[2].strokes, stroke(1, 1))
            assert.equals(2, Notes.prunePages(note))
            assert.equals(1, #note.pages)
            assert.equals(1, note.pages[1].strokes[1].points[1].x)

            local blank = Notes.newNote({ kind = "book" }, 1)
            Notes.addPage(blank)
            assert.equals(1, Notes.prunePages(blank))
            assert.equals(1, #blank.pages)
            assert.equals(0, Notes.prunePages(blank))
        end)

        it("removes pages and never leaves a note without one", function()
            local note = Notes.newNote({ kind = "book" }, 1)
            table.insert(note.pages[1].strokes, stroke(1, 1))
            local second = Notes.addPage(note)
            assert.equals(second, Notes.removePage(note, 2))
            assert.equals(1, #note.pages)
            assert.has_error(function() Notes.removePage(note, 2) end)
            Notes.removePage(note, 1)
            assert.equals(1, #note.pages)
            assert.is_true(Notes.isEmpty(note))
        end)

        it("clears a note down to one blank page in place", function()
            local note = Notes.newNote({ kind = "book" }, 1)
            local pages = note.pages
            table.insert(note.pages[1].strokes, stroke(1, 1))
            Notes.addPage(note)
            Notes.clearNote(note)
            assert.equals(pages, note.pages)
            assert.equals(1, #note.pages)
            assert.is_true(Notes.isEmpty(note))
        end)
    end)

    describe("eraseAt / restore", function()
        it("removes every stroke within the threshold, keeping original indices", function()
            local strokes = { stroke(0, 0), stroke(100, 100), stroke(5, 5), stroke(200, 200) }
            local removed = Notes.eraseAt(strokes, 2, 2, 10)
            assert.equals(2, #removed)
            assert.equals(1, removed[1].index)
            assert.equals(3, removed[2].index)
            assert.equals(2, #strokes)
            assert.equals(100, strokes[1].points[1].x)
            assert.equals(200, strokes[2].points[1].x)

            Notes.restore(strokes, removed)
            assert.equals(4, #strokes)
            assert.equals(0, strokes[1].points[1].x)
            assert.equals(100, strokes[2].points[1].x)
            assert.equals(5, strokes[3].points[1].x)
            assert.equals(200, strokes[4].points[1].x)
        end)

        it("returns nil when nothing is near", function()
            local strokes = { stroke(0, 0) }
            assert.is_nil(Notes.eraseAt(strokes, 50, 50, 10))
            assert.equals(1, #strokes)
        end)

        it("rejects a non-positive threshold", function()
            assert.has_error(function() Notes.eraseAt({}, 0, 0, 0) end)
        end)
    end)

    describe("toSaveable / fromSaved", function()
        local function strip(s)
            return { tool = s.tool, width = s.width, points = s.points }
        end
        local function restore(s)
            return { tool = s.tool, width = s.width, points = s.points, color = "cdata" }
        end

        it("round-trips notes through the stroke converters", function()
            local store = Notes.newStore()
            local note = Notes.add(store, Notes.newNote({ kind = "page", page = 2, xpointer = "/p" }, 42))
            table.insert(note.pages[1].strokes, stroke(1, 2))
            Notes.addPage(note)  -- blank, left out on disk
            Notes.addPage(note)
            table.insert(note.pages[3].strokes, stroke(3, 4))
            local saved = Notes.toSaveable(store, strip)
            assert.equals(Notes.VERSION, saved.version)
            assert.equals(2, #saved.notes[1].pages)
            assert.is_nil(saved.notes[1].pages[1].strokes[1].color)
            assert.equals(42, saved.notes[1].datetime)

            local loaded = Notes.fromSaved(saved, restore)
            assert.equals(1, #loaded.notes)
            assert.same({ kind = "page", page = 2, xpointer = "/p" }, loaded.notes[1].anchor)
            assert.equals(2, #loaded.notes[1].pages)
            assert.equals("cdata", loaded.notes[1].pages[1].strokes[1].color)
            assert.equals(1, loaded.notes[1].pages[1].strokes[1].points[1].x)
            assert.equals(3, loaded.notes[1].pages[2].strokes[1].points[1].x)
        end)

        it("loads version 1 notes with a flat strokes array as one page", function()
            local data = {
                version = 1,
                notes = { { anchor = { kind = "book" }, datetime = 7, strokes = { stroke(1, 1), stroke(2, 2) } } },
            }
            local loaded = Notes.fromSaved(data, restore)
            assert.equals(1, #loaded.notes)
            assert.equals(1, #loaded.notes[1].pages)
            assert.equals(2, #loaded.notes[1].pages[1].strokes)
            assert.equals(7, loaded.notes[1].datetime)
        end)

        it("drops empty and malformed notes and tolerates garbage input", function()
            local data = {
                version = 1,
                notes = {
                    { anchor = { kind = "book" }, pages = {} },
                    { anchor = { kind = "book" }, pages = { { strokes = {} }, "junk", { nostrokes = true } } },
                    { anchor = { kind = "nope" }, pages = { { strokes = { stroke(1, 1) } } } },
                    { anchor = { kind = "page", page = 1 } },
                    "junk",
                    { anchor = { kind = "book" }, pages = { { strokes = {} }, { strokes = { stroke(1, 1) } } } },
                },
            }
            local loaded = Notes.fromSaved(data, restore)
            assert.equals(1, #loaded.notes)
            assert.equals("book", loaded.notes[1].anchor.kind)
            assert.equals(0, loaded.notes[1].datetime)
            assert.equals(1, #loaded.notes[1].pages)

            assert.equals(0, #Notes.fromSaved(nil, restore).notes)
            assert.equals(0, #Notes.fromSaved({ notes = "x" }, restore).notes)
        end)
    end)

    describe("highlightIds", function()
        it("collects the datetimes of highlight notes only", function()
            local store = Notes.newStore()
            assert.same({}, Notes.highlightIds(store))
            Notes.add(store, Notes.newNote({ kind = "page", page = 3 }, 1))
            Notes.add(store, Notes.newNote({ kind = "highlight", datetime = "2026-09-23 10:00:00" }, 2))
            Notes.add(store, Notes.newNote({ kind = "highlight", datetime = "2026-09-23 11:00:00" }, 3))
            assert.same({ ["2026-09-23 10:00:00"] = true, ["2026-09-23 11:00:00"] = true },
                Notes.highlightIds(store))
        end)
    end)

    describe("snippet", function()
        it("returns short text unchanged and cuts long text with an ellipsis", function()
            assert.equals("short", Notes.snippet("short", 10))
            assert.equals("abcde…", Notes.snippet("abcdefgh", 5))
            assert.equals("abcde", Notes.snippet("abcde", 5))
        end)

        it("counts characters, not bytes", function()
            assert.equals("åäö…", Notes.snippet("åäöü", 3))
        end)

        it("collapses whitespace and handles non-strings", function()
            assert.equals("a b c", Notes.snippet("  a \n b\t\tc  ", 20))
            assert.equals("", Notes.snippet(nil, 5))
        end)

        it("rejects a non-positive length", function()
            assert.has_error(function() Notes.snippet("x", 0) end)
        end)
    end)
end)
