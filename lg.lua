local lg = {}

-- Almost entirely compatible with Cg[1] and its doppelgaenger HLSL[2],
-- quite a bit so with GLSL[3].

-- [1]: https://developer.download.nvidia.com/cg/index.html
-- [2]: https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl
-- [3]: https://github.com/KhronosGroup/OpenGL-Refpages

local assert, select, tonumber, type = assert, select, tonumber, type
local find, gsub, substr = string.find, string.gsub, string.sub
local concat, insert = table.concat, table.insert

local loadstring = loadstring or load
local tointeger = math.tointeger or function (x) return x end

local function nope() end
local function id(...) return ... end
local function nid(...) return select('#', ...), ... end

local function setdefault(table, default)
	return setmetatable(table, {__index = function (self, key)
		local value = default(key)
		if value ~= nil then self[key] = value end
		return value
	end})
end

-- constructors

-- yields more meaningful type errors down the line
local function num(n) return tonumber(n) or n end

local function shift(v, n, ...)
	if n == nil then return nil end -- propagate failure
	if type(v) == 'nil' then return n, ... end -- appease LuaJIT

	local x = tonumber(v); if x then return n + 1, x, ... end

	-- there are no one-dimensional vectors

	x = v._4; if x ~= nil then return n + 4, num(v._1), num(v._2), num(v._3), num(x), ... end
	x = v._3; if x ~= nil then return n + 3, num(v._1), num(v._2), num(x), ... end
	x = v._2; if x ~= nil then return n + 2, num(v._1), num(x), ... end

	x = v.w; if x ~= nil then return n + 4, num(v.x), num(v.y), num(v.z), num(x), ... end
	x = v.z; if x ~= nil then return n + 3, num(v.x), num(v.y), num(x), ... end
	x = v.y; if x ~= nil then return n + 2, num(v.x), num(x), ... end

	x = v.a; if x ~= nil then return n + 4, num(v.r), num(v.g), num(v.b), num(x), ... end
	x = v.b; if x ~= nil then return n + 3, num(v.r), num(v.g), num(x), ... end
	x = v.g; if x ~= nil then return n + 2, num(v.r), num(x), ... end

	x = v.q; if x ~= nil then return n + 4, num(v.s), num(v.t), num(v.p), num(x), ... end
	x = v.p; if x ~= nil then return n + 3, num(v.s), num(v.t), num(x), ... end
	x = v.t; if x ~= nil then return n + 2, num(v.s), num(x), ... end

	return nil
end

local _number2, _number3, _number4

function lg.number2(_1, _2)
	local n; n, _1, _2 = shift(_1, shift(_2, 0))
	if n == 1 then n, _2 = 2, _1 end
	assert(n == 2, "wrong component count")
	return (_number2(_1, _2))
end

function lg.number3(_1, _2, _3)
	local n; n, _1, _2, _3 = shift(_1, shift(_2, shift(_3, 0)))
	if n == 1 then n, _2, _3 = 3, _1, _1 end
	assert(n == 3, "wrong component count")
	return (_number3(_1, _2, _3))
end

function lg.number4(_1, _2, _3, _4)
	local n; n, _1, _2, _3, _4 = shift(_1, shift(_2, shift(_3, shift(_4, 0))))
	if n == 1 then n, _2, _3, _4 = 4, _1, _1, _1 end
	assert(n == 4, "wrong component count")
	return (_number4(_1, _2, _3, _4))
end

function lg.tonumbers(v)
	local n, _1, _2, _3, _4 = shift(v, 0)
	assert(n, "numbers expected")
	if n == 1 then return _1 end
	if n == 2 then return (_number2(_1, _2)) end
	if n == 3 then return (_number3(_1, _2, _3)) end
	return (_number4(_1, _2, _3, _4))
end
local tonumbers = lg.tonumbers

-- lifting

