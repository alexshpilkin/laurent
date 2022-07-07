local image = require 'image'
local isatty = require 'isatty'
local options = require 'options'
local srgb = require 'srgb'

local add, box, const, lift, x, y = image.add, image.box, image.const, image.lift, image.x, image.y

local opts, args = options '+f:o:v'
assert(#args == 0)
local fmtsubs = options.sub(options.all('-f', opts))
local fmt, fmtopts = require(options.last('', fmtsubs) or 'xyze'), {
	width  = options.last('width=',  fmtsubs) or 256,
	height = options.last('height=', fmtsubs) or 256,
	depth  = options.last('depth=',  fmtsubs),
}
local out = options.last('-o', opts)
if not out then
	assert(not isatty(io.output())) --FIXME Windows
elseif out == '-' then
	out = io.output()
end

local trace
if options.last('v', opts) and isatty(io.stderr) then
	local format, stderr = string.format, io.stderr
	function trace(...) return stderr:write(format(...)) end
else
	function trace() end
end

local img = add(box, lift(srgb, x, y, const(0.25)))

local pic = assert(fmt(out, fmtopts))
local width, height = pic.width, pic.height
for j = height - 1, 0, -1 do
	trace('%d / %d lines', height-j-1, height)
	for i = 0, width - 1 do
		pic(img:value(i / (width - 1), j / (height - 1)))
	end
	trace('\r\27[K')
end
