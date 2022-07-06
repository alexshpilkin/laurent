local lg = require 'lg'

local select, setmetatable = select, setmetatable
local tonumbers = lg.tonumbers
local max, min = math.max, math.min
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
	]])(min, max)

	self[n] = mt
	return mt
end})

function lift(func, ...)
	local function lifted(...)
		return (lifts[select('#', ...)](func, ...))
	end
	if select('#', ...) ~= 0 then return (lifted(...)) end
	return lifted
end

-- x, y, z, w

x, y, z, w = {}, {}, {}, {}
local x, y, z, w = x, y, z, w

function x.value(_self, ...) return tonumbers(...).x end
function y.value(_self, ...) return tonumbers(...).y end
function z.value(_self, ...) return tonumbers(...).z end
function w.value(_self, ...) return tonumbers(...).w end

-- unbounded

return _ENV
