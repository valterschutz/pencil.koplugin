--[[--
Pen note export helpers that need nothing from KOReader: file names for
the exported files and a PDF writer that puts one RGB image on each page.
Painting the note pages and writing the files is the plugin's job (see
Pencil:exportNotes in main.lua).

@module pencil.lib.export
--]]--

local Export = {}

--- str made safe for a file name on any file system: the characters VFAT
-- forbids and control characters become "_", runs of whitespace collapse
-- to one space, leading spaces and trailing dots and spaces go, and the
-- result is cut to max_chars UTF-8 characters.
function Export.safeName(str, max_chars)
    assert(type(str) == "string", "name must be a string")
    assert(type(max_chars) == "number" and max_chars > 0, "max_chars must be positive")
    str = str:gsub("%s+", " "):gsub("[%c\\/:*?\"<>|]", "_"):gsub("^ ", "")
    local chars = {}
    for char in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #chars == max_chars then break end
        chars[#chars + 1] = char
    end
    return (table.concat(chars):gsub("[%. ]+$", ""))
end

--- "<label>.<ext>" with the label made safe; ext is left out when nil so
-- the result can take a page suffix first.
function Export.fileName(label, max_chars, ext)
    local name = Export.safeName(label, max_chars)
    assert(name ~= "", "name is empty once made safe: " .. label)
    if ext then
        name = name .. "." .. ext
    end
    return name
end

--- File name of page index of count: the stem alone for a single page,
-- "stem - p01.ext" style otherwise, zero-padded so the names sort.
function Export.pageFileName(stem, index, count, ext)
    assert(type(count) == "number" and count >= 1, "count must be positive")
    assert(type(index) == "number" and index >= 1 and index <= count, "page index out of range: " .. tostring(index))
    if count == 1 then
        return stem .. "." .. ext
    end
    local width = #tostring(count)
    return string.format("%s - p%0" .. width .. "d.%s", stem, index, ext)
end

--- The labels with " (2)", " (3)", ... appended to repeats so no two
-- exported files share a name. Order is kept.
function Export.uniqueLabels(labels)
    local seen = {}
    local unique = {}
    for i, label in ipairs(labels) do
        local n = (seen[label] or 0) + 1
        seen[label] = n
        unique[i] = n == 1 and label or string.format("%s (%d)", label, n)
    end
    return unique
end

--- Writes a PDF with one RGB image per page, page by page, so a book's
-- worth of screen-size pages never sits in memory at once. write(bytes)
-- receives the file in order; dpi maps image pixels to points so the pages
-- keep the screen's physical size; deflate(bytes), if given, compresses
-- each image in zlib format, which is what /FlateDecode expects.
local PdfWriter = {}
PdfWriter.__index = PdfWriter
Export.PdfWriter = PdfWriter

local CATALOG_OBJECT = 1
local PAGES_OBJECT = 2

function PdfWriter.new(write, dpi, deflate)
    assert(type(write) == "function", "write must be a function")
    assert(type(dpi) == "number" and dpi > 0, "dpi must be positive")
    assert(deflate == nil or type(deflate) == "function", "deflate must be a function")
    local self = setmetatable({
        write = write,
        dpi = dpi,
        deflate = deflate,
        written = 0,       -- bytes emitted so far, i.e. the offset of the next one
        offsets = {},      -- object number -> byte offset of its "N 0 obj"
        next_object = PAGES_OBJECT + 1,
        pages = {},        -- object numbers of the page objects, in order
        finished = false,
    }, PdfWriter)
    self:emit("%PDF-1.4\n%\226\227\207\211\n")
    return self
end

function PdfWriter:emit(bytes)
    self.write(bytes)
    self.written = self.written + #bytes
end

function PdfWriter:beginObject(number)
    if number == nil then
        number = self.next_object
        self.next_object = number + 1
    end
    assert(self.offsets[number] == nil, "object written twice: " .. number)
    self.offsets[number] = self.written
    self:emit(number .. " 0 obj\n")
    return number
end

-- A length in points as PDF wants it: a decimal point whatever the locale.
local function points(pixels, dpi)
    return (string.format("%.3f", pixels * 72 / dpi):gsub(",", "."))
end

--- Appends a page showing the width x height image whose pixels are the
-- rgb string (three bytes per pixel, rows top to bottom). Returns the
-- page number.
function PdfWriter:addImagePage(width, height, rgb)
    assert(not self.finished, "the PDF is finished")
    assert(type(width) == "number" and width >= 1 and width % 1 == 0, "width must be a positive integer")
    assert(type(height) == "number" and height >= 1 and height % 1 == 0, "height must be a positive integer")
    assert(type(rgb) == "string" and #rgb == width * height * 3, "rgb must hold width * height RGB triplets")
    local data, filter = rgb, ""
    if self.deflate then
        data, filter = self.deflate(rgb), "/Filter /FlateDecode "
    end
    local image = self:beginObject()
    self:emit(string.format("<< /Type /XObject /Subtype /Image /Width %d /Height %d"
        .. " /ColorSpace /DeviceRGB /BitsPerComponent 8 %s/Length %d >>\nstream\n",
        width, height, filter, #data))
    self:emit(data)
    self:emit("\nendstream\nendobj\n")

    local w, h = points(width, self.dpi), points(height, self.dpi)
    local content = string.format("q %s 0 0 %s 0 0 cm /Im0 Do Q", w, h)
    local contents = self:beginObject()
    self:emit(string.format("<< /Length %d >>\nstream\n%s\nendstream\nendobj\n", #content, content))

    local page = self:beginObject()
    self:emit(string.format("<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %s %s]"
        .. " /Resources << /XObject << /Im0 %d 0 R >> >> /Contents %d 0 R >>\nendobj\n",
        PAGES_OBJECT, w, h, image, contents))
    table.insert(self.pages, page)
    return #self.pages
end

--- Writes the page tree, the catalog, the cross-reference table and the
-- trailer. Nothing may be added afterwards.
function PdfWriter:finish()
    assert(not self.finished, "the PDF is finished")
    assert(#self.pages >= 1, "a PDF needs at least one page")
    self.finished = true

    local kids = {}
    for i, page in ipairs(self.pages) do
        kids[i] = page .. " 0 R"
    end
    self:beginObject(PAGES_OBJECT)
    self:emit(string.format("<< /Type /Pages /Kids [%s] /Count %d >>\nendobj\n", table.concat(kids, " "), #self.pages))
    self:beginObject(CATALOG_OBJECT)
    self:emit(string.format("<< /Type /Catalog /Pages %d 0 R >>\nendobj\n", PAGES_OBJECT))
    local info = self:beginObject()
    self:emit("<< /Producer (pencil.koplugin) >>\nendobj\n")

    local count = self.next_object - 1
    local xref = self.written
    local lines = { "xref", "0 " .. (count + 1), "0000000000 65535 f " }
    for number = 1, count do
        assert(self.offsets[number], "object never written: " .. number)
        lines[#lines + 1] = string.format("%010d 00000 n ", self.offsets[number])
    end
    self:emit(table.concat(lines, "\n") .. "\n")
    self:emit(string.format("trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n",
        count + 1, CATALOG_OBJECT, info, xref))
end

return Export
