local lg = require 'lg'

local getmetatable, rawequal, select, setmetatable, tostring = getmetatable, rawequal, select, setmetatable, tostring
local abs, dot, hadd, hmin, hmul, max, number2, number3, number4, step, tonumbers = lg.abs, lg.dot, lg.hadd, lg.hmin, lg.hmul, lg.max, lg.number2, lg.number3, lg.number4, lg.step, lg.tonumbers
local ceil, floor, _max, _min = math.ceil, math.floor, math.max, math.min
local concat, insert = table.concat, table.insert

local loadstring = loadstring or load

local _ENV = {}
if setfenv then setfenv(1, _ENV) end

-- const, lift

const = setmetatable({__name = 'const'}, {__call = function (self, const)
	return setmetatable({const = const}, self)
end})
local const = const

const.__index = const

function const:value()
	return self.const
end

-- unbounded

local lifts = setmetatable({}, {__index = function (self, n)
	local imgs, init, bded, vals, bnds, mins, maxs = {}, {}, {}, {}, {}, {}, {}
	for i = 1, n do
		insert(imgs, 'img'..i)
		insert(init, 'img'..i..' = img'..i)
		insert(bded, 'img'..i..'.bound')
		insert(vals, 'self.img'..i..':value(...)')
		insert(bnds, 'local min'..i..', max'..i..' = self.img'..i..':bound(...)')
		insert(mins, 'min'..i)
		insert(maxs, 'max'..i)
	end

	local mt = setmetatable({__name = 'lift'..n}, {__call = loadstring([[
		local setmetatable = ...
		return function (self, func, ...)
			local ]]..concat(imgs, ', ')..[[ = ...
			local mt = ]]..concat(bded, ' and ')..[[ and self.bounded or self
			return setmetatable({
				func = func, ]]..concat(init, ', ')..[[
			}, mt)
		end
	]])(setmetatable)})
	mt.__index = mt

	mt.bounded = setmetatable({__name = 'lift'..n..'.bounded'}, mt)
	mt.bounded.__index = mt.bounded

	mt.value = loadstring([[
		return function (self, ...)
			return (self.func(]]..concat(vals, ', ')..[[))
		end
	]])()

	mt.bounded.bound = loadstring([[
		local min, max = ...
		return function (self, ...)
			]]..concat(bnds, '\n')..[[
			return min(]]..concat(mins, ', ')..[[),
			       max(]]..concat(maxs, ', ')..[[)
		end
	]])(_min, _max)

	self[n] = mt
	return mt
end})

function lift(func, ...)
	local function lifted(...)
		return (lifts[tostring(select('#', ...))](func, ...))
	end
	if select('#', ...) ~= 0 then return (lifted(...)) end
	return lifted
end

-- add, sub, mul, div

add = lift(function (lhs, rhs) return lhs + rhs end)
sub = lift(function (lhs, rhs) return lhs - rhs end)
div = lift(function (lhs, rhs) return lhs / rhs end)

mul = setmetatable({__name = 'mul'}, {__call = function (self, lhs, rhs)
	-- bounds can be tighter than for a generic lift
	local lbound, rbound = lhs.bound, rhs.bound
	local mt = self
	if lbound and rbound then
		mt = self.bounded
	elseif lbound then
		mt = self.lbounded
	elseif rbound then
		mt = self.rbounded
	end
	return setmetatable({lhs = lhs, rhs = rhs}, mt)
end})
local mul = mul

mul.__index = mul

mul.lbounded = setmetatable({__name = 'mul.lbounded'}, mul)
mul.lbounded.__index = mul.lbounded
mul.rbounded = setmetatable({__name = 'mul.rbounded'}, mul)
mul.rbounded.__index = mul.rbounded
mul.bounded  = setmetatable({__name = 'mul.bounded'},  mul)
mul.bounded.__index  = mul.bounded

function mul:value(...)
	return self.lhs:value(...) * self.rhs:value(...)
end

function mul:apply(field)
	return (self.rhs:apply(mul(field, self.lhs)))
end

function mul.lbounded:bound(...)
	local lmin, lmax = self.lhs:bound(...)
	return lmin, lmax
end

function mul.rbounded:bound(...)
	local rmin, rmax = self.rhs:bound(...)
	return rmin, rmax
end

function mul.bounded:bound(...)
	local lmin, lmax = self.lhs:bound(...)
	local rmin, rmax = self.rhs:bound(...)
	return _max(lmin, rmin), _min(lmax, rmax)
end

-- translate, scale

translate = setmetatable({__name = 'translate'}, {__call = function (self, object, ...)
	local mt, d = getmetatable(object), tonumbers(...)
	if rawequal(mt, self) or rawequal(mt, self.bounded) then
		object, d = object.object, d + object.displacement
	end
	mt = object.bound and self.bounded or self
	return setmetatable({object = object, displacement = d}, mt)
end})
local translate = translate

translate.__index = translate

translate.bounded = setmetatable({__name = 'translate.bounded'}, translate)
translate.bounded.__index = translate.bounded

