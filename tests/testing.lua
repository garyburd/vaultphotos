-- Shared helpers for the Lua tests. Run each test from the repository
-- root with lua or luajit: lua tests/json_test.lua

local M = { pass = 0, fail = 0 }

-- Match LrTasks.execute's raw wait status across Lua versions: Lua 5.2+
-- returns an exit code or signal, while Lua 5.1 and LuaJIT return the status.
local function execute(cmd)
	local a, kind, code = os.execute(cmd)
	if type(a) == 'number' then return a end
	if kind == 'signal' then return code end
	return code * 256
end

-- Command.run's SDK dependencies, without Lightroom's task scheduler.
local fakes = {
	LrDate = { currentTime = function() return os.time() end },
	LrFileUtils = {
		chooseUniqueFileName = function(path)
			return path .. '-' .. tostring(os.time()) .. '-' .. tostring(math.random(1e9))
		end,
		createAllDirectories = function(path) execute("mkdir -p '" .. path .. "'") end,
		delete = function(path) execute("rm -r '" .. path .. "'") end,
	},
	LrLogger = function()
		local logger = { lines = {} }
		function logger:enable() end
		function logger:trace(s) self.lines[#self.lines + 1] = 'TRACE ' .. s end
		function logger:warn(s) self.lines[#self.lines + 1] = 'WARN ' .. s end
		return logger
	end,
	LrPathUtils = {
		child = function(dir, name) return dir .. '/' .. name end,
		getStandardFilePath = function() return (os.getenv('TMPDIR') or '/tmp'):gsub('/$', '') end,
	},
	LrTasks = { execute = execute },
}

---@return any
function import(name) return fakes[name] or {} end -- luacheck: ignore

package.path = 'vaultphotos.lrplugin/?.lua;' .. package.path

function M.eq(got, want, msg)
	if got == want then
		M.pass = M.pass + 1
	else
		M.fail = M.fail + 1
		print(string.format('FAIL: %s\n  want: %q\n  got:  %q', msg, tostring(want), tostring(got)))
	end
end

function M.done()
	print(string.format('%d passed, %d failed', M.pass, M.fail))
	if M.fail > 0 then os.exit(1) end
end

return M
