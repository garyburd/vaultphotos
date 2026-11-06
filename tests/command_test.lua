local T = dofile('tests/testing.lua')
local Command = require 'Command'
local eq = T.eq

--== quote ==--
eq(Command.quote('/a b/c'), "'/a b/c'", 'spaces')
eq(Command.quote("it's"), "'it'\\''s'", 'single quote')
eq(Command.quote('$HOME `x` "y"'), "'$HOME `x` \"y\"'", 'shell characters')
do
	local s = "a 'b' $c \\d \"e\" `f` \n g"
	local p = io.popen('printf %s ' .. Command.quote(s))
	eq(p:read('*a'), s, 'sh reads it back')
	p:close()
end

--== status ==--
local function status(raw)
	local code, signal = Command.status(raw)
	return tostring(code) .. '/' .. tostring(signal)
end
eq(status(0), '0/nil', 'success')
eq(status(256), '1/nil', 'exit 1')
eq(status(127 * 256), '127/nil', 'command not found')
eq(status(9), 'nil/9', 'killed')
eq(status(6 + 128), 'nil/6', 'signal with core dump flag')

--== tail ==--
eq(Command.tail('a\nb\n\nc\n  \nd\n', 2), 'c\nd', 'last two non-blank lines')
eq(Command.tail('a\r\nb', 5), 'a\nb', 'fewer lines than asked')
eq(Command.tail('', 5), '', 'empty')

--== compact ==--
eq(Command.compact('The site configuration has errors:\n\nsite.yaml:7: a\nsite.yaml:3: b'),
	'The site configuration has errors:\nsite.yaml:7: a\nsite.yaml:3: b', 'blank lines dropped')
eq(Command.compact('one line'), 'one line', 'one line')

--== run ==--
local JSON = require 'JSON'
local log = require 'Log'
do
	local function read(path)
		local f = io.open(path, 'rb')
		if not f then return nil end
		local data = f:read('*a')
		f:close()
		return data
	end
	local function write(path, data)
		local f = assert(io.open(path, 'wb'))
		f:write(data)
		f:close()
	end
	local p = io.popen('mktemp -d')
	local dir = p:read('*a'):gsub('%s+$', '')
	p:close()
	assert(dir:match('^/') and #dir > 8, 'mktemp -d failed: ' .. dir)
	local stub = dir .. "/stub 'command'.sh"
	write(stub, table.concat({
		'#!/bin/sh',
		'# usage: stub <out dir> <exit status> request.json response.json',
		'cp "$3" "$1/seen.json"',
		'[ -f "$1/response.json" ] && cp "$1/response.json" "$4"',
		'echo "trace one" >&2',
		'echo "trace two" >&2',
		'exit "$2"',
	}, '\n') .. '\n')
	os.execute('chmod +x ' .. Command.quote(stub))
	local function commandLine(status)
		return Command.quote(stub) .. ' ' .. Command.quote(dir) .. ' ' .. status
	end

	write(dir .. '/response.json', '{"protocol": 5, "photos": [{"uuid": "U", "remoteId": "u.jpg"}],'
		.. ' "warnings": [{"title": "T", "message": "M\\nN"}]}')
	local request = {
		op = 'publish',
		service = { JSON.object { id = 10, path = { 'Trips', 'Café' } } },
		collection = 10,
		photos = { JSON.object { uuid = 'U', rendition = "/r/it's.jpg",
			caption = 'Say "hi"\n<there>' } },
		remoteIds = {},
	}
	local response, err = Command.run(commandLine(0), request)
	eq(err, nil, 'run: no error')
	response = response or {}
	eq(response.protocol, 5, 'run: response decoded')
	eq(response.photos and response.photos[1].remoteId, 'u.jpg', 'run: photo result')
	eq(response.warnings and response.warnings[1].message, 'M\nN', 'run: warning')
	local seen = JSON.decode(read(dir .. '/seen.json') or '') or {}
	eq(seen.protocol, Command.PROTOCOL, 'run: request has the protocol')
	eq(seen.op, 'publish', 'run: request op')
	eq(seen.photos and seen.photos[1].rendition, "/r/it's.jpg", 'run: request photo')
	eq(seen.photos and seen.photos[1].caption, 'Say "hi"\n<there>', 'run: request caption')
	eq(seen.service and seen.service[1].path[2], 'Café', 'run: request UTF-8')
	eq(JSON.encode(seen.remoteIds), '[]', 'run: empty array')
	eq(log.lines[#log.lines - 2], 'TRACE trace one', 'run: stderr logged')

	response, err = Command.run(commandLine(3), { op = 'check' })
	eq(response, nil, 'failure: no response')
	eq(err, 'the publish command failed (exit status 3):\ntrace one\ntrace two', 'failure: message')
	eq(log.lines[#log.lines]:match('^WARN check: .*kept in (.*)$') ~= nil, true, 'failure: folder kept')

	write(dir .. '/response.json', '{"protocol": 4}')
	response, err = Command.run(commandLine(0), { op = 'check' })
	eq(err, 'the publish command speaks protocol 4, not ' .. Command.PROTOCOL, 'wrong protocol')

	write(dir .. '/response.json', '{"protocol": 5')
	response, err = Command.run(commandLine(0), { op = 'check' })
	eq(err, "cannot read the publish command's response: JSON: expected \",\" or \"}\" at byte 15", 'bad JSON')

	write(dir .. '/response.json', '3')
	response, err = Command.run(commandLine(0), { op = 'check' })
	eq(err, "the publish command's response is not a JSON object", 'not an object')

	os.remove(dir .. '/response.json')
	response, err = Command.run(commandLine(0), { op = 'check' })
	eq(err, 'the publish command wrote no response', 'no response file')

	response, err = Command.run(Command.quote(dir .. '/missing'), { op = 'check' })
	eq(err and err:match('^the publish command was not found') ~= nil, true, 'missing command')

	response, err = Command.run('  ', { op = 'check' })
	eq(err, 'Enter the command line of the publish command.', 'empty command line')

	os.execute('rm -r ' .. Command.quote(dir))
end

T.done()