local function conform(u, v)
	local un, u1, u2, u3, u4 = shift(u, 0)
	local vn, v1, v2, v3, v4 = shift(v, 0)
	if un == 1 then un, u2, u3, u4 = vn, u1, u1, u1 end
	if vn == 1 then vn, v2, v3, v4 = un, v1, v1, v1 end
	assert(un and vn, "numbers expected")
	assert(un > 0 and (vn == 0 or vn == un), "component counts do not match")
	return un, u1, v1, u2, v2, u3, v3, u4, v4
end

-- lifted functions should only be used at a fixed number of arities, so
-- avoid max(unpack( ... )) and similar

function lg.lift(f)
	local lifts = setdefault({}, function (k)
		local args, arg1s, arg2s, arg3s, arg4s = {}, {}, {}, {}, {}
		local shifts = {}

		for i = 1, k do
			args[i] = 'a'..i..'v'
			arg1s[i], arg2s[i] = 'a'..i..'1', 'a'..i..'2'
			arg3s[i], arg4s[i] = 'a'..i..'3', 'a'..i..'4'
			shifts[i] = gsub([[
				local @n, @1, @2, @3, @4 = shift(@v, 0)
				assert(@n, "numbers expected")
				if @n == 1 then @n, @2, @3, @4 = n, @1, @1, @1 end
				if @n >= 1 and n == 1 then n = @n end
				assert(n == @n, "component counts do not match")
			]], '@', 'a'..i)
		end

		return loadstring([[
			local f, assert, nid, shift, _number2, _number3, _number4 = ...
			return function (]]..concat(args, ', ')..[[)
				local n = 1
				]]..concat(shifts, '\n')..[[
				local r, u1, v1 = nid(f(]]..concat(arg1s, ', ')..[[))
				if n == 1 then
					if r == 0 then return end
					if r == 1 then return u1 end
					return u1, v1
				end
				local r2, u2, v2 = nid(f(]]..concat(arg2s, ', ')..[[))
				assert(r == r2)
				if n == 2 then
					if r == 0 then return end
					local u = _number2(u1, u2)
					if r == 1 then return u end
					return u, _number2(v1, v2)
				end
				local r3, u3, v3 = nid(f(]]..concat(arg3s, ', ')..[[))
				assert(r == r3)
				if n == 3 then
					if r == 0 then return end
					local u = _number3(u1, u2, u3)
					if r == 1 then return u end
					return u, _number3(v1, v2, v3)
				end
				local r4, u4, v4 = nid(f(]]..concat(arg4s, ', ')..[[))
				assert(r == r4)
				if r == 0 then return end
				local u = _number4(u1, u2, u3, u4)
				if r == 1 then return u end
				return u, _number4(v1, v2, v3, v4)
			end
		]])(f, assert, nid, shift, _number2, _number3, _number4)
	end)
	return function (...)
		local r, u, v = nid(lifts[select('#', ...)](...))
		if r == 0 then return end
		if r == 1 then return u end
		return u, v
	end
end
local lift = lg.lift

-- operators

local function tostring(v)
	local n, _1, _2, _3, _4 = shift(v, 0)
	return 'number' .. n .. '(' .. concat({_1, _2, _3, _4}, ', ') .. ')'
end

lg.add = lift(function (x, y) return x + y end)
lg.sub = lift(function (x, y) return x - y end)
lg.mul = lift(function (x, y) return x * y end) -- Cg also has matrix mul()
lg.div = lift(function (x, y) return x / y end)
lg.mod = lift(function (x, y) return x % y end)
lg.pow = lift(function (x, y) return x ^ y end)
local sub, mul, div = lg.sub, lg.mul, lg.div

local unm = {
	nil,
	function (v) return (_number2(-v._1, -v._2)) end,
	function (v) return (_number3(-v._1, -v._2, -v._3)) end,
	function (v) return (_number4(-v._1, -v._2, -v._3, -v._4)) end,
}

local eq = {
	nil,
	function (u, v) return u._1 == v._1 and u._2 == v._2 end,
	function (u, v) return u._1 == v._1 and u._2 == v._2 and u._3 == v._3 end,
	function (u, v) return u._1 == v._1 and u._2 == v._2 and u._3 == v._3 and u._4 == v._4 end,
}

