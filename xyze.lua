-- The Radiance HDR format seems to lack an authoritative definition, but
-- the Radiance file formats document[1] referenced by the IANA media type
-- application for image/vnd.radiance[2] at least tries.

-- [1]: https://floyd.lbl.gov/radiance/refer/filefmts.pdf
-- [2]: https://www.iana.org/assignments/media-types/image/vnd.radiance

-- The article in Graphics Gems II (1991) that document refers to is not
-- freely available and in any case only describes the pixel encoding, not
-- the file format, but its accompanying code[3,4], extracted from an old
-- version of Radiance, gives an idea of the format as well.  Of course,
-- nowadays all of Radiance is open source[5], but the code inside is not
-- substantially different, only somewhat modernized.  Other people[6] have
-- also taken a stab at turning the Graphics Gems code into a proper
-- reference implementation.

-- [3]: https://floyd.lbl.gov/radiance/refer/Notes/picture_format.html
-- [4]: http://www.realtimerendering.com/resources/GraphicsGems/gemsii/RealPixels/
-- [5]: https://radiance-online.org//cgi-bin/viewcvs.cgi/ray/?pathrev=MAIN
-- [6]: https://www.graphics.cornell.edu/online/formats/rgbe/

-- One important caveat[7,8] that is only apparent from the code, not the
-- prose descriptions, is that Radiance turns the usual convention on its
-- head by quantizing with floor() and dequantizing with round().

-- [7]: https://cbloomrants.blogspot.com/2020/06/widespread-error-in-radiance-hdr-rgbe.html
-- [8]: https://cbloomrants.blogspot.com/2020/06/followup-tidbits-on-rgbe.html

-- Infuriatingly, pfstools cannot handle XYZE-flavoured Radiance images,
-- only RGBE ones.  ImageMagick and Luminance HDR do handle both.

local xyze = setmetatable({__name = 'xyze'}, {__call = function (self, ...)
	return self.open(...)
end})
xyze.__index = xyze

local tonumber = tonumber
local abs, floor, log, max, min = math.abs, math.floor, math.log, math.max, math.min
local char, format = string.char, string.format

local function try(...)
	local ok, result = pcall(...)
	if ok then return result end
end

local log2 = log(2)
local frexp =
	math.frexp or -- Lua 5.2-
	try(function ()
		local ffi = require 'ffi'
		ffi.cdef [[ double frexp(double, int *); ]]
		local _frexp, _int = ffi.C.frexp, ffi.typeof 'int [1]'
		return _frexp and function (x)
			local e = _int()
			local m = _frexp(tonumber(x), e)
			return m, e[0]
		end
	end) or
	try(function () return require 'mathx'.frexp end) or
	function (x)
		x = tonumber(x)
		if x == 0 or x + x == x or x ~= x then return x, 0 end
		local e = floor(log(abs(x)) / log2)
		x = x / 2^e
		if x >= 2 then x, e = x / 2, e + 1 end
		return x / 2, e + 1
	end

local ldexp =
	math.ldexp or -- Lua 5.2-
	try(function ()
		local ffi = require 'ffi'
		ffi.cdef [[ double ldexp(double, int); ]]
		local _ldexp = ffi.C.ldexp
		return _ldexp and function (m, e)
			return _ldexp(tonumber(m), floor(tonumber(e) + 0.5))
		end
	end) or
	try(function () return require 'mathx'.ldexp end) or
	function (m, e)
		m, e = tonumber(m), floor(tonumber(e) + 0.5)
		if m == 0 or m + m == m or m ~= m then return m end
		local halfe = floor(e / 2)
		return m * 2^halfe * 2^(e - halfe)
	end

function xyze.open(file, width, height, options)
	if width == nil then -- open{file, ...}
		options, file = file, file[1]
	elseif height == nil then -- open(file, {...})
		options = width
	elseif options == nil then -- open(file, width, height)
		options = {}
	-- else -- open(file, width, height, {...})
	end

	if file == nil then
		file = io.output() -- pray it is in the right mode
	elseif not pcall(function () assert(file.write) end) then
		local err
		file, err = io.open(file, 'wb')
		if not file then return nil, err end
	end
	width  = assert(tonumber(options.width or width))
	height = assert(tonumber(options.height or height))

	file:write(format('#?RADIANCE\n' ..
	                  'FORMAT=32-bit_rle_xyze\n' ..
	                  'SOFTWARE=rtiow/xyze.lua $Id$\n' ..
	                  '\n-Y %d +X %d\n',
	                  height, width))

	return setmetatable({
		file = file, width = width, height = height,
		k = 0, n = width * height
	}, xyze)
end

local m = ldexp(511 / 512, 127) -- maximum representable value (center)

local function encode(x, y, z)

	-- Note that the top bit in the mantissa is encoded, as an exponent
	-- that normalizes the maximum component may not normalize the rest
	-- of them.  A normal colour triple (not an RLE tag) thus has the
	-- high bit set in at least one of the mantissas.  Absolute black
	-- is exceptionally encoded as {0,0,0,0}, and Radiance will decode
	-- any value with a zero exponent as black.

	x, y, z = max(0, min(m, x)), max(0, min(m, y)), max(0, min(m, z))
	local _, e = frexp(max(x, y, z)) -- e = 0 if max = 0
	x, y, z, e = ldexp(x, 8-e), ldexp(y, 8-e), ldexp(z, 8-e), e + 128
	if e <= 0 then x, y, z, e = 0, 0, 0, 0 end
	return (char(floor(x), floor(y), floor(z), e))
end

function xyze:__call(...) self:putpx(...) end

function xyze:putpx(x, y, z)
	local k = self.k + 1
	self.file:write(encode(x, y, z))

	if k == self.n then
		self.file:close()
		self.file, k = nil, nil
	end
	self.k = k
end

return xyze
