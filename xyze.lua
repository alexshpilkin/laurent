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

local lg = require 'lg'

local clamp, floor, frexp, ldexp, number3 = lg.clamp, lg.floor, lg.frexp, lg.ldexp, lg.number3
local max = math.max
local char, format = string.char, string.format

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
	                  '\n-Y %d +X %d\n',
	                  height, width))

	return setmetatable({
		file = file, width = width, height = height,
		k = 0, n = width * height
	}, xyze)
end

local m = ldexp(511 / 512, 127) -- maximum representable value (center)

local function encode(...)

	-- Note that the top bit in the mantissa is encoded, as an exponent
	-- that normalizes the maximum component may not normalize the rest
	-- of them.  A normal colour triple (not an RLE tag) thus has the
	-- high bit set in at least one of the mantissas.  Absolute black
	-- is exceptionally encoded as {0,0,0,0}, and Radiance will decode
	-- any value with a zero exponent as black.

	local c = clamp(number3(...), 0, m)
	local _, e = frexp(max(c.x, c.y, c.z)) -- e = 0 if max = 0
	c, e = floor(ldexp(c, 8 - e)), e + 128
	if e <= 0 then c, e = number3(0), 0 end
	return (char(c.x, c.y, c.z, e))
end

function xyze:__call(...) self:putxyz(...) end

function xyze:putxyz(...)
	local file, k = self.file, self.k + 1
	file:write(encode(...))

	if k == self.n then
		file:close()
		self.file, k = nil, nil
	end
	self.k = k
end

return xyze
