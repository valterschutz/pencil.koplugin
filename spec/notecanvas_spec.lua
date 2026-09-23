--[[--
Unit tests for the note canvas widget (lib/notecanvas.lua).
KOReader's widget modules are stubbed just enough to construct the widget
and feed it stylus slots.
Run with: busted spec/notecanvas_spec.lua
--]]--

package.path = package.path .. ";pencil.koplugin/?.lua"

local SCREEN_W, SCREEN_H = 1264, 1680
local TITLE_H = 60
local HEADER_LINE_H = 30      -- stubbed TextBoxWidget: one line per newline-separated paragraph
local HEADER_PAD, HEADER_LINE = 10, 1

local function stubClass()
    local C = {}
    C.__index = C
    function C:extend(o)
        o = o or {}
        setmetatable(o, self)
        o.__index = o
        return o
    end
    function C:new(o)
        o = o or {}
        setmetatable(o, self)
        if o.init then o:init() end
        return o
    end
    return C
end

local clock = { now = 0 }
local screen = {
    night_mode = false,
    refreshed = {},
    bb = {
        paintRectRGB32 = function() end,
        paintRect = function() end,
    },
}
function screen:getWidth() return SCREEN_W end
function screen:getHeight() return SCREEN_H end
function screen:refreshUI(x, y, w, h) table.insert(self.refreshed, { x = x, y = y, w = w, h = h }) end

local ui = { shown = {}, closed = {}, dirty = 0 }

local function preload(name, module)
    package.preload[name] = function() return module end
end

