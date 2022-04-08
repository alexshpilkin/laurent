-- The impressive stash of yak shavings here is rederives colour space
-- transformations from their defining parameters to the precision
-- required for double-precision floating point rather than the four-digit
-- precision used in the original specifications.

-- This module is not a module of colorimetry.  No interesting science is
-- implemented here.  Nothing original is here.

local rgb = setmetatable({__name = 'rgb'}, {__call = function (self, ...)
	return self.space(...)
end})
rgb.__index = rgb

local abs, max, min = math.abs, math.max, math.min

local unpack = unpack
if unpack == nil then unpack = table.unpack end -- Lua 5.2+

local tointeger = math.tointeger -- Lua 5.3+
if tointeger == nil then function tointeger(x) return x end end

-- This bit of floating-point hackery only works when the floating-point
-- radix is two, but without a builtin round() in Lua we have no choice.

local topbit = 1.0
while true do
	local t = topbit * 2
	if t + 1 == t then break end
	topbit = t
end
local function round(x)
	if not (abs(x) < topbit) then return tointeger(x) end
	if x > 0 then
		return tointeger(x + topbit - topbit)
	else
		return tointeger(x - topbit + topbit)
	end
end

-- This quantization is prescribed by the specifications for both HDTV and
-- sRGB.  Note that it yields half-width quantization intervals around
-- codes for black and white.

-- TODO scRGB can encode negative luminances

function rgb.quant(c, lo, hi)
	return round(max(lo, min(hi, (hi - lo)*c + lo)))
end

function rgb.iquant(c, lo, hi)
	return (max(lo, min(hi, c)) - lo) / (hi - lo)
end

local function each(func, ...)
	local results = {}
	for i = 1, select('#', ...) do
		results[i] = func( (select(i, ...)) )
	end
	return unpack(results)
end

local function dec(value)

	-- The smallest number of digits you need to losslessly represent
	-- any IEEE double is 17 (while the largest number of digits such
	-- that any sequence of them is losslessly representable by a
	-- double is 15).

	return require 'lmpfrlib'.sprintf('% .16Re', value)
end

local function num(value)
	if type(value) ~= 'string' then value = dec(value) end
	return tonumber(value)
end

local function det(m)
	return m[1][1] * m[2][2] * m[3][3]
	     + m[1][2] * m[2][3] * m[3][1]
	     + m[1][3] * m[2][1] * m[3][2]
	     - m[1][3] * m[2][2] * m[3][1]
	     - m[1][2] * m[2][1] * m[3][3]
	     - m[1][1] * m[2][3] * m[3][2]
end

local function solve(m, v)

	-- Cramer's rule is still halfway reasonable for 3x3
	-- matrices.  Rows are easier to switch out than
	-- columns in row-major matrices, and transposing
	-- the matrix does not change its determinant.

	local mt = {{m[1][1], m[2][1], m[3][1]},
		    {m[1][2], m[2][2], m[3][2]},
		    {m[1][3], m[2][3], m[3][3]}}
	local d = det(m)
	return det{v, mt[2], mt[3]} / d,
	       det{mt[1], v, mt[3]} / d,
	       det{mt[1], mt[2], v} / d
end

function rgb:__call(...) return self.xyz_(...) end

