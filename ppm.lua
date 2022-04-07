local ppm = setmetatable({__name = 'ppm'}, {__call = function (self, ...)
	return self.open(...)
end})
ppm.__index = ppm

local format = string.format
local srgb = require 'srgb'
local quant, rgb = srgb.quant, srgb.rgb

function ppm.open(file, ...)
	if file == nil then
		file = io.output() -- pray it is in the right mode
	elseif type(file) == 'string' then
		local err
		file, err = io.open(file, ...)
		if not file then return nil, err end
	end
	return setmetatable({file = file}, ppm)
end

function ppm:format(width, height, depth)
	width, height = tonumber(width), tonumber(height)
	self.width, self.height = width, height
	local maxval = 2^(depth ~= nil and tonumber(depth) or 8) - 1
	self.maxval = maxval

	self.file:write(format('P3\n%s %s\n%s\n', width, height, maxval))
	self.i, self.j = 0, 0
end

function ppm:pixel(x, y, z)
	local file, maxval, i = self.file, self.maxval, self.i

	-- The PNM specifications say to limit ourselves to 70 chars/line,
	-- but meh, the files are easier to inspect this way.

	local r, g, b = rgb(x, y, z)
	file:write(format('%s%3s %3s %3s',
	                  i ~= 0 and '  ' or '',
	                  quant(r, 0, maxval),
	                  quant(g, 0, maxval),
	                  quant(b, 0, maxval)))

	i = i + 1
	if i == self.width then
		file:write('\n')
		i = 0; local j = self.j + 1
		if j == self.height then
			i, j = nil, nil
			self.file:close()
		end
		self.j = j
	end
	self.i = i
end

return ppm
