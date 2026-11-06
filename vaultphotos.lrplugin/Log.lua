--[[----------------------------------------------------------------------------
Log.lua — shared logger. On macOS, writes to
~/Library/Logs/Adobe/Lightroom/LrClassicLogs/vaultphotos.log.
Use `local log = require 'Log'`, then log:trace(...) or log:warn(...).
------------------------------------------------------------------------------]]

local LrLogger = import 'LrLogger'

local logger = LrLogger('vaultphotos')
logger:enable('logfile')

return logger
