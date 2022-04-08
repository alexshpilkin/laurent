local width, height = 256, 256

local ppm = require 'ppm'
local bt709 = require 'bt709' -- FIXME use sRGB outside testing

local pic = assert(ppm("render.ppm", 'w'))
pic:format(width, height)
for j = height - 1, 0, -1 do
	for i = 0, width - 1 do
		pic:pixel(bt709(i / (width - 1), j / (height - 1), 0.25))
	end
end
