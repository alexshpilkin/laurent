-- Oh boy.

-- The official definition of sRGB is IEC 61966-2-1:1999 (sRGB).  The
-- guesswork needed to interpret that dumpster fire of a spec can be
-- somewhat simplified, at the cost of general sanity, by referring to
-- IEC 61966-2-1:1999/AMD1:2003 (bg-sRGB) defining applications to codes
-- with more than 8 bits and to IEC 61966-2-2:2003 (scRGB) defining two
-- ways of working with HDR data (linearly and nonlinearly).  The original
-- intention was for sRGB to be a simple modification of the BT.709 (HDTV)
-- colour space, so see the discussion and references in bt709.lua as well.

-- The original intention might have been that, but prodigious if well
-- motivated overspecification, incorrect readings by authors of later
-- extensions, and a widely implemented mistake in the original W3C draft
-- mean that sRGB is something of a monster.  Long story short, it is not
-- an RGB space in the conventional sense, defined by a set of primaries,
-- a white point, and a transfer function, but a coding system defined by
-- a matrix the ancestry of which one should not examine too closely and
-- a transfer function that requires creative reinterpretation to make any
-- sense at all.  It is best treated, in other words, as scripture.

-- The resulting confusion among the (very few) people who actually care
-- about this stuff can be seen in blog posts of Clinton Ingram[1,2], the
-- ensuing forum discussion[3] between him, Elle Stone (of Nine Degrees
-- Below Photography), and Graeme Gill (of ArgyllCMS fame), as well as a
-- blog post[4] by Jason Summers (of ImageWorsener fame) and a discussion
-- on the W3C accessibility guidelines bug tracker[5].

-- [1]: https://photosauce.net/blog/post/making-a-minimal-srgb-icc-profile-part-3-choose-your-colors-carefully
-- [2]: https://photosauce.net/blog/post/what-makes-srgb-a-special-color-space
-- [3]: https://discuss.pixls.us/t/feature-request-save-as-floating-point/5696/175
-- [4]: https://entropymine.com/imageworsener/srgbformula/
-- [5]: https://github.com/w3c/wcag/issues/360

