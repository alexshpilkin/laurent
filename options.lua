local arg, setmetatable, type = arg, setmetatable, type
local find, substr = string.find, string.sub
local concat, insert = table.concat, table.insert

local _ENV = {}
if setfenv then setfenv(1, _ENV) end

local function matcher(option)
	local len, sign = #option, substr(option, 1, 1)
	if len == 0 then
		option = '[^=]*$'
	elseif sign ~= '-' and sign ~= '+' and substr(option, -1, -1) ~= '=' then
		len, sign, option = len + 1, '-', '[-+]'..option
	end
	option = '^'..option
	return function (opt)
		if not find(opt, option) then return nil end
		local arg = substr(opt, len + 1)
		return arg ~= '' and arg or substr(opt, 1, 1) == sign and ''
	end
end

function last(option, opts)
	local match = matcher(option)
	for i = #opts, 1, -1 do
		local arg = match(opts[i])
		if arg ~= nil then return arg, i end
	end
end

function all(option, opts)
	local match, args, idcs = matcher(option), {}, {}
	for i = 1, #opts do
		local arg = match(opts[i])
		if arg ~= nil then insert(args, arg); insert(idcs, i) end
	end
	return args, idcs
end

setmetatable(_ENV, {__call = function (self, ...)
	return self.pop(...)
end})

function pop(optstring, opts, args)
	if not args then opts, args = {}, opts end
	if not args then args = arg end -- the global one

	local signs = '-'
	if substr(optstring, 1, 1) == '+' then -- ksh getopts(1)
		signs, optstring = '-+', substr(optstring, 2)
	end

	local i, n, err = 1, #args, nil
	while i <= n do
		local sign, arg = substr(args[i], 1, 1), substr(args[i], 2)
		if not find(signs, sign, 1, true) or #arg == 0 then break end
		i = i + 1
		if arg == sign then insert(opts, sign..arg); break end

		while #arg > 0 do -- quadratic but error exits are simple
			local opt = substr(arg, 1, 1)
			local j = find(optstring, opt, 1, true)
			if not j then break end -- unknown option

			arg = substr(arg, 2)
			if substr(optstring, j+1, j+1) == ':' then
				if arg == '' and substr(optstring, j+1, j+2) ~= '::' then
					if i > n then break end -- missing argument
					arg = args[i]; i = i + 1
				end
				insert(opts, sign..opt..arg)
				arg = '' -- consumed
			else
				insert(opts, sign..opt)
			end
		end
		if arg ~= '' then err = sign..arg; break end
	end

	local left = {err or args[i]}
	for j = 2, n - i + 1 do left[j] = args[i+j-1] end
	return opts, left
end

function sub(opt)
	if type(opt) == 'table' then opt = concat(opt, ',') end

	local i, subs = 1, {}
	while i <= #opt do
		local comma = find(opt, ',', i, true) or #opt + 1
		insert(subs, substr(opt, i, comma - 1))
		i = comma + 1
	end
	return subs
end

return _ENV
