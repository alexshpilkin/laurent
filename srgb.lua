local srgb = {}

local ok, _srgb = pcall(require, '_srgb') -- run this file to regenerate
if not ok then

	-- The impressive stash of yak shavings here is concerned with
	-- rederiving the transformations to and from the sRGB space from
	-- their defining properties and parameters.

	-- Nominally, sRGB is specified in IEC 61966-2-1:1999 by using the
	-- primaries in the HDTV standard BT.709 together with a custom
	-- transfer function.  However, the numbers provided in that
	-- specification mesh together with enough precision only when
	-- dealing with 8-bit codes, and the extension to more bits in
	-- IEC 61966-2-1:1999/AMD1:2003 is surprising and extremely vague
	-- as to which of these numbers are basic and which are derived.

	-- The resulting confusion among the (very few) people who
	-- actually care about this stuff can be seen in blog posts of
	-- Clinton Ingram[1,2], the ensuing forum discussion[3] between
	-- him, Elle Stone (of Nine Degrees Below Photography), and Graeme
	-- Gill (of ArgyllCMS fame), as well as a blog post[4] by Jason
	-- Summers (of ImageWorsener fame) and a discussion in the W3C
	-- accessibility guidelines bug tracker[5].

	-- [1]: https://photosauce.net/blog/post/making-a-minimal-srgb-icc-profile-part-3-choose-your-colors-carefully
	-- [2]: https://photosauce.net/blog/post/what-makes-srgb-a-special-color-space
	-- [3]: https://discuss.pixls.us/t/feature-request-save-as-floating-point/5696/175
	-- [4]: https://entropymine.com/imageworsener/srgbformula/
	-- [5]: https://github.com/w3c/wcag/issues/360

	-- The short description of the approach taken here (as well as by
	-- Stone and Gill for the most part, but not others) is that the
	-- white point chromaticity is rederived from tabulated spectra,
	-- the colour transformations are rederived from the result and
	-- the chromaticities of the primaries, and (this is the largest
	-- change, but still invisible when roundtripping 8-bit inputs)
	-- the parameters for the linear portion of the transfer function
	-- are rederived from the smoothness restriction.  The long one,
	-- as well as an explanation of what all that means, is below.

	local unpack = unpack
	if unpack == nil then unpack = table.unpack end  -- Lua 5.2+

	_srgb = {}

	-- <http://www.circuitwizard.de/lmpfrlib/lmpfrlib.html>
	local mpfr = require 'lmpfrlib'
	mpfr.set_default_prec(96) -- overkill
	local mpf = mpfr.num

	-- The smallest number of significant digits such that any IEEE
	-- double-precision number roundtrips through a decimal
	-- representation is 17.  (This is not to be confused with the
	-- largest number of significant digits in a decimal
	-- representation such that any such representation roundtrips
	-- through an IEEE double-precision number, which is 15.)

	-- That is, 17 decimal digits losslessly represent any double
	-- (while a double losslesly represents any 15 digits, but we do
	-- not need that here).

	local function dec(x) return (mpfr.sprintf('% .16Re', x)) end

	-- WHITE POINT CHROMINANCE

	-- BT.709 specifies the white point to be illuminant D65 and gives
	-- its chrominance in x + y + z = 1 normalization to four places.
	-- IEEE 61966-1-2:1999 and the higher-precision AMD1:2003 seem to
	-- have uncritically assumed these numbers to be exact in order to
	-- obtain four (and a bit) decimal places of chrominance in the
	-- Y = 1 normalization needed to compute transformation matrices.

	-- Here I recompute the double-precision chrominance from the
	-- spectral density for the D65 illuminant in ISO 11664-1:2007
	-- (which defines what D65 is) and the colour matching functions
	-- of the 1931 observer in ISO 11664-2:2007 (which define what
	-- chrominance is).

	local function done() end
	local function rows(filename)
		local file, err = io.open(filename)
		if not file then return nil, err end

		local lines, head = file:lines(), {}
		for cell in string.gmatch(lines(), '[^\t\n]+') do
			head[#head+1] = cell
		end

		return function ()
			local line = lines()
			if not line then lines = done; return nil end

			local i, row = 1, {}
			for cell in string.gmatch(line, '[^\t\n]+') do
				row[head[i]] = cell; i = i + 1
			end
			return row
		end
	end

	local ob1931 = assert(rows('ob1931.tsv'))
	local illstd = assert(rows('illstd.tsv'))

	local ob = ob1931()
	local ill; repeat ill = illstd() until ill.nm == ob.nm
	local xw, yw, zw = mpf(0), mpf(0), mpf(0) -- 0.3127 C, 0.3290 C, 0.3583 C
	local d65, t = mpf(), mpf()
	while ob do
		assert(ill.nm == ob.nm)
		d65:set_str(ill.d65, 10)
		t:set_str(ob.xbar, 10) t:mul(t, d65) xw:add(xw, t)
		t:set_str(ob.ybar, 10) t:mul(t, d65) yw:add(yw, t)
		t:set_str(ob.zbar, 10) t:mul(t, d65) zw:add(zw, t)
		ob, ill = ob1931(), illstd()
	end

	-- TRANSFORMATION MATRICES

	-- Several elements of the forward matrix recomputed here differ
	-- in the last decimal place from IEC 61966-2-1:1999, but all will
	-- match if the rounded white point is used.

	-- BT.709 sec. 1 as referenced by IEC 61966-2-1:1999 table 1
	local xr, yr, zr = mpf('0.640'), mpf('0.330'), mpf('0.030')
	local xg, yg, zg = mpf('0.300'), mpf('0.600'), mpf('0.100')
	local xb, yb, zb = mpf('0.150'), mpf('0.060'), mpf('0.790')

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
		-- matrices.  It is easier to switch out rows than columns
		-- in row-major matrices, and the determinant does not
		-- change after transposing.

		local mt = {{m[1][1], m[2][1], m[3][1]},
		            {m[1][2], m[2][2], m[3][2]},
		            {m[1][3], m[2][3], m[3][3]}}
		local d = det(m)
		return {det{v, mt[2], mt[3]} / d,
		        det{mt[1], v, mt[3]} / d,
		        det{mt[1], mt[2], v} / d}
	end

	-- The coordinates (chrominances) of the primaries above are
	-- projective, that is, up to an overall scaling for each primary
	-- independently.  These scalings are fixed by requiring that the
	-- RGB value of (1, 1, 1) correspond to the provided white point
	-- normalized such that luminance Y = 1.

	-- In general, to define a frame in an n-dimensional projective
	-- space (of rays in a vector space of dimension n+1, or in our
	-- case of colours) one needs n+2 points in general position, and
	-- their representing vectors can always be chosen such that n+1
	-- of them make a basis and the remaining one is the sum of these.

	xw:div(xw, yw) zw:div(zw, yw) yw:set_si(1) -- 0.9505, 1.0000, 1.0891 (see above)

	-- / xw \   / scale[1]*xr scale[2]*xg scale[3]*xb \ / 1 \
	-- | yw | = | scale[1]*yr scale[2]*yg scale[3]*yb | | 1 |
	-- \ zw /   \ scale[1]*zr scale[2]*zg scale[3]*zb / \ 1 /

	-- / xw \   / xr xg xb \ / scale[1] \
	-- | yw | = | yr yg yb | | scale[2] |
	-- \ zw /   \ zr zg zb / \ scale[3] /

	local scale = solve({{xr, xg, xb}, {yr, yg, yb}, {zr, zg, zb}},
	                    {xw, yw, zw})

	xr, yr, zr = scale[1] * xr, scale[1] * yr, scale[1] * zr
	xg, yg, zg = scale[2] * xg, scale[2] * yg, scale[2] * zg
	xb, yb, zb = scale[3] * xb, scale[3] * yb, scale[3] * zb

	-- IEC 61966-2-1:1999 eq. 7
	_srgb.xr, _srgb.yr, _srgb.zr = dec(xr), dec(yr), dec(zr) -- 0.4124, 0.2126, 0.0193
	_srgb.xg, _srgb.yg, _srgb.zg = dec(xg), dec(yg), dec(zg) -- 0.3576, 0.7152, 0.1192
	_srgb.xb, _srgb.yb, _srgb.zb = dec(xb), dec(yb), dec(zb) -- 0.1805, 0.0722, 0.9505

	-- The transformation in the other direction is described by the
	-- inverse matrix, duh.  Still the IEC amendment manages to screw
	-- it up:  it attempts to give the inverse with a higher precision
	-- while using the imprecise four-place values for the forward one.

	-- Because the forward matrix has elements differing by almost two
	-- orders of magnitude, this gives rather dramatic differences in
	-- the small elements of the inverse when a more precise forward
	-- matrix (such as the one we computed above) is used;  the digits
	-- after the fourth one, which is the point of the amendment's
	-- inverse, are completely meaningless.

	local xyz_rgb = {{xr, xg, xb}, {yr, yg, yb}, {zr, zg, zb}}

	local rx, gx, bx = unpack(solve(xyz_rgb, {1, 0, 0}))
	local ry, gy, by = unpack(solve(xyz_rgb, {0, 1, 0}))
	local rz, gz, bz = unpack(solve(xyz_rgb, {0, 0, 1}))

	-- IEC 61966-2-1:1999 eq. 8, IEC 61966-2-1:1999/AMD1:2003 eq. G.7' (see above)
	_srgb.rx, _srgb.gx, _srgb.bx = dec(rx), dec(gx), dec(bx) --  3.2406255, 0.9689307,  0.0557101
	_srgb.ry, _srgb.gy, _srgb.by = dec(ry), dec(gy), dec(by) -- -1.5372080, 1.8757561, -0.2040211
	_srgb.rz, _srgb.gz, _srgb.bz = dec(rz), dec(gz), dec(bz) -- -0.4986286, 0.0415175,  1.0569959

	-- TRANSFER FUNCTION PARAMETERS

	-- For a function assembled out of a linear and a quadratic piece
	-- such as that used in sRGB, we can choose any four of the six
	-- conditions: (1) matching derivative, (2) continuity, (3) fixed
	-- gamma, (4) fixed shift, (5) fixed slope, (6) fixed threshold.

	-- The original definition of sRGB chose conditions (1)-(4) but
	-- gave the computed values for (5) and (6) with too much rounding.
	-- The final standard appears to have abandoned (1) for (5), but
	-- in fact specifies all the constants, so (3)-(6), making the
	-- specified function broken for any precision greater than the
	-- one in the text (four decimal digits).

	-- I could leave the slope (5) fixed and recompute only the
	-- threshold (6), ending up with a broken derivative (1) but
	-- matching the standard more closely.  This is the usual solution
	-- but it is kind of sad.  In the interest of general sanity I
	-- chose instead to recompute the threshold as well, which leaves
	-- it around 0.03929 instead of 0.04042.  This is a change of 3%,
	-- but because it happens at very low absolute values it is just
	-- small enough to be undetectable in 8-bit LDR processing, where
	-- code 10 covers the interval [0.03725, 0.04118) and code 11
	-- covers [0.04118, 0.04510).

	-- IEC 61966-2-1:1999 eq. 6
	local gamma, shift = mpf('2.4'), mpf('0.055')
	_srgb.gamma, _srgb.shift = dec(gamma), dec(shift)

	-- To derive these, set f(x) = ((x + shift) / (1 + shift))^gamma,
	-- the general power-law curve that passes through (1,1), and
	-- solve for thresh and slope in { f(thresh) = thresh / slope,
	-- f'(thresh) = 1 / slope }.

	local thresh = shift / (gamma - 1)
	local slope  = ((1 + shift) / gamma) ^ gamma
	             * ((gamma - 1) / shift) ^ (gamma - 1)

	_srgb.thresh  = dec(thresh)         -- 0.04045 (see above)
	_srgb.slope   = dec(slope)          -- 12.92
	_srgb.igamma  = dec(1 / gamma)      -- 1 / 2.4
	_srgb.ithresh = dec(thresh / slope) -- 0.0031308
end

-- The "c" in the linear-colour functions is meant to suggest the linear
-- space scRGB, wherein the "c" does not actually stand for anything.  It
-- would be nice to have a more evocative naming convention.

local xr, yr, zr = tonumber(_srgb.xr), tonumber(_srgb.yr), tonumber(_srgb.zr)
local xg, yg, zg = tonumber(_srgb.xg), tonumber(_srgb.yg), tonumber(_srgb.zg)
local xb, yb, zb = tonumber(_srgb.xb), tonumber(_srgb.yb), tonumber(_srgb.zb)

function srgb.xyzc(r, g, b)
	return xr*r + xg*g + xb*b, yr*r + yg*g + yb*b, zr*r + zg*g + zb*b
end
local xyzc = srgb.xyzc

local rx, ry, rz = tonumber(_srgb.rx), tonumber(_srgb.ry), tonumber(_srgb.rz)
local gx, gy, gz = tonumber(_srgb.gx), tonumber(_srgb.gy), tonumber(_srgb.gz)
local bx, by, bz = tonumber(_srgb.bx), tonumber(_srgb.by), tonumber(_srgb.bz)

function srgb.crgb(x, y, z)
	return rx*x + ry*y + rz*z, gx*x + gy*y + gz*z, bx*x + by*y + bz*z
end
local crgb = srgb.crgb

-- The names here are the right way around:  transfer() is the model
-- transfer function of the monitor, so to display the correct XYZ values
-- we convert to linear RGB then apply the inverse itransfer() that the
-- device will compensate for.

local gamma, shift = tonumber(_srgb.gamma), tonumber(_srgb.shift)
local thresh, slope = tonumber(_srgb.thresh), tonumber(_srgb.slope)

function srgb.transfer(c)
	if -thresh <= c and c <= thresh then
		return c / slope
	elseif c > 0 then
		return ((c + shift) / (1 + shift))^gamma
	else
		return -((-c + shift) / (1 + shift))^gamma
	end
end
local transfer = srgb.transfer

function srgb.xyz(r, g, b)
	return xyzc(transfer(r), transfer(g), transfer(b))
end

local igamma, ithresh = tonumber(_srgb.igamma), tonumber(_srgb.ithresh)

function srgb.itransfer(c)
	if -ithresh <= c and c <= ithresh then
		return slope * c
	elseif c > 0 then
		return (1 + shift) * c^igamma - shift
	else
		return -((1 + shift) * (-c)^igamma - shift)
	end
end
local itransfer = srgb.itransfer

function srgb.rgb(x, y, z)
	local r, g, b = crgb(x, y, z)
	return itransfer(r), itransfer(g), itransfer(b)
end

local min, max = math.min, math.max

local topbit = 1.0
while true do
	local t = topbit * 2
	if t + 1 == t then break end
	topbit = t
end
local function round(x)
	if x <= -topbit or x >= topbit then return x end
	if x > 0 then
		return x + topbit - topbit
	else
		return x - topbit + topbit
	end
end

function srgb.quant(c, lo, hi)
	-- IEC 61966-2-1:1999 eq. 11; note this yields half-width
	-- quantization intervals around codes for black and white
	return max(lo, min(hi, round((hi - lo)*c + lo)))
end

function srgb.iquant(c, lo, hi)
	-- IEC 61966-2-1:1999 eq. 2; see note above
	return (max(lo, min(hi, c)) - lo) / (hi - lo)
end

if select('#', ...) == 1 and package.loaded[...] then return srgb end

local keys = {}
for k in pairs(_srgb) do keys[#keys+1] = k end
table.sort(keys, function (a, b)
	if #a == 2 and #b ~= 2 then return true  end
	if #a ~= 2 and #b == 2 then return false end
	return a < b
end)

io.write("-- Generated by "..arg[0].." -- DO NOT MODIFY\nreturn {\n")
for _, k in ipairs(keys) do
	io.write(string.format("\t%-7s = %q,\n", k, _srgb[k]))
end
io.write("}\n")
