local T = dofile('tests/testing.lua')
local JSON = require 'JSON'
local eq = T.eq

--== encode ==--
eq(JSON.encode(nil), 'null', 'nil')
eq(JSON.encode(true), 'true', 'true')
eq(JSON.encode(12), '12', 'integer')
eq(JSON.encode(-0.5), '-0.5', 'fraction')
eq(JSON.encode(744000000), '744000000', 'large integer')
eq(JSON.encode(48.989123), '48.989122999999999', '17 digits')
eq(tonumber(JSON.encode(0.1)), 0.1, 'round trip')
eq(JSON.encode(2 ^ 60), '1.152921504606847e+18', 'beyond 2^53')
eq(JSON.encode('a"b\\c\n\t\1\127é'), '"a\\"b\\\\c\\n\\t\\u0001\\u007fé"', 'string escapes')
eq(JSON.encode({}), '[]', 'empty table is an array')
eq(JSON.encode(JSON.object()), '{}', 'empty object')
eq(JSON.encode({ 1, 'a', { 2 } }), '[1,"a",[2]]', 'array')
eq(JSON.encode({ b = 1, a = { x = true } }), '{"a":{"x":true},"b":1}', 'object, keys sorted')
eq(pcall(JSON.encode, JSON.object { 1, 2 }), false, 'object with number keys')
eq(pcall(JSON.encode, { [1] = 1, [3] = 3 }), false, 'sparse array has number keys')
eq(pcall(JSON.encode, 0 / 0), false, 'NaN')
eq(pcall(JSON.encode, math.huge), false, 'infinity')
eq(pcall(JSON.encode, print), false, 'function')
do
	local t = {}
	t.self = t
	eq(pcall(JSON.encode, t), false, 'cycle')
	local shared = { 1 }
	eq(JSON.encode({ shared, shared }), '[[1],[1]]', 'shared table is not a cycle')
end

--== decode ==--
local function dec(s) return (JSON.decode(s)) end
eq(dec('null'), nil, 'null')
eq(dec(' true '), true, 'true')
eq(dec('false'), false, 'false')
eq(dec('-12.5e1'), -125, 'number')
eq(dec('"a\\"b\\\\c\\/\\n\\u00e9\\ud83d\\ude00"'), 'a"b\\c/\né\240\159\152\128', 'string escapes')
eq(dec('"\\ud83d"'), '\239\191\189', 'lone surrogate')
eq(dec('"é"'), 'é', 'UTF-8 passes through')
eq(dec('"a\127b"'), 'a\127b', 'DEL passes through')
do
	local v = dec('{"protocol": 1, "photos": [{"uuid": "u", "remoteId": "r.jpg"}, {"uuid": "v", "error": "e"}],'
		.. ' "warnings": [], "path": null}')
	eq(v.protocol, 1, 'object field')
	eq(#v.photos, 2, 'array length')
	eq(v.photos[2].error, 'e', 'nested')
	eq(#v.warnings, 0, 'empty array')
	eq(v.path, nil, 'null field')
	eq(JSON.encode(dec('{}')), '{}', 'decoded empty object stays an object')
end
for _, bad in ipairs { '', '{', '[1,', '{"a" 1}', '{a: 1}', '"abc', '"a\nb"', '"\\x"', '1 2', 'nul', '[1,]', '-' } do
	local v, err = JSON.decode(bad)
	eq(v == nil and type(err) == 'string', true, 'error for ' .. bad)
end
do
	local _, err = JSON.decode('{"a": tru}')
	eq(err, 'JSON: unexpected "t" at byte 7', 'error message')
end

T.done()
