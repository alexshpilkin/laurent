local width, height = 256, 256

local ppm = require 'ppm'
local srgb = require 'srgb'

local pic = assert(ppm("render.ppm", 'w'))
pic:format(width, height)
for j = height - 1, 0, -1 do
	for i = 0, width - 1 do
		pic:pixel(srgb(i / (width - 1), j / (height - 1), 0.25))
	end
end