-- swizzling

local function values(key, set)
	local step, list, seen, uniq = 1, {}, {}, true
	if type(set) == 'number' then
		set, step = substr('_1_2_3_4', 1, 2 * set), 2
	end
	for i = 1, #key, step do
		local k = find(set, substr(key, i, i + step - 1), 1, true)
		if not k or (k - 1) % step ~= 0 then return nil end
		uniq = uniq and not seen[k]; seen[k] = true
		insert(list, 'self._' .. tointeger((k - 1) / step + 1))
	end
	return concat(list, ", "), #list, uniq
end

local function makeindex(key, set)
	local args, m = values(key, set)
	if not args or 1 > m or m > 4 then return nil end
	return loadstring([[
		local _number1, _number2, _number3, _number4 = ...
		return function (self)
			return (_number]]..m..[[(]]..args..[[))
		end
	]])(id, _number2, _number3, _number4)
end

local function makenewindex(key, set)
	local args, m, uniq = values(key, set)
	if not args or 1 > m or m > 4 or not uniq then return nil end
	return loadstring([[
		local shift = ...
		return function (self, value)
			local n, _1, _2, _3, _4 = shift(value, 0)
			assert(n == ]]..m..[[); ]]..args..[[ = _1, _2, _3, _4
		end
	]])(shift)
end

-- raw constructors

local function makemetatable(n)
	local xyzw = substr('xyzw', 1, n)
	local rgba = substr('rgba', 1, n)
	local stpq = substr('stpq', 1, n)

	local indices = setdefault({_1 = id}, function (key)
		return makeindex(key, n)    or makeindex(key, xyzw) or
		       makeindex(key, rgba) or makeindex(key, stpq)
	end)

	local newindices = setdefault({}, function (key)
		return makenewindex(key, n)    or makenewindex(key, xyzw) or
		       makenewindex(key, rgba) or makenewindex(key, stpq)
	end)

	-- avoid slow path when shift() sniffs dimension
	indices._2, indices._3, indices._4 = nope, nope, nope
	if n < 4 then indices.w, indices.a, indices.q = nope, nope, nope end
	if n < 3 then indices.z, indices.b, indices.p = nope, nope, nope end
	if n < 2 then indices.y, indices.g, indices.t = nope, nope, nope end

	return {
		__name = 'number' .. n,
		__tostring = tostring,
		__index = function (self, key)
			local index = indices[key]
			if index then return (index(self)) end
		end,
		__newindex = function (self, key, value)
			assert(newindices[key])(self, value)
		end,
		__add = lg.add, __sub = lg.sub, __mul = lg.mul,
		__div = lg.div, __mod = lg.mod, __pow = lg.pow,
		__unm = unm[n], __eq = eq[n], -- Cg uses masks
	}
end

if not (debug.getmetatable(0) and rawget(debug.getmetatable(0), '__index')) then
	debug.setmetatable(0, {__index = makemetatable(1).__index})
end
local meta2, meta3, meta4 = makemetatable(2), makemetatable(3), makemetatable(4)

if jit then
	local ffi = require 'ffi'
	_number2 = ffi.metatype('struct { double _1, _2; }', meta2)
	_number3 = ffi.metatype('struct { double _1, _2, _3; }', meta3)
	_number4 = ffi.metatype('struct { double _1, _2, _3, _4; }', meta4)
else
	function _number2(_1, _2)
		return (setmetatable({_1 = _1, _2 = _2}, meta2))
	end
	function _number3(_1, _2, _3)
		return (setmetatable({_1 = _1, _2 = _2, _3 = _3}, meta3))
	end
	function _number4(_1, _2, _3, _4)
		return (setmetatable({_1 = _1, _2 = _2, _3 = _3, _4 = _4}, meta4))
	end
end

-- functions

-- abs, frexp, ldexp

-- Cg also has sign(), C99 has copysign()
lg.abs = lift(math.abs)
lg.frexp = math.frexp and lift(math.frexp)
lg.ldexp = math.ldexp and lift(math.ldexp)

