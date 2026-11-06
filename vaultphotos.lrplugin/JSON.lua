--[[----------------------------------------------------------------------------
JSON.lua — JSON encoding and decoding for Lua 5.1, without Lightroom imports.
------------------------------------------------------------------------------]]

local M = {}

local objectMeta = {}

---Mark t as a JSON object, creating a new table if t is nil.
---An empty marked table encodes as {} rather than [].
---@param t table?
---@return table
function M.object(t)
	return setmetatable(t or {}, objectMeta)
end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
	['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encodeString(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return escapes[c] or string.format('\\u%04x', c:byte())
	end) .. '"'
end

local function isArray(t)
	if getmetatable(t) == objectMeta then return false end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= 'number' or k < 1 or k ~= math.floor(k) then return false end
		n = n + 1
	end
	return n == #t
end

local encodeValue

local function encodeTable(t, seen)
	if seen[t] then error('JSON: cannot encode a cycle') end
	seen[t] = true
	local parts = {}
	if isArray(t) then
		for i = 1, #t do parts[i] = encodeValue(t[i], seen) end
		seen[t] = nil
		return '[' .. table.concat(parts, ',') .. ']'
	end
	local keys = {}
	for k in pairs(t) do
		if type(k) ~= 'string' then error('JSON: object key is not a string: ' .. tostring(k)) end
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for i, k in ipairs(keys) do parts[i] = encodeString(k) .. ':' .. encodeValue(t[k], seen) end
	seen[t] = nil
	return '{' .. table.concat(parts, ',') .. '}'
end

function encodeValue(v, seen)
	local kind = type(v)
	if kind == 'nil' then return 'null' end
	if kind == 'boolean' then return tostring(v) end
	if kind == 'string' then return encodeString(v) end
	if kind == 'number' then
		if v ~= v or v == math.huge or v == -math.huge then error('JSON: cannot encode ' .. tostring(v)) end
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format('%.0f', v) end
		return string.format('%.17g', v)
	end
	if kind == 'table' then return encodeTable(v, seen) end
	error('JSON: cannot encode a ' .. kind)
end

---Encode v as JSON. Empty tables and tables with keys 1..n encode as
---arrays; other tables require string keys and encode as objects. Use
---object to force object encoding. Object keys are sorted, and numbers
---retain enough precision to round-trip. Throws for unsupported values,
---non-string object keys, or cycles.
---@param v any
---@return string
function M.encode(v)
	return encodeValue(v, {})
end

local function utf8(c)
	if c < 0x80 then return string.char(c) end
	if c < 0x800 then return string.char(0xC0 + math.floor(c / 0x40), 0x80 + c % 0x40) end
	if c < 0x10000 then
		return string.char(0xE0 + math.floor(c / 0x1000), 0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
	end
	return string.char(0xF0 + math.floor(c / 0x40000), 0x80 + math.floor(c / 0x1000) % 0x40,
		0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
end

---Decode s, returning the value or nil and an error message. JSON null
---becomes nil, leaving holes in arrays and omitting object fields. Decoded
---objects retain their object encoding. Lone surrogates become U+FFFD.
---@param s string
---@return any
---@return string?
function M.decode(s)
	local pos = 1

	---@return nil
	local function fail(what)
		error({ message = string.format('JSON: %s at byte %d', what, pos) })
	end

	local function space()
		pos = s:find('[^ \t\r\n]', pos) or #s + 1
	end

	local value

	local function str()
		pos = pos + 1
		local parts = {}
		while true do
			-- Unlike Lua's %c, JSON's control range excludes DEL (0x7F).
			local stop = s:find('["\\%z\1-\31]', pos)
			if not stop then fail('unterminated string') end
			---@cast stop integer
			parts[#parts + 1] = s:sub(pos, stop - 1)
			local c = s:sub(stop, stop)
			if c == '"' then
				pos = stop + 1
				return table.concat(parts)
			elseif c ~= '\\' then
				pos = stop
				fail('control character in string')
			end
			local e = s:sub(stop + 1, stop + 1)
			local simple = ({ ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f',
				n = '\n', r = '\r', t = '\t' })[e]
			if simple then
				parts[#parts + 1] = simple
				pos = stop + 2
			elseif e == 'u' then
				local hex = s:match('^%x%x%x%x', stop + 2)
				if not hex then pos = stop; fail('bad \\u escape') end
				local code = tonumber(hex, 16) --[[@as integer]]
				pos = stop + 6
				if code >= 0xD800 and code < 0xDC00 then
					local low = s:match('^\\u(%x%x%x%x)', pos)
					local lowCode = low and tonumber(low, 16)
					if lowCode and lowCode >= 0xDC00 and lowCode < 0xE000 then
						code = 0x10000 + (code - 0xD800) * 0x400 + (lowCode - 0xDC00)
						pos = pos + 6
					else
						code = 0xFFFD
					end
				elseif code >= 0xDC00 and code < 0xE000 then
					code = 0xFFFD
				end
				parts[#parts + 1] = utf8(code)
			else
				pos = stop
				fail('bad escape')
			end
		end
	end

	function value()
		space()
		local c = s:sub(pos, pos)
		if c == '{' then
			pos = pos + 1
			local t = M.object()
			space()
			if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
			while true do
				space()
				if s:sub(pos, pos) ~= '"' then fail('expected a key') end
				local k = str()
				space()
				if s:sub(pos, pos) ~= ':' then fail('expected ":"') end
				pos = pos + 1
				t[k] = value()
				space()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == '}' then return t end
				if d ~= ',' then pos = pos - 1; fail('expected "," or "}"') end
			end
		elseif c == '[' then
			pos = pos + 1
			local t, n = {}, 0
			space()
			if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
			while true do
				n = n + 1
				t[n] = value()
				space()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == ']' then return t end
				if d ~= ',' then pos = pos - 1; fail('expected "," or "]"') end
			end
		elseif c == '"' then
			return str()
		end
		if s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true end
		if s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false end
		if s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil end
		local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
		local n = num and tonumber(num)
		if not n then fail('unexpected ' .. (c == '' and 'end' or string.format('%q', c))) end
		pos = pos + #num
		return n
	end

	local ok, result = pcall(function()
		local v = value()
		space()
		if pos <= #s then fail('extra text') end
		return v
	end)
	if ok then return result end
	if type(result) == 'table' then return nil, result.message end
	return nil, tostring(result)
end

return M