function translate:value(...)
	return (self.object:value(tonumbers(...) - self.displacement))
end

function translate:apply(field)
	return (self.object:apply(translate(field, -self.displacement)))
end

function translate.bounded:bound(...)
	local f = tonumbers(...)
	local foff, fmin, fmax = dot(f, self.displacement), self.object:bound(f)
	return fmin + foff, fmax + foff
end

scale = setmetatable({__name = 'scale'}, {__call = function (self, object, ...)
	local mt, s = getmetatable(object), tonumbers(...)
	if rawequal(mt, translate) or rawequal(mt, translate.bounded) then
		return (translate(self(object.object, s), s * object.displacement))
	end
	local is = 1 / s
	if rawequal(mt, self) or rawequal(mt, self.bounded) then
		object, s, is = object.object, s * object.scale, is * object.iscale
	end
	mt = object.bound and self.bounded or self
	return setmetatable({object = object, scale = s, iscale = is}, mt)
end})
local scale = scale

scale.__index = scale

scale.bounded = setmetatable({__name = 'scale.bounded'}, scale)
scale.bounded.__index = scale.bounded

function scale:value(...)
	return (self.object:value(tonumbers(...) * self.iscale))
end

function scale:apply(field)
	return (self.object:apply(scale(field, self.iscale)))
end

function scale.bounded:bound(...)
	local fmin, fmax = self.object:bound(tonumbers(...) * self.scale)
	return fmin, fmax
end

-- filter

filter = setmetatable({__name = 'filter'}, {__call = function (self, field, probe)
	local mt = field.bound and probe.bound and self.bounded or self
	return setmetatable({field = field, probe = probe}, mt)
end})
local filter = filter

filter.__index = filter

filter.bounded = setmetatable({__name = 'filter.bounded'}, filter)
filter.bounded.__index = filter.bounded

function filter:value(...)
	return (self.probe:apply(translate(self.field, -tonumbers(...))))
end

function filter.bounded:bound(...)
	local fmin, fmax = self.field:bound(...)
	local pmin, pmax = self.probe:bound(...)
	return fmin + pmin, fmax + pmax
end

-- x, y, z, w

x, y, z, w = {}, {}, {}, {}
local x, y, z, w = x, y, z, w

function x.value(_self, ...) return tonumbers(...).x end
function y.value(_self, ...) return tonumbers(...).y end
function z.value(_self, ...) return tonumbers(...).z end
function w.value(_self, ...) return tonumbers(...).w end

-- unbounded

-- box, triangle

box = {}
local box = box

function box.value(_self, ...)
	return (hmin(step(abs(tonumbers(...)), 0.5)))
end

function box.bound(_self, ...)
	local b = hadd(abs(tonumbers(...))) * 0.5
	return -b, b
end

triangle = {}
local triangle = triangle

function triangle.value(_self, ...)
	return (hmul(max(0, 1 - abs(tonumbers(...)))))
end

function triangle.bound(_self, ...)
	local b = hadd(abs(tonumbers(...)))
	return -b, b
end

-- grid, grid2, grid3, grid4

local function snap(tmin, tmax)
	return ceil(tmin), floor(tmax)
end

grid = {}
local grid = grid

function grid.apply(_self, field)
	local xmin, xmax = snap(field:bound(1))

	local sum = 0
	for i = xmin, xmax do
		sum = sum + field:value(i)
	end
	return sum
end

grid2 = {}
local grid2 = grid2

function grid2.apply(_self, field)
	local xmin, xmax = snap(field:bound(number2(1, 0)))
	local ymin, ymax = snap(field:bound(number2(0, 1)))

	local sum = 0
	for i = xmin, xmax do for j = ymin, ymax do
		sum = sum + field:value(number2(i, j))
	end end
	return sum
end

grid3 = {}
local grid3 = grid3

function grid3.apply(_self, field)
	local xmin, xmax = snap(field:bound(number3(1, 0, 0)))
	local ymin, ymax = snap(field:bound(number3(0, 1, 0)))
	local zmin, zmax = snap(field:bound(number3(0, 0, 1)))

	local sum = 0
	for i = xmin, xmax do for j = ymin, ymax do for k = zmin, zmax do
		sum = sum + field:value(number3(i, j, k))
	end end end
	return sum
end

grid4 = {}
local grid4 = grid4

function grid4.apply(_self, field)
	local xmin, xmax = snap(field:bound(number4(1, 0, 0, 0)))
	local ymin, ymax = snap(field:bound(number4(0, 1, 0, 0)))
	local zmin, zmax = snap(field:bound(number4(0, 0, 1, 0)))
	local wmin, wmax = snap(field:bound(number4(0, 0, 0, 1)))

	local sum = 0
	for i = xmin, xmax do for j = ymin, ymax do for k = zmin, zmax do for l = wmin, wmax do
		sum = sum + field:value(number4(i, j, k, l))
	end end end end
	return sum
end

return _ENV