-- floor, ceil, frac, modf

local _floor = math.floor

-- Cg also has round() and trunc()
lg.floor, lg.ceil = lift(_floor), lift(math.ceil)

lg.frac = lift(function (x)
	x = tonumber(x); local i = x - _floor(x)
	return x ~= i and i or 0 -- inf and -inf to zero, nan to nan
end)

lg.modf = lift(math.modf)

-- max, min, clamp, saturate

lg.max, lg.min = lift(math.max), lift(math.min)
local max, min = lg.max, lg.min

-- on x86, max(0, -0) is -0 but max(-0, 0) is 0
function lg.clamp(u, v, w) return (min(max(u, v), w)) end
local clamp = lg.clamp

function lg.saturate(v) return (clamp(v, 0, 1)) end
local saturate = lg.saturate

-- lerp, step, smoothstep

function lg.lerp(u, v, t) return mul(sub(1, t), u) + mul(t, v) end

lg.step = lift(function (e, x) return e <= x and 1 or 0 end)

function lg.smoothstep(u, v, w)
	local x = saturate(sub(w, u) / sub(v, u))
	return x * x * (3 - 2 * x)
end

-- deg, rad

-- Cg calls these degrees() and radians()
lg.deg, lg.rad = lift(math.deg), lift(math.rad)

-- fmod, sqrt, exp, log

local _sqrt = math.sqrt

-- Cg also has rsqrt()
lg.fmod, lg.sqrt = lift(math.fmod), lift(_sqrt)
lg.exp, lg.log = lift(math.exp), lift(math.log)

-- sin, cos, tan, sinh, cosh, tanh

lg.sin, lg.cos, lg.tan = lift(math.sin), lift(math.cos), lift(math.tan)

lg.sinh = math.sinh and lift(math.sinh)
lg.cosh = math.cosh and lift(math.cosh)
lg.tanh = math.tanh and lift(math.tanh)

-- asin, acos, atan, atan2

lg.asin, lg.acos  = lift(math.asin), lift(math.acos)
lg.atan, lg.atan2 = lift(math.atan), lift(math.atan2)

-- dot, cross, length, distance, normalize

function lg.dot(u, v)
	local n, u1, v1, u2, v2, u3, v3, u4, v4 = conform(u, v)
	local x = u1 * v1; if n == 1 then return x end
	x =   x + u2 * v2; if n == 2 then return x end
	x =   x + u3 * v3; if n == 3 then return x end
	x =   x + u4 * v4; return x
end
local dot = lg.dot

function lg.cross(u, v) -- Cg only has the three-dimensional version
	local n, u1, v1, u2, v2, u3, v3, u4, v4 = conform(u, v)
	assert(n ~= 1)
	local w3 = u1 * v2 - v1 * u2
	if n == 2 then return w3 end
	local w1, w2 = u2 * v3 - v2 * u3, u3 * v1 - v3 * u1
	if n == 3 then return (_number3(w1, w2, w3)) end
	local w4 = u4 * v4
	return (_number4(w1, w2, w3, w4))
end

function lg.length(v) return (_sqrt(dot(v, v))) end
local length = lg.length

function lg.distance(u, v) return (length(sub(v, u))) end

function lg.normalize(v) return (div(v, length(v))) end

-- faceforward, reflect, refract, lit

function lg.faceforward(n, i, ng)
	n = tonumbers(n); return dot(i, ng) < 0 and n or -n
end

function lg.reflect(i, n) return i - mul(2 * dot(n, i), n) end

function lg.refract(i, n, eta)
	local cosi = dot(-i, n)
	local cos2t = 1 - eta * eta * (1 - cosi * cosi)
	if cos2t < 0 then return nil end
	return mul(eta, i) + mul(eta * cosi - _sqrt(cos2t), n)
end

function lg.lit(ndotl, ndoth, m)
	local specular = ndotl > 0 and max(0, ndoth)^m or 0
	return (_number4(1, max(0, ndotl), specular, 1))
end

return lg
