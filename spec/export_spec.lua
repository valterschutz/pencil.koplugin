--[[--
Unit tests for the export helpers (lib/export.lua): file names and the
PDF writer.
Run with: busted spec/export_spec.lua
--]]--

package.path = package.path .. ";pencil.koplugin/?.lua"

local Export = require("lib/export")

-- Builds a PDF in memory; deflate is optional.
local function buildPdf(pages, dpi, deflate)
    local chunks = {}
    local writer = Export.PdfWriter.new(function(bytes) table.insert(chunks, bytes) end, dpi, deflate)
    for _, page in ipairs(pages) do
        writer:addImagePage(page.w, page.h, page.rgb)
    end
    writer:finish()
    return table.concat(chunks)
end

local function solid(w, h, r, g, b)
    return string.rep(string.char(r, g, b), w * h)
end

-- The byte offsets listed in the cross-reference table, by object number.
local function xrefOffsets(pdf)
    local startxref = tonumber(pdf:match("startxref\n(%d+)\n%%%%EOF\n$"))
    assert(startxref, "no startxref")
    assert.equals("xref", pdf:sub(startxref + 1, startxref + 4))
    local count = tonumber(pdf:match("^xref\n0 (%d+)\n", startxref + 1))
    local offsets = {}
    local pos = pdf:find("\n", startxref + 1) + 1
    pos = pdf:find("\n", pos) + 1
    for number = 0, count - 1 do
        local entry = pdf:sub(pos, pos + 19)
        assert.equals(20, #entry)
        local offset, kind = entry:match("^(%d%d%d%d%d%d%d%d%d%d) %d%d%d%d%d ([fn]) \n$")
        assert(offset, "malformed xref entry: " .. entry)
        if kind == "n" then
            offsets[number] = tonumber(offset)
        end
        pos = pos + 20
    end
    return offsets, count
end

describe("Export", function()

    describe("safeName", function()
        it("replaces what VFAT forbids and collapses whitespace", function()
            assert.equals("a_b_c_d_e_f_g_h_i", Export.safeName('a/b\\c:d*e?f"g<h>i', 100))
            assert.equals("one two three", Export.safeName("  one \n two\t\tthree  ", 100))
            assert.equals("tab_here", Export.safeName("tab\1here", 100))
        end)

        it("drops trailing dots and spaces and cuts to max_chars", function()
            assert.equals("name", Export.safeName("name. . ", 100))
            assert.equals("ab", Export.safeName("abcdef", 2))
            assert.equals("åäö", Export.safeName("åäöx", 3))
            assert.equals("ab", Export.safeName("ab   .cd", 4))
        end)

        it("validates its input", function()
            assert.has_error(function() Export.safeName(nil, 10) end)
            assert.has_error(function() Export.safeName("x", 0) end)
        end)
    end)

    describe("fileName", function()
        it("makes the label safe and adds the extension", function()
            assert.equals("Chapter - One_Two.pdf", Export.fileName("Chapter - One/Two", 100, "pdf"))
            assert.equals("Page 3", Export.fileName("Page 3", 100))
        end)

        it("refuses names that vanish once made safe", function()
            assert.has_error(function() Export.fileName("...", 100, "pdf") end)
            assert.has_error(function() Export.fileName("  ", 100, "pdf") end)
        end)
    end)

    describe("pageFileName", function()
        it("uses the stem alone for a single page and pads multi-page suffixes", function()
            assert.equals("stem.png", Export.pageFileName("stem", 1, 1, "png"))
            assert.equals("stem - p2.png", Export.pageFileName("stem", 2, 3, "png"))
            assert.equals("stem - p07.png", Export.pageFileName("stem", 7, 12, "png"))
            assert.equals("stem - p12.png", Export.pageFileName("stem", 12, 12, "png"))
        end)

        it("rejects an index outside the page count", function()
            assert.has_error(function() Export.pageFileName("stem", 0, 1, "png") end)
            assert.has_error(function() Export.pageFileName("stem", 3, 2, "png") end)
        end)
    end)

    describe("uniqueLabels", function()
        it("numbers repeats in order and leaves the rest alone", function()
            assert.same({ "a", "b", "a (2)", "c", "a (3)", "b (2)" },
                Export.uniqueLabels({ "a", "b", "a", "c", "a", "b" }))
            assert.same({}, Export.uniqueLabels({}))
        end)
    end)

    describe("PdfWriter", function()
        it("writes a valid header, objects, cross-reference table and trailer", function()
            local pdf = buildPdf({ { w = 2, h = 3, rgb = solid(2, 3, 255, 0, 0) } }, 72)
            assert.equals("%PDF-1.4\n", pdf:sub(1, 9))
            local offsets, count = xrefOffsets(pdf)
            -- image, contents, page, pages, catalog, info + the free entry
            assert.equals(7, count)
            for number = 1, count - 1 do
                assert.equals(number .. " 0 obj\n", pdf:sub(offsets[number] + 1, offsets[number] + #(number .. " 0 obj\n")))
            end
            assert.truthy(pdf:find("/Type /Catalog /Pages 2 0 R", 1, true))
            assert.truthy(pdf:find("/Type /Pages /Kids [5 0 R] /Count 1", 1, true))
            assert.truthy(pdf:find("/Size 7 /Root 1 0 R /Info 6 0 R", 1, true))
        end)

        it("stores the raw image with its size in points at the given dpi", function()
            local rgb = solid(2, 3, 1, 2, 3)
            local pdf = buildPdf({ { w = 2, h = 3, rgb = rgb } }, 300)
            assert.truthy(pdf:find("/Width 2 /Height 3 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 18 >>\nstream\n" .. rgb .. "\nendstream", 1, true))
            assert.is_nil(pdf:find("FlateDecode", 1, true))
            assert.truthy(pdf:find("/MediaBox [0 0 0.480 0.720]", 1, true))
            assert.truthy(pdf:find("q 0.480 0 0 0.720 0 0 cm /Im0 Do Q", 1, true))
        end)

        it("deflates the image when given a compressor", function()
            local compressed = "zz"
            local pdf = buildPdf({ { w = 1, h = 1, rgb = "abc" } }, 72, function(data)
                assert.equals("abc", data)
                return compressed
            end)
            assert.truthy(pdf:find("/Filter /FlateDecode /Length 2 >>\nstream\nzz\nendstream", 1, true))
        end)

        it("lists every page in order", function()
            local pdf = buildPdf({
                { w = 1, h = 1, rgb = "abc" },
                { w = 1, h = 1, rgb = "def" },
                { w = 1, h = 1, rgb = "ghi" },
            }, 72)
            assert.truthy(pdf:find("/Kids [5 0 R 8 0 R 11 0 R] /Count 3", 1, true))
            local offsets, count = xrefOffsets(pdf)
            assert.equals(13, count)
            assert.equals(12, #offsets)
        end)

        it("validates pages and refuses use after finish", function()
            local writer = Export.PdfWriter.new(function() end, 300)
            assert.has_error(function() writer:addImagePage(2, 2, "short") end)
            assert.has_error(function() writer:addImagePage(0, 2, "") end)
            assert.has_error(function() writer:finish() end)  -- no pages
            writer:addImagePage(1, 1, "abc")
            writer:finish()
            assert.has_error(function() writer:addImagePage(1, 1, "abc") end)
            assert.has_error(function() writer:finish() end)
            assert.has_error(function() Export.PdfWriter.new(nil, 300) end)
            assert.has_error(function() Export.PdfWriter.new(function() end, 0) end)
        end)
    end)
end)
