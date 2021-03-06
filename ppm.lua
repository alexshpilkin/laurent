local bt709 = require 'bt709'

local assert, pcall, setmetatable, tonumber = assert, pcall, setmetatable, tonumber
local open, output = io.open, io.output
local quant, rgb_ = bt709.quant, bt709.rgb_
local format = string.format

local _ENV = {}
if setfenv then setfenv(1, _ENV) end

__index = _ENV

setmetatable(_ENV, {__call = function (self, file, width, height, options)
	if width == nil then -- open{file, ...}
		options, file = file, file[1]
	elseif height == nil then -- open(file, {...})
		options = width
	elseif options == nil then -- open(file, width, height)
		options = {}
	-- else -- open(file, width, height, {...})
	end

	if file == nil then
		file = output() -- pray it is in the right mode
	elseif not pcall(function () assert(file.write) end) then
		local err
		file, err = open(file, 'wb')
		if not file then return nil, err end
	end
	width  = assert(tonumber(options.width or width))
	height = assert(tonumber(options.height or height))
	local maxval = 2^assert(tonumber(options.depth or 8)) - 1
	assert(maxval < 65536)

	file:write(format('P3\n%d %d\n%d\n', width, height, maxval))

	return setmetatable({
		file = file, width = width, height = height, maxval = maxval,
		i = 0, j = 0
	}, self)
end})

function __call(self, ...) self:putxyz(...) end

function putxyz(self, ...)
	local file, maxval, i = self.file, self.maxval, self.i + 1

	-- The PNM specifications say to limit ourselves to 70 chars/line,
	-- but meh, the files are easier to inspect this way.

	local c = quant(rgb_(...), 0, maxval)
	file:write(format('%s%3d %3d %3d',
	                  i > 1 and '  ' or '',
	                  c.r, c.g, c.b))

	if i == self.width then
		file:write('\n')
		i = 0; local j = self.j + 1
		if j == self.height then
			file:close()
			self.file, i, j = nil, nil, nil
		end
		self.j = j
	end
	self.i = i
end

return _ENV
