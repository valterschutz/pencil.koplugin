--[[--
Full-screen blank canvas for a pen note.

The Pencil plugin routes raw stylus slots here while the canvas is the
topmost widget (see Pencil:handleStylusSlot), so the pen tip draws, the
side button highlights and the eraser end erases exactly as on a page.
Finger input only reaches the title bar: the X closes the canvas and the
menu icon offers undo, clear and delete.

@module pencil.lib.notecanvas
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notes = require("lib/notes")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local Screen = Device.screen

-- Linux input tool types, as promoted by the patched input.lua
local TOOL_TYPE_ERASER = 2
local TOOL_TYPE_HIGHLIGHTER = 3

-- stroke.tool values understood by Pencil:renderStroke
local TOOL_PEN = "pen"
local TOOL_HIGHLIGHTER = "highlighter"

local REFRESH_INTERVAL_MS = 16
local ERASE_THRESHOLD_PX = 20

local NoteCanvas = InputContainer:extend{
    pencil = nil,        -- Pencil plugin: tool settings, stroke rendering, coordinate transform
    note = nil,          -- Notes record; its strokes array is edited in place
    title = "",
    on_close = nil,      -- function(canvas, changed)
    on_delete = nil,     -- function(canvas); the canvas closes itself afterwards
    covers_fullscreen = true,
}

function NoteCanvas:init()
    assert(self.pencil, "NoteCanvas needs the Pencil plugin")
    assert(self.note and self.note.strokes, "NoteCanvas needs a note")
    assert(type(self.on_close) == "function", "NoteCanvas needs an on_close callback")

    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        fullscreen = true,
        align = "left",
        title = self.title,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self[1] = self.title_bar
    self.canvas_top = self.title_bar:getHeight()

    self.undo_stack = {}
    self.changed = false
    self.current_stroke = nil
    self.pen_down = false
    self.dirty_region = nil
    self.last_refresh_time = 0

    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
end

function NoteCanvas:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    self.title_bar:paintTo(bb, x, y)
    for _, stroke in ipairs(self.note.strokes) do
        self.pencil:renderStroke(bb, stroke)
    end
    if self.current_stroke then
        self.pencil:renderStroke(bb, self.current_stroke)
    end
end

-- Stylus entry point. slot = {id, x, y, tool}; id < 0 means the tip lifted.
-- Always returns true so the pen never reaches gesture detection.
function NoteCanvas:handleStylusSlot(slot)
    if not (slot.id and slot.id >= 0) then
        self:penUp()
        return true
    end
    local x, y = self.pencil:transformCoordinates(slot.x or 0, slot.y or 0)
    local swap = self.pencil.swap_eraser_and_highlighter
    local eraser_type = swap and TOOL_TYPE_HIGHLIGHTER or TOOL_TYPE_ERASER
    local highlighter_type = swap and TOOL_TYPE_ERASER or TOOL_TYPE_HIGHLIGHTER
    if slot.tool == eraser_type then
        self:penUp()
        self:eraseAt(x, y)
    elseif not self.pen_down then
        self:penDown(x, y, slot.tool == highlighter_type)
    else
        self:penMove(x, y)
    end
    return true
end

function NoteCanvas:isInDrawingArea(x, y)
    return y >= self.canvas_top and y < self.dimen.h and x >= 0 and x < self.dimen.w
end

function NoteCanvas:penDown(x, y, highlighter)
    if not self:isInDrawingArea(x, y) then return end
    local tool = highlighter and TOOL_HIGHLIGHTER or TOOL_PEN
    local settings = self.pencil.tool_settings[tool]
    self.current_stroke = {
        tool = tool,
        points = {},
        width = settings.width,
        color = settings.color,
        color_name = settings.color_name,
        alpha = settings.alpha,
        datetime = os.time(),
    }
    self.pen_down = true
    self.last_refresh_time = time.now()
    self.dirty_region = nil
    self:addPoint(x, y)
end

function NoteCanvas:penMove(x, y)
    if not self.current_stroke then return end
    if not self:isInDrawingArea(x, y) then
        self:penUp()
        return
    end
    local points = self.current_stroke.points
    local last = points[#points]
    if last.x ~= x or last.y ~= y then
        self:addPoint(x, y)
    end
end

function NoteCanvas:penUp()
    if not self.pen_down then return end
    self.pen_down = false
    local stroke = self.current_stroke
    self.current_stroke = nil
    if stroke and #stroke.points >= 1 then
        table.insert(self.note.strokes, stroke)
        table.insert(self.undo_stack, { type = "add" })
        self.changed = true
    end
    self:flushDirtyRegion()
end

-- Paint the newest segment straight into the framebuffer and refresh the
-- touched area at most every REFRESH_INTERVAL_MS, as the page drawing does.
function NoteCanvas:addPoint(x, y)
    local stroke = self.current_stroke
    table.insert(stroke.points, { x = x, y = y })
    local n = #stroke.points
    local width = stroke.width
    local color = stroke.color
    if Screen.night_mode and stroke.color_name ~= "Black" and stroke.color_name ~= "Gray" then
        color = color:invert()
    end

    local pad = math.floor(width / 2) + 2
    local x0, y0, x1, y1
    if n == 1 then
        local half = math.floor(width / 2)
        Screen.bb:paintRectRGB32(x - half, y - half, width, width, color)
        x0, y0, x1, y1 = x, y, x, y
    else
        local p1 = stroke.points[n - 1]
        if stroke.tool == TOOL_HIGHLIGHTER then
            self.pencil:drawHighlighterSegment(Screen.bb, p1.x, p1.y, x, y, width, color)
        else
            self.pencil:drawLineSegment(Screen.bb, p1.x, p1.y, x, y, width, color)
        end
        x0, y0 = math.min(p1.x, x), math.min(p1.y, y)
        x1, y1 = math.max(p1.x, x), math.max(p1.y, y)
    end
    self:growDirtyRegion(x0 - pad, y0 - pad, x1 + pad, y1 + pad)

    local now = time.now()
    if time.to_ms(now - self.last_refresh_time) >= REFRESH_INTERVAL_MS then
        self.last_refresh_time = now
        self:flushDirtyRegion()
    end
end

function NoteCanvas:growDirtyRegion(x0, y0, x1, y1)
    local r = self.dirty_region
    if r then
        r.x0, r.y0 = math.min(r.x0, x0), math.min(r.y0, y0)
        r.x1, r.y1 = math.max(r.x1, x1), math.max(r.y1, y1)
    else
        self.dirty_region = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
    end
end

function NoteCanvas:flushDirtyRegion()
    local r = self.dirty_region
    if not r then return end
    self.dirty_region = nil
    local rx = math.max(0, math.floor(r.x0))
    local ry = math.max(0, math.floor(r.y0))
    local rw = math.min(self.dimen.w - rx, math.ceil(r.x1) - rx)
    local rh = math.min(self.dimen.h - ry, math.ceil(r.y1) - ry)
    if rw > 0 and rh > 0 then
        Screen:refreshUI(rx, ry, rw, rh)
    end
end

function NoteCanvas:eraseAt(x, y)
    if not self:isInDrawingArea(x, y) then return end
    local removed = Notes.eraseAt(self.note.strokes, x, y, ERASE_THRESHOLD_PX)
    if not removed then return end
    table.insert(self.undo_stack, { type = "delete", removed = removed })
    self.changed = true
    self:repaint()
end

function NoteCanvas:undo()
    local entry = table.remove(self.undo_stack)
    if not entry then return end
    if entry.type == "add" then
        table.remove(self.note.strokes)
    else
        Notes.restore(self.note.strokes, entry.removed)
    end
    self.changed = true
    self:repaint()
end

function NoteCanvas:clear()
    if Notes.isEmpty(self.note) then return end
    local strokes = self.note.strokes
    local removed = {}
    for i, stroke in ipairs(strokes) do
        removed[i] = { index = i, stroke = stroke }
    end
    for i = #strokes, 1, -1 do
        strokes[i] = nil
    end
    table.insert(self.undo_stack, { type = "delete", removed = removed })
    self.changed = true
    self:repaint()
end

function NoteCanvas:repaint()
    UIManager:setDirty(self, "ui")
end

function NoteCanvas:showMenu()
    local dialog
    local buttons = {
        {{
            text = _("Undo last stroke"),
            enabled = #self.undo_stack > 0,
            callback = function()
                UIManager:close(dialog)
                self:undo()
            end,
        }},
        {{
            text = _("Clear canvas"),
            enabled = not Notes.isEmpty(self.note),
            callback = function()
                UIManager:close(dialog)
                self:clear()
            end,
        }},
    }
    if self.on_delete then
        table.insert(buttons, {{
            text = _("Delete note"),
            callback = function()
                UIManager:close(dialog)
                self.on_delete(self)
            end,
        }})
    end
    dialog = ButtonDialog:new{
        title = self.title,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function NoteCanvas:onClose()
    self:penUp()
    UIManager:close(self, "flashui")
    logger.dbg("NoteCanvas: closed, changed =", self.changed, "strokes =", #self.note.strokes)
    self.on_close(self, self.changed)
    return true
end

function NoteCanvas:onCloseWidget()
    self.title_bar:free()
end

return NoteCanvas
