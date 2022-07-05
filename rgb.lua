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

local lg = require 'lg'

local clamp, lift, number3, round, sub = lg.clamp, lg.lift, lg.number3, lg.round, lg.sub
local abs = math.abs
local insert = table.insert

local unpack = unpack or table.unpack

-- This quantization is prescribed by the specifications for both HDTV and
-- sRGB.  Note that it yields half-width quantization intervals around
-- codes for black and white.

-- TODO scRGB can encode negative luminances

function rgb.quant(c, lo, hi)
	return (round(clamp(sub(hi, lo)*c + lo, lo, hi)))
end

function rgb.iquant(c, lo, hi)
	return (clamp(c, lo, hi) - lo) / sub(hi, lo)
end

local function each(func, ...)
	local results = {}
	for i = 1, select('#', ...) do
		results[i] = func( (select(i, ...)) )
	end
	return unpack(results)
end

local function tod(value)
	return type(value) == 'string' and tonumber(value) or value:get_d()
end

-- FIXME move det and solve to lg when it is mpfr-compatible

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
		local mpfr = require 'mpfr'
		mpfr.set_default_prec(96)

		local xr, yr, zr = each(mpfr.fr, unpack(data.r))
		local xg, yg, zg = each(mpfr.fr, unpack(data.g))
		local xb, yb, zb = each(mpfr.fr, unpack(data.b))
		local xw, yw, zw = each(mpfr.fr, unpack(data.w))

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

	local xyzr = number3(each(tod, data.xr, data.yr, data.zr))
	local xyzg = number3(each(tod, data.xg, data.yg, data.zg))
	local xyzb = number3(each(tod, data.xb, data.yb, data.zb))

	function space.xyz(...)
		local c = number3(...)
		return xyzr * c.r + xyzg * c.g + xyzb * c.b
	end
	local xyz = space.xyz

	if data.rx == nil then
		local mpfr = require 'mpfr'
		mpfr.set_default_prec(96)

		local xyz_rgb = {{each(mpfr.fr, data.xr, data.xg, data.xb)},
		                 {each(mpfr.fr, data.yr, data.yg, data.yb)},
		                 {each(mpfr.fr, data.zr, data.zg, data.zb)}}

		-- The transformation in the other direction is described
		-- by the inverse matrix.  (Duh.)

		data.rx, data.gx, data.bx = solve(xyz_rgb, {1, 0, 0})
		data.ry, data.gy, data.by = solve(xyz_rgb, {0, 1, 0})
		data.rz, data.gz, data.bz = solve(xyz_rgb, {0, 0, 1})
	end

	local rgbx = number3(each(tod, data.rx, data.gx, data.bx))
	local rgby = number3(each(tod, data.ry, data.gy, data.by))
	local rgbz = number3(each(tod, data.rz, data.gz, data.bz))

	function space.rgb(...)
		local c = number3(...)
		return rgbx * c.x + rgby * c.y + rgbz * c.z
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
		local mpfr = require 'mpfr'
		mpfr.set_default_prec(96)
		data.gamma = 1 / mpfr.fr(assert(data.igamma))
	elseif data.igamma == nil then
		local mpfr = require 'mpfr'
		mpfr.set_default_prec(96)
		data.igamma = 1 / mpfr.fr(assert(data.gamma))
	end

	local gamma, igamma = each(tod, data.gamma, data.igamma)
	local slope, offset = each(tod, data.slope, data.offset)

	if data.thresh == nil then
		local mpfr = require 'mpfr'
		mpfr.set_default_prec(96)
		data.thresh = mpfr.fr(data.slope) * mpfr.fr(assert(data.ithresh))
	elseif data.ithresh == nil then
		local mpfr = require 'mpfr'
		mpfr.set_default_prec(96)
		data.ithresh = mpfr.fr(assert(data.thresh)) / mpfr.fr(data.slope)
	end

	local thresh, ithresh = each(tod, data.thresh, data.ithresh)

	-- The general form of a power-law curve that passes through (1,1)
	-- is  f(x) = ((x + offset) / (1 + offset))^gamma.

	space.transfer = lift(function (c)
		if abs(c) <= thresh then
			return c / slope
		elseif c > 0 then
			return ((c + offset) / (1 + offset))^gamma
		else
			return -((-c + offset) / (1 + offset))^gamma
		end
	end)
	local transfer = space.transfer

	function space.xyz_(...)
		return (xyz(transfer(number3(...))))
	end

	space.itransfer = lift(function(c)
		if abs(c) <= ithresh then
			return slope * c
		elseif c > 0 then
			return (1 + offset) * c^igamma - offset
		else
			return -((1 + offset) * (-c)^igamma - offset)
		end
	end)
	local itransfer = space.itransfer

	function space.rgb_(...)
		return (itransfer(rgb(...)))
	end

	if ... then return space end -- guess we were in a module

	local keys = {}
	for k in pairs(data) do insert(keys, k) end
	table.sort(keys, function (a, b)
		-- Sort matrix entries together.
		if #a == 2 and #b ~= 2 then return true  end
		if #a ~= 2 and #b == 2 then return false end
		return a < b
	end)

	io.write("-- Generated by "..arg[0].." -- DO NOT MODIFY\nreturn {\n")
	for _, k in ipairs(keys) do
		local value = data[k]
		if type(value) ~= 'string' then

			-- There are at least two decimal fractions with
			-- 17 digits between each pair of double-precision
			-- numbers (binary fractions with 53 digits), but
			-- when there are three the middle decimal one can
			-- be very close to or even exactly between the
			-- binary ones, so given a string of 17 decimal
			-- digits more digits can be needed to get the
			-- last binary digit right after rounding.

			-- (We could instead first round to 53 binary
			-- digits and then to 17 decimal digits, but then
			-- not all the decimal digits would be correct as
			-- printed even though the actual double-precision
			-- numbers after reading would be the same.  This
			-- would work but is a bit distasteful.)

			local mpfr = require 'mpfr'
			local x = mpfr.fr(value); x:prec_round(53)
			for p = 16, 1000 do -- usually <= 18
				local s = value:format(' .*e', p)
				local y = mpfr.fr(s); y:prec_round(53)
				if x == y then value = s; break end
			end
		end
		io.write(string.format("\t%-7s = %q,\n", k, value))
	end
	io.write("}\n")
end

return rgb