function rgb.space(data, ...)
	local space = setmetatable({}, rgb)

	-- To avoid double rounding, whatever values end up being derived
	-- here are stored in data as mpfr objects.  They are converted to
	-- strings only if a data file is generated.  Enough digits are
	-- used that the results should not change if one is not.

	if data.xr == nil then
		local mpfr = require 'lmpfrlib'
		mpfr.set_default_prec(96)

		local xr, yr, zr = each(mpfr.num, unpack(data.r))
		local xg, yg, zg = each(mpfr.num, unpack(data.g))
		local xb, yb, zb = each(mpfr.num, unpack(data.b))
		local xw, yw, zw = each(mpfr.num, unpack(data.w))

		-- The coordinates (chrominances) of the primaries are
		-- projective, that is, up to an overall scaling for each
		-- primary independently.  These scalings are fixed by
		-- requiring that the RGB value of (1, 1, 1) correspond to
		-- the provided white point normalized to unit luminance Y.

		-- In general, to define a frame in an n-dimensional
		-- projective space (of rays in a vector space of dimension
		-- n+1, or in our case of colours) one needs n+2 points in
		-- general position, and their representing vectors can
		-- always be chosen such that n+1 of them make a basis and
		-- the remaining one is the sum of these.

		xw, yw, zw = xw / yw, 1, zw / yw

		-- / xw \   / sr*xr sg*xg sb*xb \ / 1 \
		-- | yw | = | sr*yr sg*yg sb*yb | | 1 |
		-- \ zw /   \ sr*zr sg*zg sb*zb / \ 1 /

		-- / xw \   / xr xg xb \ / sr \
		-- | yw | = | yr yg yb | | sg |
		-- \ zw /   \ zr zg zb / \ sb /

		local sr, sg, sb = solve({{xr, xg, xb},
		                          {yr, yg, yb},
		                          {zr, zg, zb}},
				         {xw, yw, zw})

		xr, yr, zr = sr * xr, sr * yr, sr * zr
		xg, yg, zg = sg * xg, sg * yg, sg * zg
		xb, yb, zb = sb * xb, sb * yb, sb * zb

		data.xr, data.yr, data.zr = xr, yr, zr
		data.xg, data.yg, data.zg = xg, yg, zg
		data.xb, data.yb, data.zb = xb, yb, zb
	end

	local xr, yr, zr = each(num, data.xr, data.yr, data.zr)
	local xg, yg, zg = each(num, data.xg, data.yg, data.zg)
	local xb, yb, zb = each(num, data.xb, data.yb, data.zb)

	function space.xyz(r, g, b)
		return xr*r + xg*g + xb*b,
		       yr*r + yg*g + yb*b,
		       zr*r + zg*g + zb*b
	end
	local xyz = space.xyz

	if data.rx == nil then
		local mpfr = require 'lmpfrlib'
		mpfr.set_default_prec(96)

		local xyz_rgb = {{each(mpfr.num, data.xr, data.xg, data.xb)},
		                 {each(mpfr.num, data.yr, data.yg, data.yb)},
		                 {each(mpfr.num, data.zr, data.zg, data.zb)}}

		-- The transformation in the other direction is described
		-- by the inverse matrix.  (Duh.)

		data.rx, data.gx, data.bx = solve(xyz_rgb, {1, 0, 0})
		data.ry, data.gy, data.by = solve(xyz_rgb, {0, 1, 0})
		data.rz, data.gz, data.bz = solve(xyz_rgb, {0, 0, 1})
	end

	local rx, ry, rz = each(num, data.rx, data.ry, data.rz)
	local gx, gy, gz = each(num, data.gx, data.gy, data.gz)
	local bx, by, bz = each(num, data.bx, data.by, data.bz)

	function space.rgb(x, y, z)
		return rx*x + ry*y + rz*z,
		       gx*x + gy*y + gz*z,
		       bx*x + by*y + bz*z
	end
	local rgb = space.rgb -- luacheck: ignore 431 (shadowing upvalue)

	-- The names here are the right way around:  transfer() is the
	-- model transfer function of the monitor, so to display the
	-- correct XYZ values we convert to linear RGB then apply the
	-- inverse itransfer() that the device will compensate for.

	-- The underscore in the nonlinear-colour functions is meant to
	-- suggest the prime used for nonlinear quantities in CIE
	-- publications.  It would be nice to have a more evocative naming
	-- convention.

	if data.gamma == nil then
		local mpfr = require 'lmpfrlib'
		mpfr.set_default_prec(96)
		data.gamma = 1 / mpfr.num(assert(data.igamma))
	elseif data.igamma == nil then
		local mpfr = require 'lmpfrlib'
		mpfr.set_default_prec(96)
		data.igamma = 1 / mpfr.num(assert(data.gamma))
	end

	local gamma, igamma = each(num, data.gamma, data.igamma)
	local slope, offset = each(num, data.slope, data.offset)

	if data.thresh == nil then
		local mpfr = require 'lmpfrlib'
		mpfr.set_default_prec(96)
		data.thresh = mpfr.num(data.slope) * mpfr.num(assert(data.ithresh))
	elseif data.ithresh == nil then
		local mpfr = require 'lmpfrlib'
		mpfr.set_default_prec(96)
		data.ithresh = mpfr.num(assert(data.thresh)) / mpfr.num(data.slope)
	end

	local thresh, ithresh = each(num, data.thresh, data.ithresh)

	-- The general form of a power-law curve that passes through (1,1)
	-- is  f(x) = ((x + offset) / (1 + offset))^gamma.

	function space.transfer(c)
		if abs(c) <= thresh then
			return c / slope
		elseif c > 0 then
			return ((c + offset) / (1 + offset))^gamma
		else
			return -((-c + offset) / (1 + offset))^gamma
		end
	end
	local transfer = space.transfer

	function space.xyz_(r, g, b)
		return xyz(transfer(r), transfer(g), transfer(b))
	end

	function space.itransfer(c)
		if abs(c) <= ithresh then
			return slope * c
		elseif c > 0 then
			return (1 + offset) * c^igamma - offset
		else
			return -((1 + offset) * (-c)^igamma - offset)
		end
	end
	local itransfer = space.itransfer

	function space.rgb_(x, y, z)
		local r, g, b = rgb(x, y, z)
		return itransfer(r), itransfer(g), itransfer(b)
	end

	if ... then return space end -- guess we were in a module

	local keys = {}
	for k in pairs(data) do keys[#keys+1] = k end
	table.sort(keys, function (a, b)
		-- Sort matrix entries together.
		if #a == 2 and #b ~= 2 then return true  end
		if #a ~= 2 and #b == 2 then return false end
		return a < b
	end)

	io.write("-- Generated by "..arg[0].." -- DO NOT MODIFY\nreturn {\n")
	for _, k in ipairs(keys) do
		local value = data[k]
		if type(value) ~= 'string' then value = dec(value) end
		io.write(string.format("\t%-7s = %q,\n", k, value))
	end
	io.write("}\n")
end

return rgb
