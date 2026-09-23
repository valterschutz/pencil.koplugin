--[[--
Unit tests for the stylus side button: quick press vs. hold, and what a
quick press toggles depending on the "Side button tap" setting.
Run with: busted spec/side_button_spec.lua
--]]--

local MODE_PEN = "pen"
local MODE_FINGER = "finger"
local SIDE_BUTTON_TAP_TOOL = "tool"
local SIDE_BUTTON_TAP_MODE = "mode"
local SIDE_BUTTON_TAP_MAX_MS = 500
local SIDE_BUTTON_TAP_MAX_PX = 10
local SIDE_BUTTON_DOUBLE_TAP_MS = 250

-- Mock Pencil mirroring onStylusButtonPress/Release, onSideButtonTap and
-- the input mode helpers, with a controllable clock.
local function createMockPencil(options)
    options = options or {}
    local mock = {
        now_ms = 0,
        current_tool = "pen",
        input_mode = options.input_mode or MODE_PEN,
        side_button_tap = options.side_button_tap or SIDE_BUTTON_TAP_TOOL,
        side_button_down = false,
        side_button_press_time = nil,
        side_button_used_for_highlight = false,
        highlighting = false,
        pen_down = false,
        _saved = 0,
    }

    function mock:saveSettings() self._saved = self._saved + 1 end
    function mock:isFingerMode() return self.input_mode == MODE_FINGER end
    mock.eraser_tool_active = false
    mock.eraser_button_active = false

    function mock:isFingerPassthrough(is_eraser_end, is_highlighter)
        if not self:isFingerMode() then return false end
        if is_eraser_end or is_highlighter then return false end
        if self.side_button_down or self.pen_down then return false end
        return not (self.eraser_tool_active or self.eraser_button_active)
    end

    function mock:setInputMode(mode)
        assert(mode == MODE_PEN or mode == MODE_FINGER, "unknown input mode: " .. tostring(mode))
        if mode == self.input_mode then return end
        self.input_mode = mode
        self:saveSettings()
    end

    function mock:toggleInputMode()
        self:setInputMode(self:isFingerMode() and MODE_PEN or MODE_FINGER)
    end

    function mock:togglePenEraser()
        self.current_tool = self.current_tool == "eraser" and "pen" or "eraser"
        self:saveSettings()
    end

    -- Fake scheduler: pending actions fire when the clock passes their time
    mock._scheduled = {}
    mock._note_menus = 0
    function mock:scheduleIn(ms, fn) table.insert(self._scheduled, { at = self.now_ms + ms, fn = fn }) end
    function mock:unschedule(fn)
        for i = #self._scheduled, 1, -1 do
            if self._scheduled[i].fn == fn then table.remove(self._scheduled, i) end
        end
    end
    function mock:advance(ms)
        self.now_ms = self.now_ms + ms
        local due = {}
        for i = #self._scheduled, 1, -1 do
            if self._scheduled[i].at <= self.now_ms then
                table.insert(due, 1, table.remove(self._scheduled, i).fn)
            end
        end
        for _, fn in ipairs(due) do fn() end
    end
    function mock:showNoteMenu() self._note_menus = self._note_menus + 1 end
    -- Let a pending single tap fire
    function mock:settle() self:advance(SIDE_BUTTON_DOUBLE_TAP_MS) end

    function mock:onSideButtonTap()
        if self.side_button_tap_pending then
            self:unschedule(self.side_button_tap_pending)
            self.side_button_tap_pending = nil
            self:showNoteMenu()
            return
        end
        self.side_button_tap_pending = function()
            self.side_button_tap_pending = nil
            self:onSideButtonSingleTap()
        end
        self:scheduleIn(SIDE_BUTTON_DOUBLE_TAP_MS, self.side_button_tap_pending)
    end

    function mock:onSideButtonSingleTap()
        if self.side_button_tap == SIDE_BUTTON_TAP_MODE then
            self:toggleInputMode()
        else
            self:togglePenEraser()
        end
    end

    function mock:onStylusButtonPress()
        self.side_button_down = true
        self.side_button_press_time = self.now_ms
        if not self.highlighting then
            self.side_button_used_for_highlight = false
        end
        return true
    end

    mock._overlay = false
    function mock:isOverlayActive() return self._overlay end

    function mock:onStylusButtonRelease()
        local was_down = self.side_button_down
        local used_for_highlight = self.side_button_used_for_highlight
        local held_ms = self.side_button_press_time and (self.now_ms - self.side_button_press_time) or 0
        self.side_button_down = false
        self.side_button_used_for_highlight = false
        self.side_button_press_time = nil
        if not was_down then return false end
        if self:isOverlayActive() then return false end
        if not used_for_highlight and held_ms <= SIDE_BUTTON_TAP_MAX_MS then
            self:onSideButtonTap()
        end
        return true
    end

    function mock:beginSideButtonContact(x, y)
        self.side_button_contact = { x = x, y = y, time = self.now_ms, moved = false }
    end

    function mock:trackSideButtonContact(x, y)
        local c = self.side_button_contact
        if not c or c.moved then return end
        if math.abs(x - c.x) > SIDE_BUTTON_TAP_MAX_PX or math.abs(y - c.y) > SIDE_BUTTON_TAP_MAX_PX then
            c.moved = true
        end
    end

    function mock:takeSideButtonTap()
        local c = self.side_button_contact
        self.side_button_contact = nil
        if not c or c.moved then return false end
        return (self.now_ms - c.time) <= SIDE_BUTTON_TAP_MAX_MS
    end

    -- Simulate the tip touching at (x, y) with the button held, moving by
    -- (dx, dy) over held_ms, then lifting. Returns whether it was a tap.
    function mock:contact(held_ms, dx, dy)
        self:onStylusButtonPress()
        self:beginSideButtonContact(100, 100)
        self.now_ms = self.now_ms + held_ms
        self:trackSideButtonContact(100 + (dx or 0), 100 + (dy or 0))
        local tapped = self:takeSideButtonTap()
        if tapped then self:onSideButtonTap() end
        return tapped
    end

    -- Simulate a press held for held_ms, optionally drawing while held
    function mock:press(held_ms, drew)
        self:onStylusButtonPress()
        self.now_ms = self.now_ms + held_ms
        if drew then self.side_button_used_for_highlight = true end
        self:onStylusButtonRelease()
    end

    return mock
