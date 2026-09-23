--[[--
Full-screen canvas for a pen note, one note page at a time.

The Pencil plugin routes raw stylus slots here while the canvas is the
topmost widget (see Pencil:handleStylusSlot), so the pen tip draws, the
side button highlights and the eraser end erases exactly as on a page.
Holding the side button and tapping toggles finger/pen mode; in finger
mode the bare tip is left to gesture detection, like a finger.

Fingers (and the tip in finger mode) swipe between pages like in the
reader: a swipe to the left turns forward and adds a blank page past the
last one, a swipe to the right goes back. The hardware page buttons do
the same. The title bar shows the page count, the X closes the canvas and
the menu icon offers undo, clear page, delete page, the mode toggle and
delete note.

@module pencil.lib.notecanvas
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notes = require("lib/notes")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template
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
    pencil = nil,        -- Pencil plugin: tool settings, input mode, stroke rendering, coordinate transform
    note = nil,          -- Notes record; its pages are edited in place
    title = "",
    tap_max_ms = nil,    -- side-button contact shorter than this and ...
    tap_max_px = nil,    -- ... moving less than this is a tap, not a highlight
    on_close = nil,      -- function(canvas, changed)
    on_delete = nil,     -- function(canvas); the canvas closes itself afterwards
    covers_fullscreen = true,
}

function NoteCanvas:init()
    assert(self.pencil, "NoteCanvas needs the Pencil plugin")
    assert(self.note and self.note.pages and #self.note.pages >= 1, "NoteCanvas needs a note with pages")
    assert(type(self.tap_max_ms) == "number" and self.tap_max_ms > 0, "NoteCanvas needs tap_max_ms")
    assert(type(self.tap_max_px) == "number" and self.tap_max_px >= 0, "NoteCanvas needs tap_max_px")
    assert(type(self.on_close) == "function", "NoteCanvas needs an on_close callback")

    self.page_index = 1
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        fullscreen = true,
        align = "left",
        title = self:titleText(),
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self[1] = self.title_bar
    self.canvas_top = self.title_bar:getHeight()

    self.undo_stacks = {}  -- page table -> list of undo entries
    self.changed = false
    self.current_stroke = nil
    self.pen_down = false
    self.title_bar_contact = false
    self.contact = nil     -- { x, y, time, moved, highlighter } for the tip contact in progress
    self.dirty_region = nil
    self.last_refresh_time = 0

    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            NextPage = { { Device.input.group.PgFwd } },
            PrevPage = { { Device.input.group.PgBack } },
        }
    end
end

function NoteCanvas:currentPage()
    return self.note.pages[self.page_index]
end

function NoteCanvas:strokes()
    return self:currentPage().strokes
end

function NoteCanvas:undoStack()
    local page = self:currentPage()
    local stack = self.undo_stacks[page]
    if not stack then
        stack = {}
        self.undo_stacks[page] = stack
    end
    return stack
end

-- Single line so the bar stays as short as possible: "Book note · Page 2 of 3"
function NoteCanvas:titleText()
    return T(_("%1 · Page %2 of %3"), self.title, self.page_index, #self.note.pages)
end

function NoteCanvas:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    self.title_bar:paintTo(bb, x, y)
    for _, stroke in ipairs(self:strokes()) do
        self.pencil:renderStroke(bb, stroke)
    end
    if self.current_stroke then
        self.pencil:renderStroke(bb, self.current_stroke)
    end
end

-- Stylus entry point. slot = {id, x, y, tool}; id < 0 means the tip lifted.
-- Returns true to keep the pen out of gesture detection. A contact that
-- starts on the title bar is handed to gesture detection instead, lift
-- included, so the pen can tap the X and the menu icon. In finger mode
-- the bare tip is handed over as well, so it swipes and taps like a finger.
function NoteCanvas:handleStylusSlot(slot)
    if not (slot.id and slot.id >= 0) then
        if self.title_bar_contact then
            self.title_bar_contact = false
            return false
        end
        self:penUp()
        return true
    end
    if self.title_bar_contact then
        return false
    end
    local swap = self.pencil.swap_eraser_and_highlighter
    local eraser_type = swap and TOOL_TYPE_HIGHLIGHTER or TOOL_TYPE_ERASER
    local highlighter_type = swap and TOOL_TYPE_ERASER or TOOL_TYPE_HIGHLIGHTER
    local is_eraser = slot.tool == eraser_type
    local is_highlighter = slot.tool == highlighter_type
    local x, y = self.pencil:transformCoordinates(slot.x or 0, slot.y or 0)
    if not self.pen_down then
        if y < self.canvas_top or (self.pencil:isFingerMode() and not (is_eraser or is_highlighter)) then
            self.title_bar_contact = true
            return false
        end
    end
    if is_eraser then
        self:penUp()
        self:eraseAt(x, y)
    elseif not self.pen_down then
        self:penDown(x, y, is_highlighter)
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
    self.contact = { x = x, y = y, time = time.now(), moved = false, highlighter = highlighter }
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
    local c = self.contact
    if c and not c.moved and (math.abs(x - c.x) > self.tap_max_px or math.abs(y - c.y) > self.tap_max_px) then
        c.moved = true
    end
    local points = self.current_stroke.points
    local last = points[#points]
    if last.x ~= x or last.y ~= y then
        self:addPoint(x, y)
    end
end

-- Whether the contact that just ended was a hold + tap: side button held,
-- lifted within tap_max_ms having moved at most tap_max_px.
function NoteCanvas:takeSideButtonTap()
    local c = self.contact
    self.contact = nil
    if not (c and c.highlighter) or c.moved then return false end
    return time.to_ms(time.now() - c.time) <= self.tap_max_ms
end

function NoteCanvas:penUp()
    if not self.pen_down then return end
    self.pen_down = false
    local stroke = self.current_stroke
    self.current_stroke = nil
    if self:takeSideButtonTap() then
        self.dirty_region = nil
        self:repaint()
        self.pencil:toggleInputMode()
        return
    end
    if stroke and #stroke.points >= 1 then
        table.insert(self:strokes(), stroke)
        table.insert(self:undoStack(), { type = "add" })
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
    local removed = Notes.eraseAt(self:strokes(), x, y, ERASE_THRESHOLD_PX)
    if not removed then return end
    table.insert(self:undoStack(), { type = "delete", removed = removed })
    self.changed = true
    self:repaint()
end

function NoteCanvas:undo()
    local entry = table.remove(self:undoStack())
    if not entry then return end
    if entry.type == "add" then
        table.remove(self:strokes())
    else
        Notes.restore(self:strokes(), entry.removed)
    end
    self.changed = true
    self:repaint()
end

function NoteCanvas:clear()
    local strokes = self:strokes()
    if #strokes == 0 then return end
    local removed = {}
    for i, stroke in ipairs(strokes) do
        removed[i] = { index = i, stroke = stroke }
    end
    for i = #strokes, 1, -1 do
        strokes[i] = nil
    end
    table.insert(self:undoStack(), { type = "delete", removed = removed })
    self.changed = true
    self:repaint()
end

function NoteCanvas:goToPage(index)
    assert(index >= 1 and index <= #self.note.pages, "page index out of range: " .. tostring(index))
    self:penUp()
    self.page_index = index
    self.title_bar:setTitle(self:titleText(), true)
    self:repaint()
end

-- Forward past the last page adds a blank one; blank pages are dropped
-- again when the canvas closes.
function NoteCanvas:nextPage()
    if self.page_index == #self.note.pages then
        Notes.addPage(self.note)
    end
    self:goToPage(self.page_index + 1)
    return true
end

function NoteCanvas:prevPage()
    if self.page_index > 1 then
        self:goToPage(self.page_index - 1)
    end
    return true
end

-- Removes the current page; a blank one is left when it was the last.
function NoteCanvas:deletePage()
    self:penUp()
    local page = self:currentPage()
    if #self.note.pages == 1 and Notes.isPageEmpty(page) then return end
    Notes.removePage(self.note, self.page_index)
    self.undo_stacks[page] = nil
    self.changed = true
    self:goToPage(math.min(self.page_index, #self.note.pages))
end

function NoteCanvas:confirmDeletePage()
    if Notes.isPageEmpty(self:currentPage()) then
        self:deletePage()
        return
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete page %1 of %2 of this note?"), self.page_index, #self.note.pages),
        ok_text = _("Delete"),
        ok_callback = function() self:deletePage() end,
    })
end

function NoteCanvas:onSwipe(_, ges)
    if ges.direction == "west" then
        return self:nextPage()
    elseif ges.direction == "east" then
        return self:prevPage()
    end
    return false
end

function NoteCanvas:onNextPage()
    return self:nextPage()
end

function NoteCanvas:onPrevPage()
    return self:prevPage()
end

function NoteCanvas:repaint()
    UIManager:setDirty(self, "ui")
end

function NoteCanvas:showMenu()
    local dialog
    local buttons = {
        {{
            text = _("Undo last stroke"),
            enabled = #self:undoStack() > 0,
            callback = function()
                UIManager:close(dialog)
                self:undo()
            end,
        }},
        {{
            text = _("Clear page"),
            enabled = #self:strokes() > 0,
            callback = function()
                UIManager:close(dialog)
                self:clear()
            end,
        }},
        {{
            text = _("Delete page"),
            enabled = #self.note.pages > 1 or #self:strokes() > 0,
            callback = function()
                UIManager:close(dialog)
                self:confirmDeletePage()
            end,
        }},
        {{
            text = self.pencil:isFingerMode() and _("Switch to pen mode") or _("Switch to finger mode"),
            callback = function()
                UIManager:close(dialog)
                self.pencil:toggleInputMode()
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
    Notes.prunePages(self.note)
    logger.dbg("NoteCanvas: closed, changed =", self.changed, "pages =", #self.note.pages)
    self.on_close(self, self.changed)
    return true
end

function NoteCanvas:onCloseWidget()
    self.title_bar:free()
end

return NoteCanvas
