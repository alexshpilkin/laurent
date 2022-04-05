local width, height = 256, 256

local floor, max, min = math.floor, math.max, math.min
local format = string.format

local function clamp(x, lo, hi)
	return max(lo, min(hi, x))
end

local file = assert(io.open("render.ppm", 'w'))
file:write(format('P3\n%s %s\n255\n', width, height))
for j = height - 1, 0, -1 do
	local intr = ''
	for i = 0, width - 1 do
		local r, g, b = i / (width - 1), j / (height - 1), 0.25
		file:write(format('%s%s %s %s', intr,
		                  clamp(floor(r * 256), 0, 255),
		                  clamp(floor(g * 256), 0, 255),
		                  clamp(floor(b * 256), 0, 255)))
		intr = ' '
	end
	file:write('\n')
end
file:close()
