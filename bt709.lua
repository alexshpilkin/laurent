-- This is the colour space defined in Rec. ITU-R BT.709 (HDTV); there are
-- more details on the definition of the transfer function in Rec. ITU-R
-- BT.2020 (UHDTV) and some general remarks in Rec. ITU-T H.273 (CICP).

-- The only tricky part is that the white point is both defined as standard
-- illuminant D65 and has its chromaticity specified.  I assume that the
-- former definition takes precedence and recompute the precise coordinates
-- from the spectra tabulated in ISO 11664-1:2007 (which defines D65) and
-- ISO 11664-2:2007 (which defines the CIE 1931 reference observer).

local insert = table.insert

local basic = {
	-- HDTV sec. 1, CICP table 2 row 1
	r = {'0.640', '0.330', '0.030'},
	g = {'0.300', '0.600', '0.100'},
	b = {'0.150', '0.060', '0.790'},

	-- HDTV sec. 1, CICP table 3 row 1 and others;  more precise values
	-- of the derived quantities are from UHDTV table 4
	igamma = '0.45', slope = '4.500',
	-- ithresh = 0.018053968510807, offset = 0.09929682680944,
}

local ok, data = pcall(require, '_bt709') -- run this file to generate
if not ok then data = {} end
setmetatable(data, {__index = basic})

if data.xr == nil then -- will need white point
	local mpfr = require 'lmpfrlib'
	mpfr.set_default_prec(96)

	local function rows(filename)
		local file, err = io.open(filename)
		if not file then return nil, err end

		local lines, head = file:lines(), {}
		for cell in string.gmatch(lines(), '[^\t\n]+') do
			insert(head, cell)
		end

		return function ()
			local line = lines()
			if not line then return nil end

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
	local xw, yw, zw = mpfr.num(0), mpfr.num(0), mpfr.num(0) -- 0.3127 C, 0.3290 C, 0.3583 C
	local d65, t = mpfr.num(), mpfr.num()
	while ob do
		assert(ill.nm == ob.nm)
		d65:set_str(ill.d65, 10)
		t:set_str(ob.xbar, 10) t:mul(t, d65) xw:add(xw, t)
		t:set_str(ob.ybar, 10) t:mul(t, d65) yw:add(yw, t)
		t:set_str(ob.zbar, 10) t:mul(t, d65) zw:add(zw, t)
		ob, ill = ob1931(), illstd()
	end

	-- Put the white point coordinates in basic so that the writer
	-- does not try to write them out to the data file.  The writer
	-- cannot deal with tables, and in any case the white point is not
	-- needed after the conversion matrix has been derived.

	-- HDTV sec. 1, CICP table 2 row 1, UHDTV table 3
	basic.w = {xw, yw, zw} -- 0.3127 : 0.3290 : 0.3583 (projective)

	-- Note that the oft-quoted value of 0.9505 : 1.0000 : 1.0891 for
	-- D65 is wrong:  the last digits are as though the rounded values
	-- given above are exact, which they are not.  The code above
	-- yields 0.9505 : 1.0000 : 1.0888, and that is enough to change
	-- the fourth decimal place in the transformation matrix.
end

if data.thresh == nil then
	local mpfr = require 'lmpfrlib'
	mpfr.set_default_prec(96) -- overkill

	-- Per UHDTV, the 1/gamma and slope values are fixed and the rest
	-- are set such that the linear and power-law curves match at the
	-- threshold in both value and slope.  There is no analytic
	-- expression for these values, but a simple fixed-point iteration
	-- suffices and converges in a couple dozen iterations.

	local igamma, slope = mpfr.num(data.igamma), mpfr.num(data.slope)
	local expt = 1 / (1 - igamma)

	local ithresh, eps = 1, mpfr.num(2)^-64
	while true do
		local t = ((1 - igamma) * ithresh + igamma / slope)^expt
		if ((t - ithresh) / t):abs() <= eps then break end
		ithresh = t
	end
	data.ithresh, data.offset = ithresh, (1 / igamma - 1) * ithresh * slope
end

return require 'rgb' (data, ...)
