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

    function mock:onSideButtonTap()
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

    function mock:onStylusButtonRelease()
        local was_down = self.side_button_down
        self.side_button_down = false
        local held_ms = self.side_button_press_time and (self.now_ms - self.side_button_press_time) or 0
        self.side_button_press_time = nil
        if was_down and not self.side_button_used_for_highlight and held_ms <= SIDE_BUTTON_TAP_MAX_MS then
            self:onSideButtonTap()
        end
        self.side_button_used_for_highlight = false
        return true
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
            assert.equals("eraser", p.current_tool)
        end)

        it("press at the threshold still counts as a tap", function()
            local p = createMockPencil()
            p:press(SIDE_BUTTON_TAP_MAX_MS)
            assert.equals("eraser", p.current_tool)
        end)

        it("long hold does not toggle", function()
            local p = createMockPencil()
            p:press(SIDE_BUTTON_TAP_MAX_MS + 1)
            assert.equals("pen", p.current_tool)
        end)

        it("press used for highlighting does not toggle", function()
            local p = createMockPencil()
            p:press(100, true)
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
            assert.equals("eraser", p.current_tool)
            assert.equals(MODE_PEN, p.input_mode)
        end)

        it("mode setting toggles finger/pen and leaves the tool alone", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            p:press(100)
            assert.equals(MODE_FINGER, p.input_mode)
            assert.equals("pen", p.current_tool)
            p:press(100)
            assert.equals(MODE_PEN, p.input_mode)
        end)

        it("mode toggle is persisted", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE })
            p:press(100)
            assert.equals(1, p._saved)
        end)

        it("hold in finger mode does not toggle", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE, input_mode = MODE_FINGER })
            p:press(SIDE_BUTTON_TAP_MAX_MS + 1)
            assert.equals(MODE_FINGER, p.input_mode)
            assert.equals("pen", p.current_tool)
        end)

        it("hold used for highlighting in finger mode does not toggle", function()
            local p = createMockPencil({ side_button_tap = SIDE_BUTTON_TAP_MODE, input_mode = MODE_FINGER })
            p:press(100, true)
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
