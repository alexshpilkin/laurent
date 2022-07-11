local image = require 'image'
local isatty = require 'isatty'
local options = require 'options'
local srgb = require 'srgb'

local add, average, box, const, filter, grid2, jitter2, lift, mul, radial, scale, separable, translate, triangle, x, y = image.add, image.average, image.box, image.const, image.filter, image.grid2, image.jitter2, image.lift, image.mul, image.radial, image.scale, image.separable, image.translate, image.triangle, image.x, image.y

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

local img = translate(mul(radial(box), const(srgb(0, 0, 1))), 0, -0.25)
img = mul(img, scale(filter(scale(separable(triangle, box), 0.5), grid2), 0.1))
img = translate(scale(img, 0.5), 0.5)
img = add(img, lift(srgb, x, y, const(0.25)))

local pic = assert(fmt(out, fmtopts))
local width, height = pic.width, pic.height
img = filter(img, scale(average(jitter2, 64), 1 / width, 1 / height))
for j = height - 1, 0, -1 do
	trace('%d / %d lines', height-j-1, height)
	for i = 0, width - 1 do
		pic(img:value(i / (width - 1), j / (height - 1)))
	end
	trace('\r\27[K')
end
