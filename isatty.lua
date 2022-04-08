local stdin, stdout, stderr = io.stdin, io.stdout, io.stderr
local execute = os.execute
local format = string.format

local function try(...)
	local ok, result = pcall(...)
	if ok then return result end
end

pcall(function () require 'ffi'.cdef [[
	int isatty(int);
	int _isatty(int);
	int fileno(struct FILE *);
]] end)

local fileno =
	try(function () return require 'ffi'.C.fileno end) or
	try(function () return require 'ffi'.C._fileno end) or
	try(function () return require 'ffi'.load 'ucrtbase'._fileno end) or
	try(function () return require 'posix.stdio'.fileno end) or
	try(function () return require 'fs'.fileno end) or
	function (file)
		if file == stdin  then return 0 end
		if file == stdout then return 1 end
		if file == stderr then return 2 end
	end

local isatty =
	try(function () return require 'ffi'.C.isatty end) or
	try(function () return require 'ffi'.C._isatty end) or
	try(function () return require 'ffi'.load 'ucrtbase'._isatty end) or
	try(function () return require 'posix.unistd'.isatty end) or
	os.type == 'unix' and function (fd) -- luacheck: ignore 143 (luatex)
		local status = execute(format('test -t %d', fd))
		return status == true or status == 0
	end or function ()
		return 0
	end

-- FIXME ismintty on Windows -- see cluttex/src/texrunner/isatty.lua

return function (file)
	local fd = fileno(file)
	return fd ~= nil and isatty(fd) ~= 0 -- true or false
end