preload("ffi/blitbuffer", { COLOR_WHITE = "white" })
preload("ui/widget/buttondialog", { new = function(_, o) return o end })
preload("ui/widget/confirmbox", { new = function(_, o) o.is_confirm = true return o end })
preload("device", {
    screen = screen,
    hasKeys = function() return false end,
    input = { group = { Back = "Back" } },
})
preload("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
preload("ui/geometry", { new = function(_, o) return o end })
preload("ui/size", {
    padding = { large = HEADER_PAD, fullscreen = 15 },
    line = { medium = HEADER_LINE },
})
preload("ui/widget/textboxwidget", {
    new = function(_, o)
        assert(o.text and o.face and o.width and o.height, "TextBoxWidget stub needs text, face, width, height")
        local _, newlines = o.text:gsub("\n", "")
        o.h = math.min(o.height, (newlines + 1) * HEADER_LINE_H)
        o.painted = 0
        o.getSize = function(self) return { w = self.width, h = self.h } end
        o.paintTo = function(self) self.painted = self.painted + 1 end
        o.free = function(self) self.freed = true end
        return o
    end,
})
preload("ui/gesturerange", { new = function(_, o) return o end })
preload("ui/widget/container/inputcontainer", stubClass())
preload("ui/widget/titlebar", {
    new = function(_, o)
        o.getHeight = function() return TITLE_H end
        o.paintTo = function() end
        o.free = function() end
        o.setTitle = function(self, text) self.title = text end
        return o
    end,
})
preload("ffi/util", {
    template = function(fmt, ...)
        local args = { ... }
        return (fmt:gsub("%%(%d)", function(i) return tostring(args[tonumber(i)]) end))
    end,
})
preload("ui/uimanager", {
    show = function(_, w) table.insert(ui.shown, w) end,
    close = function(_, w) table.insert(ui.closed, w) end,
    setDirty = function() ui.dirty = ui.dirty + 1 end,
})
preload("logger", { dbg = function() end, info = function() end, warn = function() end })
preload("ui/time", {
    now = function() return clock.now end,
    to_ms = function(t) return t end,
})
preload("gettext", function(s) return s end)

local NoteCanvas = require("lib/notecanvas")
local Notes = require("lib/notes")

local TAP_MAX_MS, TAP_MAX_PX = 500, 10

local function newPencil()
    return {
        swap_eraser_and_highlighter = false,
        finger_mode = false,
        mode_toggles = 0,
        isFingerMode = function(self) return self.finger_mode end,
        toggleInputMode = function(self)
            self.finger_mode = not self.finger_mode
            self.mode_toggles = self.mode_toggles + 1
        end,
        tool_settings = {
            pen = { width = 3, color = "black", color_name = "Black", alpha = 255 },
            highlighter = { width = 20, color = "yellow", alpha = 128 },
        },
        segments = 0,
        highlighter_segments = 0,
        transformCoordinates = function(_, x, y) return x, y end,
        drawLineSegment = function(self) self.segments = self.segments + 1 end,
        drawHighlighterSegment = function(self) self.highlighter_segments = self.highlighter_segments + 1 end,
        renderStroke = function() end,
        marker_paints = 0,
        renderFingerModeMarker = function(self) self.marker_paints = self.marker_paints + 1 end,
    }
end

local function newCanvas(note, header)
    local closed = {}
    local canvas = NoteCanvas:new{
        pencil = newPencil(),
        note = note or Notes.newNote({ kind = "book" }, 1),
        title = "Book note",
        header = header,
        tap_max_ms = TAP_MAX_MS,
        tap_max_px = TAP_MAX_PX,
        on_close = function(_, changed) table.insert(closed, changed) end,
    }
    return canvas, closed
end

local function strokes(canvas) return canvas:strokes() end
local function swipe(canvas, direction) return canvas:onSwipe(nil, { direction = direction }) end

local PEN, ERASER, HIGHLIGHTER = 1, 2, 3
local function down(canvas, x, y, tool) canvas:handleStylusSlot({ id = 0, x = x, y = y, tool = tool or PEN }) end
local function up(canvas) canvas:handleStylusSlot({ id = -1, tool = PEN }) end

describe("NoteCanvas", function()
    before_each(function()
        clock.now = 0
        screen.refreshed = {}
        ui.shown, ui.closed, ui.dirty = {}, {}, 0
    end)

    it("requires the plugin, a note with pages, tap thresholds and a close callback", function()
        local function try(o)
            o.pencil = o.pencil == nil and newPencil() or o.pencil
            if o.note == nil then o.note = Notes.newNote({ kind = "book" }, 1) end
            if o.tap_max_ms == nil then o.tap_max_ms = TAP_MAX_MS end
            if o.tap_max_px == nil then o.tap_max_px = TAP_MAX_PX end
            if o.on_close == nil then o.on_close = function() end end
            return function() NoteCanvas:new(o) end
        end
        assert.has_no.errors(try({}))
        assert.has_error(try({ pencil = false }))
        assert.has_error(try({ note = false }))
        assert.has_error(try({ note = { anchor = { kind = "book" }, strokes = {} } }))
        assert.has_error(try({ tap_max_ms = false }))
        assert.has_error(try({ tap_max_px = false }))
        assert.has_error(try({ on_close = false }))
    end)

    it("turns a pen drag into one stroke and marks the note changed", function()
        local canvas = newCanvas()
        down(canvas, 100, 200)
        assert.is_true(canvas.pen_down)
        down(canvas, 110, 210)
        down(canvas, 110, 210)  -- duplicate sample is ignored
        down(canvas, 120, 220)
        up(canvas)
        assert.is_false(canvas.pen_down)
        assert.equals(1, #strokes(canvas))
        assert.equals(3, #strokes(canvas)[1].points)
        assert.equals("pen", strokes(canvas)[1].tool)
        assert.equals(3, strokes(canvas)[1].width)
        assert.equals(2, canvas.pencil.segments)
        assert.is_true(canvas.changed)
        assert.equals(1, #canvas:undoStack())
    end)

    it("dominates the stylus over the drawing area", function()
        local canvas = newCanvas()
        assert.is_true(canvas:handleStylusSlot({ id = 0, x = 1, y = TITLE_H, tool = PEN }))
        assert.is_true(canvas:handleStylusSlot({ id = -1, tool = PEN }))
        assert.is_true(canvas:handleStylusSlot({ id = 0, x = 1, y = TITLE_H, tool = ERASER }))
        assert.is_true(canvas:handleStylusSlot({ id = -1, tool = ERASER }))
    end)

    it("passes a contact that starts on the title bar to gesture detection, lift included", function()
        local canvas = newCanvas()
        assert.is_false(canvas:handleStylusSlot({ id = 0, x = 100, y = TITLE_H - 1, tool = PEN }))
        assert.is_false(canvas.pen_down)
        assert.is_false(canvas:handleStylusSlot({ id = 0, x = 100, y = TITLE_H + 50, tool = PEN }))
        assert.is_false(canvas.pen_down)
        assert.is_false(canvas:handleStylusSlot({ id = -1, tool = PEN }))
        assert.equals(0, #strokes(canvas))
        assert.is_false(canvas.changed)
        -- the next contact draws again
        down(canvas, 100, 500)
        assert.is_true(canvas.pen_down)
        up(canvas)
        assert.equals(1, #strokes(canvas))
    end)

    it("ends the stroke when the pen leaves the drawing area", function()
        local canvas = newCanvas()
        down(canvas, 100, 500)
        down(canvas, 100, 400)
        down(canvas, 100, 10)
        assert.is_false(canvas.pen_down)
        assert.equals(1, #strokes(canvas))
        assert.equals(2, #strokes(canvas)[1].points)
    end)

    it("draws a highlighter stroke while the side button is held", function()
        local canvas = newCanvas()
        down(canvas, 100, 500, HIGHLIGHTER)
        down(canvas, 200, 500, HIGHLIGHTER)
        up(canvas)
        assert.equals("highlighter", strokes(canvas)[1].tool)
        assert.equals(20, strokes(canvas)[1].width)
        assert.equals(1, canvas.pencil.highlighter_segments)
        assert.equals(0, canvas.pencil.segments)
    end)

    it("erases with the eraser end and restores on undo", function()
        local canvas = newCanvas()
        down(canvas, 100, 500)
        up(canvas)
        down(canvas, 600, 900)
        up(canvas)
        canvas.changed = false
        down(canvas, 105, 505, ERASER)
        assert.equals(1, #strokes(canvas))
        assert.equals(600, strokes(canvas)[1].points[1].x)
        assert.is_true(canvas.changed)
        assert.equals(1, ui.dirty)
        canvas:undo()
        assert.equals(2, #strokes(canvas))
        assert.equals(100, strokes(canvas)[1].points[1].x)
    end)

    it("honours the swapped eraser/highlighter setting", function()
        local canvas = newCanvas()
        canvas.pencil.swap_eraser_and_highlighter = true
        down(canvas, 100, 500, ERASER)
        down(canvas, 200, 500, ERASER)
        up(canvas)
        assert.equals("highlighter", strokes(canvas)[1].tool)
        down(canvas, 100, 500, HIGHLIGHTER)
        assert.equals(0, #strokes(canvas))
    end)

    it("undoes strokes in order and clears the canvas reversibly", function()
        local canvas = newCanvas()
        down(canvas, 100, 500) up(canvas)
        down(canvas, 300, 500) up(canvas)
        canvas:undo()
        assert.equals(1, #strokes(canvas))
        assert.equals(100, strokes(canvas)[1].points[1].x)
        down(canvas, 300, 500) up(canvas)
        local page_strokes = strokes(canvas)
        canvas:clear()
        assert.equals(page_strokes, strokes(canvas))
        assert.equals(0, #strokes(canvas))
        canvas:undo()
        assert.equals(2, #strokes(canvas))
        canvas:undo()
        canvas:undo()
        canvas:undo()  -- empty stack is harmless
        assert.equals(0, #strokes(canvas))
    end)

    it("refreshes the touched area at most every 16 ms and on lift", function()
        local canvas = newCanvas()
        down(canvas, 100, 500)
        down(canvas, 110, 510)
        assert.equals(0, #screen.refreshed)
        clock.now = 16
        down(canvas, 120, 520)
        assert.equals(1, #screen.refreshed)
        local r = screen.refreshed[1]
        assert.is_true(r.x <= 100 - 1 and r.y <= 500 - 1)
        assert.is_true(r.x + r.w >= 120 + 1 and r.y + r.h >= 520 + 1)
        down(canvas, 130, 530)
        up(canvas)
        assert.equals(2, #screen.refreshed)
        up(canvas)  -- nothing pending
        assert.equals(2, #screen.refreshed)
    end)

    it("finishes the stroke in progress and reports changes on close", function()
        local canvas, closed = newCanvas()
        down(canvas, 100, 500)
        canvas:onClose()
        assert.equals(1, #strokes(canvas))
        assert.same({ true }, closed)
        assert.equals(canvas, ui.closed[1])

        local untouched, untouched_closed = newCanvas()
        untouched:onClose()
        assert.same({ false }, untouched_closed)
    end)

    it("offers delete only when a handler is given", function()
        local canvas = newCanvas()
        canvas:showMenu()
        assert.equals(4, #ui.shown[1].buttons)
        canvas.on_delete = function() end
        canvas:showMenu()
        assert.equals(5, #ui.shown[2].buttons)
    end)

    describe("pages", function()
        it("starts on page 1 with the count in the title", function()
            local canvas = newCanvas()
            assert.equals(1, canvas.page_index)
            assert.equals("Book note · Page 1 of 1", canvas.title_bar.title)
        end)

        it("adds a page on a swipe west past the last page and navigates back and forth", function()
            local canvas = newCanvas()
            down(canvas, 100, 500) up(canvas)
            assert.is_true(swipe(canvas, "west"))
            assert.equals(2, canvas.page_index)
            assert.equals(2, #canvas.note.pages)
            assert.equals(0, #strokes(canvas))
            assert.equals("Book note · Page 2 of 2", canvas.title_bar.title)
            down(canvas, 200, 600) up(canvas)
            assert.is_true(swipe(canvas, "east"))
            assert.equals(1, canvas.page_index)
            assert.equals(100, strokes(canvas)[1].points[1].x)
            assert.equals("Book note · Page 1 of 2", canvas.title_bar.title)
            assert.is_true(swipe(canvas, "west"))
            assert.equals(2, canvas.page_index)
            assert.equals(2, #canvas.note.pages)
            assert.equals(200, strokes(canvas)[1].points[1].x)
        end)

        it("stays on the first page on a swipe east and ignores other directions", function()
            local canvas = newCanvas()
            assert.is_true(swipe(canvas, "east"))
            assert.equals(1, canvas.page_index)
            assert.is_false(swipe(canvas, "north"))
            assert.equals(1, #canvas.note.pages)
        end)

        it("turns pages with the page buttons", function()
            local canvas = newCanvas()
            assert.is_true(canvas:onNextPage())
            assert.equals(2, canvas.page_index)
            assert.is_true(canvas:onPrevPage())
            assert.equals(1, canvas.page_index)
        end)

        it("finishes the stroke in progress when the page turns", function()
            local canvas = newCanvas()
            down(canvas, 100, 500)
            down(canvas, 110, 510)
            swipe(canvas, "west")
            assert.is_false(canvas.pen_down)
            assert.equals(1, #canvas.note.pages[1].strokes)
            assert.equals(0, #strokes(canvas))
        end)

        it("keeps undo and clear per page", function()
            local canvas = newCanvas()
            down(canvas, 100, 500) up(canvas)
            swipe(canvas, "west")
            down(canvas, 200, 600) up(canvas)
            down(canvas, 300, 600) up(canvas)
            canvas:undo()
            assert.equals(1, #strokes(canvas))
            assert.equals(1, #canvas.note.pages[1].strokes)
            canvas:clear()
            assert.equals(0, #strokes(canvas))
            assert.equals(1, #canvas.note.pages[1].strokes)
            swipe(canvas, "east")
            canvas:undo()
            assert.equals(0, #strokes(canvas))
            canvas:undo()  -- nothing left on page 1
            assert.equals(0, #strokes(canvas))
            swipe(canvas, "west")
            canvas:undo()
            assert.equals(1, #strokes(canvas))
        end)

        it("drops blank pages on close but keeps one", function()
            local canvas, closed = newCanvas()
            down(canvas, 100, 500) up(canvas)
            swipe(canvas, "west")
            swipe(canvas, "west")
            assert.equals(3, #canvas.note.pages)
            canvas:onClose()
            assert.equals(1, #canvas.note.pages)
            assert.same({ true }, closed)

            local blank = newCanvas()
            swipe(blank, "west")
            blank:onClose()
            assert.equals(1, #blank.note.pages)
        end)

        it("deletes the current page and lands on the following one", function()
            local canvas = newCanvas()
            down(canvas, 100, 500) up(canvas)
            swipe(canvas, "west")
            down(canvas, 200, 500) up(canvas)
            swipe(canvas, "west")
            down(canvas, 300, 500) up(canvas)
            swipe(canvas, "east")
            canvas.changed = false
            canvas:deletePage()
            assert.equals(2, #canvas.note.pages)
            assert.equals(2, canvas.page_index)
            assert.equals(300, strokes(canvas)[1].points[1].x)
            assert.equals("Book note · Page 2 of 2", canvas.title_bar.title)
            assert.is_true(canvas.changed)
            canvas:deletePage()
            assert.equals(1, canvas.page_index)
            assert.equals(100, strokes(canvas)[1].points[1].x)
            canvas:deletePage()
            assert.equals(1, #canvas.note.pages)
            assert.equals(0, #strokes(canvas))
            canvas:undo()  -- the deleted page's history is gone
            assert.equals(0, #strokes(canvas))
        end)

        it("asks before deleting a page with strokes, not a blank one", function()
            local canvas = newCanvas()
            canvas:showMenu()
            assert.is_false(ui.shown[1].buttons[3][1].enabled)
            swipe(canvas, "west")
            canvas:confirmDeletePage()
            assert.equals(1, #canvas.note.pages)
            assert.is_nil(ui.shown[2])
            down(canvas, 100, 500) up(canvas)
            canvas:confirmDeletePage()
            assert.is_true(ui.shown[2].is_confirm)
            assert.equals(1, #strokes(canvas))
            ui.shown[2].ok_callback()
            assert.equals(0, #strokes(canvas))
        end)
    end)

    describe("finger mode", function()
        it("toggles the mode on hold + tap and discards the dot", function()
            local canvas = newCanvas()
            down(canvas, 100, 500, HIGHLIGHTER)
            down(canvas, 104, 503, HIGHLIGHTER)
            clock.now = TAP_MAX_MS
            up(canvas)
            assert.equals(1, canvas.pencil.mode_toggles)
            assert.is_true(canvas.pencil.finger_mode)
            assert.equals(0, #strokes(canvas))
            assert.is_false(canvas.changed)
            assert.equals(1, ui.dirty)
        end)

        it("keeps a long or moving side-button contact as a highlight", function()
            local canvas = newCanvas()
            down(canvas, 100, 500, HIGHLIGHTER)
            clock.now = TAP_MAX_MS + 1
            up(canvas)
            assert.equals(0, canvas.pencil.mode_toggles)
            assert.equals(1, #strokes(canvas))
            clock.now = 0
            down(canvas, 100, 500, HIGHLIGHTER)
            down(canvas, 100 + TAP_MAX_PX + 1, 500, HIGHLIGHTER)
            up(canvas)
            assert.equals(0, canvas.pencil.mode_toggles)
            assert.equals(2, #strokes(canvas))
        end)

        it("does not treat a bare pen tap as a mode toggle", function()
            local canvas = newCanvas()
            down(canvas, 100, 500) up(canvas)
            assert.equals(0, canvas.pencil.mode_toggles)
            assert.equals(1, #strokes(canvas))
        end)

        it("passes the bare tip through in finger mode, but still highlights and erases", function()
            local canvas = newCanvas()
            canvas.pencil.finger_mode = true
            assert.is_false(canvas:handleStylusSlot({ id = 0, x = 100, y = 500, tool = PEN }))
            assert.is_false(canvas:handleStylusSlot({ id = 0, x = 300, y = 500, tool = PEN }))
            assert.is_false(canvas:handleStylusSlot({ id = -1, tool = PEN }))
            assert.equals(0, #strokes(canvas))
            assert.is_true(canvas:handleStylusSlot({ id = 0, x = 100, y = 500, tool = HIGHLIGHTER }))
            clock.now = TAP_MAX_MS + 1
            assert.is_true(canvas:handleStylusSlot({ id = -1, tool = HIGHLIGHTER }))
            assert.equals("highlighter", strokes(canvas)[1].tool)
            assert.is_true(canvas:handleStylusSlot({ id = 0, x = 100, y = 500, tool = ERASER }))
            assert.is_true(canvas:handleStylusSlot({ id = -1, tool = ERASER }))
            assert.equals(0, #strokes(canvas))
        end)

        it("offers the mode toggle in the menu", function()
            local canvas = newCanvas()
            canvas:showMenu()
            assert.equals("Switch to finger mode", ui.shown[1].buttons[4][1].text)
            ui.shown[1].buttons[4][1].callback()
            assert.is_true(canvas.pencil.finger_mode)
            canvas:showMenu()
            assert.equals("Switch to pen mode", ui.shown[2].buttons[4][1].text)
        end)
    end)

    describe("header", function()
        local HEADER_H = HEADER_LINE_H + 2 * HEADER_PAD + HEADER_LINE

        it("is absent unless given, and must be a non-empty string", function()
            local canvas = newCanvas()
            assert.is_nil(canvas.header_widget)
            assert.equals(TITLE_H, canvas:canvasTop())
            assert.has_error(function() newCanvas(nil, "") end)
            assert.has_error(function() newCanvas(nil, 42) end)
        end)

        it("pushes the drawing area down on the first page only", function()
            local canvas = newCanvas(nil, "the highlighted text")
            assert.equals(TITLE_H + HEADER_H, canvas:canvasTop())
            swipe(canvas, "west")
            assert.equals(TITLE_H, canvas:canvasTop())
            swipe(canvas, "east")
            assert.equals(TITLE_H + HEADER_H, canvas:canvasTop())
        end)

        it("grows with the text up to a third of the screen", function()
            local canvas = newCanvas(nil, "one\ntwo\nthree")
            assert.equals(TITLE_H + 3 * HEADER_LINE_H + 2 * HEADER_PAD + HEADER_LINE, canvas:canvasTop())
            local long = string.rep("line\n", 200)
            canvas = newCanvas(nil, long)
            assert.equals(math.floor(SCREEN_H / 3), canvas.header_widget.height)
            assert.equals(TITLE_H + math.floor(SCREEN_H / 3) + 2 * HEADER_PAD + HEADER_LINE, canvas:canvasTop())
        end)

        it("hands a contact that starts on the header to gesture detection", function()
            local canvas = newCanvas(nil, "the highlighted text")
            local top = canvas:canvasTop()
            assert.is_false(canvas:handleStylusSlot({ id = 0, x = 100, y = top - 1, tool = PEN }))
            assert.is_false(canvas.pen_down)
            assert.is_false(canvas:handleStylusSlot({ id = -1, tool = PEN }))
            assert.equals(0, #strokes(canvas))
            down(canvas, 100, top)
            assert.is_true(canvas.pen_down)
            up(canvas)
            assert.equals(1, #strokes(canvas))
        end)

        it("is painted on the first page and freed with the canvas", function()
            local canvas = newCanvas(nil, "the highlighted text")
            canvas:paintTo(screen.bb, 0, 0)
            assert.equals(1, canvas.header_widget.painted)
            swipe(canvas, "west")
            canvas:paintTo(screen.bb, 0, 0)
            assert.equals(1, canvas.header_widget.painted)
            canvas:onCloseWidget()
            assert.is_true(canvas.header_widget.freed)
        end)
    end)

    describe("finger mode marker", function()
        it("is painted by the plugin on every repaint", function()
            local canvas = newCanvas()
            canvas:paintTo(screen.bb, 0, 0)
            assert.equals(1, canvas.pencil.marker_paints)
            canvas:paintTo(screen.bb, 0, 0)
            assert.equals(2, canvas.pencil.marker_paints)
        end)
    end)
end)