end

describe("side button", function()

    describe("tap vs hold", function()

        it("quick press toggles", function()
            local p = createMockPencil()
            p:press(100)
            p:settle()
            assert.equals("eraser", p.current_tool)
        end)

        it("press at the threshold still counts as a tap", function()
            local p = createMockPencil()
            p:press(SIDE_BUTTON_TAP_MAX_MS)
            p:settle()
            assert.equals("eraser", p.current_tool)
        end)

        it("long hold does not toggle", function()
            local p = createMockPencil()
            p:press(SIDE_BUTTON_TAP_MAX_MS + 1)
            p:settle()
            assert.equals("pen", p.current_tool)
        end)

        it("press used for highlighting does not toggle", function()
            local p = createMockPencil()
            p:press(100, true)
            p:settle()
            assert.equals("pen", p.current_tool)
        end)

        it("release under an overlay still clears the held state", function()
            local p = createMockPencil()
            p:onStylusButtonPress()
            p._overlay = true
            assert.is_false(p:onStylusButtonRelease())
            assert.is_false(p.side_button_down)
            assert.is_false(p.side_button_used_for_highlight)
            assert.equals("pen", p.current_tool)
        end)

        it("release without press does nothing", function()
            local p = createMockPencil()
            p:onStylusButtonRelease()
            assert.equals("pen", p.current_tool)
        end)

        it("highlight state survives a press that arrives mid-highlight", function()
            local p = createMockPencil()
            p.highlighting = true
            p.side_button_used_for_highlight = true
            p:onStylusButtonPress()
            assert.is_true(p.side_button_used_for_highlight)
        end)
    end)

    describe("tap action setting", function()

        it("defaults to pencil/eraser and leaves the mode alone", function()
            local p = createMockPencil()
            p:press(100)
            p:settle()
            assert.equals("eraser", p.current_tool)
            assert.equals(MODE_PEN, p.input_mode)
        end)

        it("mode setting toggles finger/pen and leaves the tool alone", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            p:press(100)
            p:settle()
            assert.equals(MODE_FINGER, p.input_mode)
            assert.equals("pen", p.current_tool)
            p:press(100)
            p:settle()
            assert.equals(MODE_PEN, p.input_mode)
        end)

        it("mode toggle is persisted", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            p:press(100)
            p:settle()
            assert.equals(1, p._saved)
        end)

        it("hold in finger mode does not toggle", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE, input_mode = MODE_FINGER })
            p:press(SIDE_BUTTON_TAP_MAX_MS + 1)
            p:settle()
            assert.equals(MODE_FINGER, p.input_mode)
            assert.equals("pen", p.current_tool)
        end)

        it("hold used for highlighting in finger mode does not toggle", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE, input_mode = MODE_FINGER })
            p:press(100, true)
            p:settle()
            assert.equals(MODE_FINGER, p.input_mode)
        end)
    end)

    describe("hold + tap the page", function()

        it("short still contact is a tap", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            assert.is_true(p:contact(120))
            p:settle()
            assert.equals(MODE_FINGER, p.input_mode)
        end)

        it("jitter within the threshold is still a tap", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            assert.is_true(p:contact(120, SIDE_BUTTON_TAP_MAX_PX, -SIDE_BUTTON_TAP_MAX_PX))
            p:settle()
        end)

        it("a drag is not a tap", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            assert.is_false(p:contact(120, SIDE_BUTTON_TAP_MAX_PX + 1, 0))
            p:settle()
            assert.equals(MODE_PEN, p.input_mode)
        end)

        it("movement stays remembered even if the tip returns", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            p:beginSideButtonContact(100, 100)
            p:trackSideButtonContact(150, 100)
            p:trackSideButtonContact(100, 100)
            assert.is_false(p:takeSideButtonTap())
        end)

        it("a long press on the page is not a tap", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            assert.is_false(p:contact(SIDE_BUTTON_TAP_MAX_MS + 1))
            p:settle()
        end)

        it("no contact record means no tap", function()
            local p = createMockPencil()
            assert.is_false(p:takeSideButtonTap())
        end)

        it("the record is consumed", function()
            local p = createMockPencil()
            p:beginSideButtonContact(100, 100)
            assert.is_true(p:takeSideButtonTap())
            assert.is_false(p:takeSideButtonTap())
        end)

        it("works from finger mode back to pen mode", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE, input_mode = MODE_FINGER })
            assert.is_true(p:contact(120))
            p:settle()
            assert.equals(MODE_PEN, p.input_mode)
        end)

        it("toggles the tool under the default setting", function()
            local p = createMockPencil()
            assert.is_true(p:contact(120))
            p:settle()
            assert.equals("eraser", p.current_tool)
            assert.equals(MODE_PEN, p.input_mode)
        end)
    end)

    describe("hold + double tap", function()

        it("a single tap acts only after the double-tap window", function()
            local p = createMockPencil()
            p:onStylusButtonPress()
            p:beginSideButtonContact(100, 100)
            p:advance(50)
            assert.is_true(p:takeSideButtonTap())
            p:onSideButtonTap()
            assert.equals("pen", p.current_tool)
            p:advance(SIDE_BUTTON_DOUBLE_TAP_MS - 1)
            assert.equals("pen", p.current_tool)
            p:advance(1)
            assert.equals("eraser", p.current_tool)
            assert.equals(0, p._note_menus)
        end)

        it("two taps within the window open the pen note menu and do not toggle", function()
            local p = createMockPencil()
            p:onSideButtonTap()
            p:advance(SIDE_BUTTON_DOUBLE_TAP_MS - 1)
            p:onSideButtonTap()
            p:advance(SIDE_BUTTON_DOUBLE_TAP_MS * 2)
            assert.equals(1, p._note_menus)
            assert.equals("pen", p.current_tool)
            assert.is_nil(p.side_button_tap_pending)
        end)

        it("two taps further apart toggle twice", function()
            local p = createMockPencil()
            p:onSideButtonTap()
            p:advance(SIDE_BUTTON_DOUBLE_TAP_MS)
            assert.equals("eraser", p.current_tool)
            p:onSideButtonTap()
            p:advance(SIDE_BUTTON_DOUBLE_TAP_MS)
            assert.equals("pen", p.current_tool)
            assert.equals(0, p._note_menus)
        end)

        it("a third tap starts a new single tap", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            p:onSideButtonTap()
            p:onSideButtonTap()
            p:onSideButtonTap()
            assert.equals(1, p._note_menus)
            assert.equals(MODE_PEN, p.input_mode)
            p:settle()
            assert.equals(MODE_FINGER, p.input_mode)
        end)
    end)

    describe("finger passthrough", function()

        it("never passes through in pen mode", function()
            local p = createMockPencil()
            assert.is_false(p:isFingerPassthrough(false, false))
        end)

        it("passes a bare pen tip through in finger mode", function()
            local p = createMockPencil({ input_mode = MODE_FINGER })
            assert.is_true(p:isFingerPassthrough(false, false))
        end)

        it("keeps the eraser end", function()
            local p = createMockPencil({ input_mode = MODE_FINGER })
            assert.is_false(p:isFingerPassthrough(true, false))
            p.eraser_button_active = true
            assert.is_false(p:isFingerPassthrough(false, false))
        end)

        it("keeps the pen while the side button is held", function()
            local p = createMockPencil({ input_mode = MODE_FINGER })
            assert.is_false(p:isFingerPassthrough(false, true))
            p:onStylusButtonPress()
            assert.is_false(p:isFingerPassthrough(false, false))
        end)

        it("keeps a contact it already started handling", function()
            local p = createMockPencil({ input_mode = MODE_FINGER })
            p.pen_down = true
            assert.is_false(p:isFingerPassthrough(false, false))
        end)
    end)

    describe("setInputMode", function()

        it("rejects unknown modes", function()
            local p = createMockPencil()
            assert.has_error(function() p:setInputMode("mouse") end)
        end)

        it("setting the same mode is a no-op", function()
            local p = createMockPencil()
            p:setInputMode(MODE_PEN)
            assert.equals(0, p._saved)
        end)

    end)
end)
