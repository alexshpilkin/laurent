local lg = require 'lg'

local select, setmetatable, tostring = select, setmetatable, tostring
local abs, hadd, hmin, hmul, max, step, tonumbers = lg.abs, lg.hadd, lg.hmin, lg.hmul, lg.max, lg.step, lg.tonumbers
local _max, _min = math.max, math.min
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

return _ENV
