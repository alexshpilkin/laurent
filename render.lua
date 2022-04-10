local width, height = 256, 256

local srgb = require 'srgb'
local xyze = require 'xyze'

local trace
if require 'isatty' (io.stderr) then
	local format, stderr = string.format, io.stderr
	function trace(...) return stderr:write(format(...)) end
else
	function trace() end
end

local pic = assert(xyze("render.hdr", width, height))
for j = height - 1, 0, -1 do
	trace('%d / %d lines', height-j-1, height)
	for i = 0, width - 1 do
		pic(srgb(i / (width - 1), j / (height - 1), 0.25))
	end
	trace('\r\27[K')
end
