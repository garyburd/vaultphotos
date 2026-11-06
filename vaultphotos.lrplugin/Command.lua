--[[----------------------------------------------------------------------------
Command.lua — runs the publish command using PROTOCOL.md.
See DEVELOPING.md for logs and request replay.
------------------------------------------------------------------------------]]

---@type any
local LrDate      = import 'LrDate'
---@type any
local LrFileUtils = import 'LrFileUtils'
---@type any
local LrPathUtils = import 'LrPathUtils'
---@type any
local LrTasks     = import 'LrTasks'

local JSON = require 'JSON'
local log = require 'Log'

local M = {}

-- Keep this version in sync with PROTOCOL.md and the command.
M.PROTOCOL = 5

---Quote s for /bin/sh.
---@param s string
---@return string
function M.quote(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

---Decode the raw wait status that LrTasks.execute returns: the exit code,
---or nil and the signal that killed the command.
---@param raw number
---@return integer? code
---@return integer? signal
function M.status(raw)
	local signal = raw % 128 -- bit 7 is the core dump flag
	if signal ~= 0 then return nil, signal end
	return math.floor(raw / 256)
end

---@param text string
---@return string[]
local function nonBlankLines(text)
	local lines = {}
	for line in text:gmatch('[^\r\n]+') do
		if line:match('%S') then lines[#lines + 1] = line end
	end
	return lines
end

---Return the last n nonblank lines of text.
---@param text string
---@param n integer
---@return string
function M.tail(text, n)
	local lines = nonBlankLines(text)
	return table.concat(lines, '\n', math.max(1, #lines - n + 1))
end

---Return message without blank lines.
---@param message string
---@return string
function M.compact(message)
	return table.concat(nonBlankLines(message), '\n')
end

local function readAll(path)
	local file = io.open(path, 'rb')
	if not file then return nil end
	local data = file:read('*a')
	file:close()
	return data
end

---Return nil and the response, or an error message if it is unusable.
---@param path string
---@return string? failure
---@return table? response
local function readResponse(path)
	local data = readAll(path)
	if not data then return 'the publish command wrote no response' end
	local response, err = JSON.decode(data)
	if err then return 'cannot read the publish command\'s response: ' .. err end
	if type(response) ~= 'table' then return 'the publish command\'s response is not a JSON object' end
	if response.protocol ~= M.PROTOCOL then
		return string.format('the publish command speaks protocol %s, not %d',
			tostring(response.protocol), M.PROTOCOL)
	end
	return nil, response
end

---Run commandLine with request, setting request.protocol. Must be called
---from a Lightroom task. Returns the decoded response, or nil and an error
---message on command failure or an invalid response. The caller handles
---response.error and response.warnings.
---
---commandLine is shell text, run from / with
---PATH=/usr/bin:/bin:/usr/sbin:/sbin. stderr is logged. Command failures and
---invalid responses retain temporary files; the log gives the folder path.
---@param commandLine string? the service's command line setting
---@param request table
---@return table?
---@return string?
function M.run(commandLine, request)
	if type(commandLine) ~= 'string' or not commandLine:match('%S') then
		return nil, 'Enter the command line of the publish command.'
	end

	request.protocol = M.PROTOCOL
	local ok, encoded = pcall(JSON.encode, request)
	if not ok then return nil, 'cannot encode the request: ' .. tostring(encoded) end

	local dir = LrFileUtils.chooseUniqueFileName(
		LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'vaultphotos-' .. tostring(request.op)))
	LrFileUtils.createAllDirectories(dir)
	local requestPath = LrPathUtils.child(dir, 'request.json')
	local responsePath = LrPathUtils.child(dir, 'response.json')
	local stderrPath = LrPathUtils.child(dir, 'stderr')
	local file, err = io.open(requestPath, 'wb')
	if not file then return nil, 'cannot write ' .. requestPath .. ': ' .. tostring(err) end
	file:write(encoded)
	file:close()

	local start = LrDate.currentTime()
	local raw = LrTasks.execute(commandLine .. ' ' .. M.quote(requestPath) .. ' '
		.. M.quote(responsePath) .. ' 2>' .. M.quote(stderrPath))
	local stderr = readAll(stderrPath) or ''
	for line in stderr:gmatch('[^\n]+') do log:trace(line) end

	local code, signal = M.status(raw)
	local failure, response
	if signal then
		failure = 'the publish command was killed by signal ' .. signal
	elseif code == 127 then
		failure = 'the publish command was not found. Name the program by its absolute path: '
			.. 'Lightroom runs it with PATH=/usr/bin:/bin:/usr/sbin:/sbin.'
	elseif code ~= 0 then
		failure = 'the publish command failed (exit status ' .. code .. ')'
		local last = M.tail(stderr, 5)
		if last ~= '' then failure = failure .. ':\n' .. last end
	else
		failure, response = readResponse(responsePath)
	end
	if failure then
		log:warn(tostring(request.op) .. ': ' .. failure .. '; its files are kept in ' .. dir)
		return nil, failure
	end
	log:trace(string.format('%s: %.0f ms', tostring(request.op), (LrDate.currentTime() - start) * 1000))
	LrFileUtils.delete(dir)
	return response
end

return M