local basic = {
	-- sRGB table 1, referencing HDTV sec. 1
	-- r = {'0.640',  '0.330',  '0.030'},
	-- g = {'0.300',  '0.600',  '0.100'},
	-- b = {'0.150',  '0.060',  '0.790'},
	-- w = {'0.3127', '0.3290', '0.3583'},

	-- sRGB eq. 7, bg-sRGB eqs. F.8, G.6, scRGB eq. 4
	xr = '0.4124', yr = '0.2126', zr = '0.0193',
	xg = '0.3576', yg = '0.7152', zg = '0.1192',
	xb = '0.1805', yb = '0.0722', zb = '0.9505',

	-- We arrive at the conclusion that it is this matrix that should
	-- be treated as the definition of linear sRGB, and not the HDTV
	-- primaries and the D65 white point that the spec also quotes,
	-- from the fact that bg-sRGB and scRGB also quote exactly these
	-- values rounded to precisely this amount of digits when they
	-- discuss using sRGB with more precision than afforded by 8-bit
	-- component values (for which there is no difference), but give
	-- extra digits of precision in the inverse matrix below as though
	-- they treated the forward matrix as exact.

	-- Because the elements of the forward matrix span almost two
	-- orders of magnitude, the extra digits of the inverse matrix
	-- would end up completely different if one inverted the forward
	-- one as obtained from the HDTV primaries and then rounded the
	-- result.  In fact, close perusal of the original 1999 spec with
	-- its four digits reveals that even the inverse matrix it gives
	-- is not the rounded inverse of the exact HDTV one but the
	-- rounded inverse of the rounded HDTV one.  (That last difference
	-- is confined in all cases to one or two units in the last place.)

	-- However, to say that the forward matrix is the rounded HDTV one
	-- is also not exactly correct:  it actually appears to be derived
	-- using the rounded chromaticity values for D65 given in the HDTV
	-- spec, so the last digit of one of the elements ends up wrong.

	-- sRGB eq. 8, bg-sRGB eq. G.7'
	-- rx =  3.2406255, gx = -0.9689307, bx =  0.0557101,
	-- ry = -1.5372080, gy =  1.8757561, by = -0.2040211,
	-- rz = -0.4986286, gz =  0.0415175, bz =  1.0569959,

	-- sRGB eqs. 5, 6, 9, 10, bg-sRGB eqs. F.4-6, F.9-11, G.3-5,
	-- G.8-10, scRGB eqs. B.1-3
	gamma = '2.4', offset = '0.055', slope = '12.92',
	-- thresh = 0.04045, ithresh = 0.0031308,

	-- Now we have gotten to the transfer function.  It is impressive
	-- just how cursed such a tiny thing can be.

	-- The origin story goes that the original intention was to make
	-- the linear and power-law pieces match in both value and slope
	-- at the threshold (like in the HDTV function), and choosing
	-- gamma and offset as the basic parameters allowed an analytic
	-- expression to be derived for the remaining two.  However, the
	-- widely implemented specification draft on the W3C website
	-- rounded the derived values for slope and threshold so much that
	-- the function ended up discontinous in practical usage.

	-- To patch that up and not break existing implementations too
	-- much, the final IEC standard fixed the slope at the value
	-- people actually implemented and allowed the derivative to be
	-- slightly discontinuous.  This moves the threshold by about 3%,
	-- from 0.03929 to 0.04042, but because the change happens at low
	-- absolute values it is just small enough to be undetectable in
	-- 8-bit LDR processing, where code 10 covers [0.03725, 0.04118)
	-- and code 11 covers [0.04118, 0.04510).  The possibility of an
	-- analytic expression for the threshold is then also lost.

	-- However, the story does not end here, because the specification
	-- also gives the threshold for the inverse transfer function, and
	-- it is wrong in the last decimal place because it seems to have
	-- been obtained from the rounded threshold, not the exact one.
	-- The bg-sRGB spec quotes the same two values, and scRGB goes one
	-- step further by only retaining the inverse one.

	-- However, after quantization, the differences turn out not to
	-- matter, even with 16-bit accuracy as targeted by bg-sRGB.

	-- In practice, almost nobody appears to be using the historical
	-- smooth thresholds.  It is unclear whether the continuous or the
	-- literalist thresholds are used more often in situations where
	-- the difference matters.
}

local ok, data = pcall(require, '_srgb') -- run this file to generate
if not ok then data = {} end
setmetatable(data, {__index = basic})

if data.thresh == nil then
	local mpfr = require 'mpfr'
	mpfr.set_default_prec(96)

	-- This code chooses to prefer continuity to strict compliance, so
	-- the threshold value is recomputed as the larger of the two
	-- intersection abscissae of the linear and power-law curves.  No
	-- analytic expression exists for it, and because the intersection
	-- is so close to degenerate fixed-point iteration takes more than
	-- two thousand iterations to converge, but I see no real
	-- alternative here.  It is completely straightforward, though.

	local gamma, offset = mpfr.fr(data.gamma), mpfr.fr(data.offset)
	local slope, igamma = mpfr.fr(data.slope), 1 / gamma

	local thresh, eps = 1, mpfr.fr(2)^-64
	while true do
		local t = (1 + offset) * (thresh / slope)^igamma - offset
		if ((t - thresh) / t):abs() < eps then break end
		thresh = t
	end
	data.thresh = thresh -- 0.04045

	-- Here is what the computation would be if we imposed continuity
	-- of the derivative instead of fixing the slope:

	-- local thresh = offset / (gamma - 1)
	-- local slope  = ((1 + offset) / gamma) ^ gamma
	--              * ((gamma - 1) / offset) ^ (gamma - 1)
	-- data.thresh, data.slope = thresh, slope -- 0.03929, 12.9232
end

return require 'rgb' (data, ...)
