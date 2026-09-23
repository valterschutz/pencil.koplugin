--[[--
Unit tests for the note canvas widget (lib/notecanvas.lua).
KOReader's widget modules are stubbed just enough to construct the widget
and feed it stylus slots.
Run with: busted spec/notecanvas_spec.lua
--]]--

package.path = package.path .. ";pencil.koplugin/?.lua"

local SCREEN_W, SCREEN_H = 1264, 1680
local TITLE_H = 60

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
preload("device", {
    screen = screen,
    hasKeys = function() return false end,
    input = { group = { Back = "Back" } },
})
preload("ui/geometry", { new = function(_, o) return o end })
preload("ui/widget/container/inputcontainer", stubClass())
preload("ui/widget/titlebar", {
    new = function(_, o)
        o.getHeight = function() return TITLE_H end
        o.paintTo = function() end
        o.free = function() end
        return o
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

local function newPencil()
    return {
        swap_eraser_and_highlighter = false,
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
    }
end

local function newCanvas(note)
    local closed = {}
    local canvas = NoteCanvas:new{
        pencil = newPencil(),
        note = note or { anchor = { kind = "book" }, datetime = 1, strokes = {} },
        title = "Book note",
        on_close = function(_, changed) table.insert(closed, changed) end,
    }
    return canvas, closed
end

local PEN, ERASER, HIGHLIGHTER = 1, 2, 3
local function down(canvas, x, y, tool) canvas:handleStylusSlot({ id = 0, x = x, y = y, tool = tool or PEN }) end
local function up(canvas) canvas:handleStylusSlot({ id = -1, tool = PEN }) end

describe("NoteCanvas", function()
    before_each(function()
        clock.now = 0
        screen.refreshed = {}
        ui.shown, ui.closed, ui.dirty = {}, {}, 0
    end)

    it("requires the plugin, a note and a close callback", function()
        assert.has_error(function() NoteCanvas:new{ note = { strokes = {} }, on_close = function() end } end)
        assert.has_error(function() NoteCanvas:new{ pencil = newPencil(), on_close = function() end } end)
        assert.has_error(function() NoteCanvas:new{ pencil = newPencil(), note = { strokes = {} } } end)
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
        assert.equals(1, #canvas.note.strokes)
        assert.equals(3, #canvas.note.strokes[1].points)
        assert.equals("pen", canvas.note.strokes[1].tool)
        assert.equals(3, canvas.note.strokes[1].width)
        assert.equals(2, canvas.pencil.segments)
        assert.is_true(canvas.changed)
        assert.equals(1, #canvas.undo_stack)
    end)

    it("always dominates the stylus", function()
        local canvas = newCanvas()
        assert.is_true(canvas:handleStylusSlot({ id = 0, x = 1, y = 1, tool = PEN }))
        assert.is_true(canvas:handleStylusSlot({ id = -1, tool = PEN }))
        assert.is_true(canvas:handleStylusSlot({ id = 0, x = 1, y = 1, tool = ERASER }))
    end)

    it("ignores pen contact on the title bar", function()
        local canvas = newCanvas()
        down(canvas, 100, TITLE_H - 1)
        assert.is_false(canvas.pen_down)
        up(canvas)
        assert.equals(0, #canvas.note.strokes)
        assert.is_false(canvas.changed)
    end)

    it("ends the stroke when the pen leaves the drawing area", function()
        local canvas = newCanvas()
        down(canvas, 100, 500)
        down(canvas, 100, 400)
        down(canvas, 100, 10)
        assert.is_false(canvas.pen_down)
        assert.equals(1, #canvas.note.strokes)
        assert.equals(2, #canvas.note.strokes[1].points)
    end)

    it("draws a highlighter stroke while the side button is held", function()
        local canvas = newCanvas()
        down(canvas, 100, 500, HIGHLIGHTER)
        down(canvas, 200, 500, HIGHLIGHTER)
        up(canvas)
        assert.equals("highlighter", canvas.note.strokes[1].tool)
        assert.equals(20, canvas.note.strokes[1].width)
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
        assert.equals(1, #canvas.note.strokes)
        assert.equals(600, canvas.note.strokes[1].points[1].x)
        assert.is_true(canvas.changed)
        assert.equals(1, ui.dirty)
        canvas:undo()
        assert.equals(2, #canvas.note.strokes)
        assert.equals(100, canvas.note.strokes[1].points[1].x)
    end)

    it("honours the swapped eraser/highlighter setting", function()
        local canvas = newCanvas()
        canvas.pencil.swap_eraser_and_highlighter = true
        down(canvas, 100, 500, ERASER)
        down(canvas, 200, 500, ERASER)
        up(canvas)
        assert.equals("highlighter", canvas.note.strokes[1].tool)
        down(canvas, 100, 500, HIGHLIGHTER)
        assert.equals(0, #canvas.note.strokes)
    end)

    it("undoes strokes in order and clears the canvas reversibly", function()
        local canvas = newCanvas()
        down(canvas, 100, 500) up(canvas)
        down(canvas, 300, 500) up(canvas)
        canvas:undo()
        assert.equals(1, #canvas.note.strokes)
        assert.equals(100, canvas.note.strokes[1].points[1].x)
        down(canvas, 300, 500) up(canvas)
        local strokes = canvas.note.strokes
        canvas:clear()
        assert.equals(strokes, canvas.note.strokes)
        assert.equals(0, #canvas.note.strokes)
        canvas:undo()
        assert.equals(2, #canvas.note.strokes)
        canvas:undo()
        canvas:undo()
        canvas:undo()  -- empty stack is harmless
        assert.equals(0, #canvas.note.strokes)
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
        assert.equals(1, #canvas.note.strokes)
        assert.same({ true }, closed)
        assert.equals(canvas, ui.closed[1])

        local untouched, untouched_closed = newCanvas()
        untouched:onClose()
        assert.same({ false }, untouched_closed)
    end)

    it("offers delete only when a handler is given", function()
        local canvas = newCanvas()
        canvas:showMenu()
        assert.equals(2, #ui.shown[1].buttons)
        canvas.on_delete = function() end
        canvas:showMenu()
        assert.equals(3, #ui.shown[2].buttons)
    end)
end)
