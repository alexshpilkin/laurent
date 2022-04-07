local width, height = 256, 256

local srgb = require 'srgb'
local format = string.format
local rgb, quant, tosrgb = srgb.xyz, srgb.quant, srgb.rgb

local file = assert(io.open("render.ppm", 'w'))
file:write(format('P3\n%s %s\n255\n', width, height))
for j = height - 1, 0, -1 do
	local intr = ''
	for i = 0, width - 1 do
		local x, y, z = rgb(i / (width - 1), j / (height - 1), 0.25)

		local r, g, b = tosrgb(x, y, z)
		file:write(format('%s%s %s %s', intr,
		                  quant(r, 0, 255),
		                  quant(g, 0, 255),
		                  quant(b, 0, 255)))
		intr = ' '
	end
	file:write('\n')
end
file:close()
