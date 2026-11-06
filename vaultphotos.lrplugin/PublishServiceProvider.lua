--[[----------------------------------------------------------------------------
PublishServiceProvider.lua — the Vault Photos publish service.

Reads the catalog, renders photos, and handles settings and publish
results. The command handles storage; see Command.lua and PROTOCOL.md.
------------------------------------------------------------------------------]]

---@type any
local LrColor       = import 'LrColor'
---@type any
local LrDate        = import 'LrDate'
---@type any
local LrDialogs     = import 'LrDialogs'
---@type any
local LrErrors      = import 'LrErrors'
---@type any
local LrTasks       = import 'LrTasks'
---@type any
local LrView        = import 'LrView'

local Command = require 'Command'
local log = require 'Log'

local TITLE = 'Vault Photos'

-- Protocol 1 settings (vaultphotosVault and others) are ignored.
local COMMAND_KEY = 'vaultphotosCommand'

-- Wait for a pause in typing before checking the command.
local CHECK_DELAY = 0.3
-- Retry errors to detect configuration fixes outside Lightroom. Limit
-- retries to about 15 minutes in case endDialog is missed.
local RECHECK_DELAY = 2
local RECHECKS = 450

--==============================================================================
-- Running the command
--==============================================================================

-- Lightroom calls once per collection; service-wide warnings would repeat.
local shownAt = {}
---Log a warning and show it unless it was shown in the last minute.
local function warnOnce(title, message)
	title, message = tostring(title), tostring(message)
	log:warn(title .. ': ' .. message)
	local key = title .. '\n' .. message
	local now = LrDate.currentTime()
	if shownAt[key] and now - shownAt[key] < 60 then return end
	shownAt[key] = now
	LrDialogs.message(title, message, 'warning')
end

---Run the service's command and show its warnings. Returns the response,
---or nil and an error message if the command or operation fails.
---@param props table the publish settings
---@param request table
---@return table?
---@return string?
local function call(props, request)
	local response, err = Command.run(props[COMMAND_KEY], request)
	if not response then return nil, err end
	for _, w in ipairs(response.warnings or {}) do warnOnce(w.title, w.message) end
	if response.error then return nil, response.error end
	return response
end

---Like call, but throws a Lightroom user error on failure.
---@param props table the publish settings
---@param request table
---@return table
local function run(props, request)
	local response, err = call(props, request)
	if not response then LrErrors.throwUserError(TITLE .. ': ' .. tostring(err)) end
	---@cast response table
	return response
end

--==============================================================================
-- The catalog
--==============================================================================

---Return a copy of list with item appended.
---@param list any[]
---@param item any
---@return any[]
local function append(list, item)
	local out = { unpack(list) }
	out[#out + 1] = item
	return out
end

---Append container's descendant collections to out and return it. Each
---entry is { id, path }, with enclosing set names followed by the
---collection name. sets supplies the path to container, including its
---name when it is a set. If out is nil, create a new list.
---@param container any
---@param sets string[]
---@param out table[]?
---@return table[]
local function collectionsOf(container, sets, out)
	out = out or {}
	for _, collection in ipairs(container:getChildCollections()) do
		out[#out + 1] = { id = collection.localIdentifier, path = append(sets, collection:getName()) }
	end
	for _, set in ipairs(container:getChildCollectionSets()) do
		collectionsOf(set, append(sets, set:getName()), out)
	end
	return out
end

--==============================================================================
-- The service
--==============================================================================

local provider = {}

provider.supportsIncrementalPublish = 'only'
provider.canExportToTemporaryLocation = true
-- The command chooses storage names; rendition names are temporary.
provider.hideSections = { 'exportLocation', 'fileNaming' }
provider.canExportVideo = false
provider.supportsCustomSortOrder = false

provider.exportPresetFields = {
	{ key = COMMAND_KEY, default = '' },
}

-- The protocol supplies no URL or path for Go to Published.
provider.titleForGoToPublishedCollection = 'disable'
provider.titleForGoToPublishedPhoto = 'disable'

-- Defining this callback creates the default collection. SDK defaults
-- allow deleting it and adding others.
function provider.getCollectionBehaviorInfo(publishSettings)
	return {}
end

local openDialogs = {}

-- Dialog callbacks run outside a task, but Command.run requires one.
function provider.startDialog(propertyTable)
	openDialogs[propertyTable] = true
	local generation = 0
	local check
	function check(delay, recheck)
		generation = generation + 1
		local mine = generation
		LrTasks.startAsyncTask(function()
			if delay then LrTasks.sleep(delay) end
			if mine ~= generation or not openDialogs[propertyTable] then return end
			local response, err = Command.run(propertyTable[COMMAND_KEY], { op = 'check' })
			-- A slow check can finish after a newer edit or after the dialog closes.
			if mine ~= generation or not openDialogs[propertyTable] then return end
			local problem = response and response.error or err
			if problem then problem = Command.compact(problem) end
			-- Lightroom disables saving while this is set.
			propertyTable.LR_cantExportBecause = problem
			propertyTable.vaultphotosProblem = problem or ''
			recheck = (recheck or 0) + 1
			if problem and recheck <= RECHECKS then check(RECHECK_DELAY, recheck) end
		end)
	end
	propertyTable:addObserver(COMMAND_KEY, function() check(CHECK_DELAY) end)
	check()
end

function provider.endDialog(propertyTable)
	openDialogs[propertyTable] = nil
end

function provider.sectionsForTopOfDialog(f, propertyTable)
	local bind = LrView.bind
	return {
		{
			title = 'Publish command',
			synopsis = bind(COMMAND_KEY),

			f:row {
				f:static_text { title = 'Command line:', alignment = 'right' },
				f:edit_field {
					value = bind(COMMAND_KEY),
					immediate = true,
					width_in_chars = 60,
					height_in_lines = 2,
					tooltip = 'The program, by its absolute path, and its arguments, quoted for /bin/sh. '
						.. 'For example: /Users/me/go/bin/vaultsite lr-publish /path/to/vault myservice',
				},
			},
			-- Room for a few configuration errors; the tooltip has the
			-- whole message if they don't fit.
			f:static_text {
				title = bind 'vaultphotosProblem',
				tooltip = bind 'vaultphotosProblem',
				text_color = LrColor(0.7, 0.1, 0.1),
				width_in_chars = 60,
				height_in_lines = 6,
			},
			f:static_text {
				title = 'The command does the publishing: Lightroom renders the photos, and the\n'
				     .. 'command stores them. Its configuration says where.',
				height_in_lines = 2,
				text_color = LrColor(0.4, 0.4, 0.4),
			},
		},
	}
end

-- Lightroom deletes renditions when this returns, so wait for the command
-- to finish. Check cancellation after rendering, before starting the command.
function provider.processRenderedPhotos(functionContext, exportContext)
	local service, collection = exportContext.publishService, exportContext.publishedCollection
	local collections = collectionsOf(service, {})
	local props = exportContext.propertyTable

	local nPhotos = exportContext.exportSession:countRenditions()
	local progressScope = exportContext:configureProgress {
		title = nPhotos > 1 and ('Publishing ' .. nPhotos .. ' photos') or 'Publishing 1 photo',
	}

	local photos, renditions = {}, {}
	for _, rendition in exportContext:renditions { stopIfCanceled = true } do
		local photo = rendition.photo
		local uuid = photo:getRawMetadata('uuid')
		local success, pathOrMessage = rendition:waitForRender()
		if success then
			photos[#photos + 1] = {
				uuid = uuid,
				rendition = pathOrMessage,
				caption = photo:getFormattedMetadata('caption'),
			}
			renditions[uuid] = rendition
		else
			rendition:uploadFailed(pathOrMessage)
		end
	end

	if progressScope:isCanceled() then
		log:trace('publish canceled; nothing stored')
		return
	end

	progressScope:setCaption('Running the publish command')
	local response, err = call(props, {
		op = 'publish',
		service = collections,
		collection = collection.localIdentifier,
		photos = photos,
	})
	if not response then
		err = TITLE .. ': ' .. tostring(err)
		log:warn('publish failed: ' .. err)
		for _, rendition in pairs(renditions) do rendition:uploadFailed(err) end
		return
	end
	for _, result in ipairs(response.photos or {}) do
		local rendition = renditions[result.uuid]
		if rendition then
			if result.remoteId then
				rendition:recordPublishedPhotoId(result.remoteId)
			else
				local message = tostring(result.error or 'the command reported no remote ID')
				log:warn('publish failed: ' .. message)
				rendition:uploadFailed(message)
			end
			renditions[result.uuid] = nil
		end
	end
	for _, rendition in pairs(renditions) do rendition:uploadFailed('the command did not report the photo') end
end

function provider.deletePhotosFromPublishedCollection(publishSettings, arrayOfPhotoIds, deletedCallback, localCollectionId)
	local response = run(publishSettings, {
		op = 'delete',
		collection = localCollectionId,
		remoteIds = arrayOfPhotoIds,
	})
	for _, remoteId in ipairs(response.confirmed or {}) do deletedCallback(remoteId) end
end

---Run fn, logging errors under hook instead of throwing them.
---@param hook string for the log
---@param fn function
local function guarded(hook, fn)
	-- Throwing would make Lightroom offer to revert the user's change.
	-- The next publish retries collection synchronization.
	local ok, err = LrTasks.pcall(fn)
	if not ok then log:warn(hook .. ': collections not synced: ' .. tostring(err)) end
end

---Send the service's collections with change applied. change maps
---collection IDs to new paths, or false for deletions. Throws on failure.
---@param publishSettings table
---@param service any LrPublishService
---@param change table<number, string[]|false>
local function syncCollections(publishSettings, service, change)
	-- Lightroom has not applied the callback's change to the catalog yet.
	-- In Classic 15, getParent() still returned the old set during a move
	-- callback and two seconds later. Override those stale paths with change.
	local collections = {}
	for _, c in ipairs(collectionsOf(service, {})) do
		local path = change[c.id]
		if path == nil then
			collections[#collections + 1] = c
		elseif path then
			collections[#collections + 1] = { id = c.id, path = path }
		end
	end
	local _, err = call(publishSettings, { op = 'publish', service = collections })
	if err then error(err, 0) end
end

---Sync a renamed or moved collection or set. info.name and info.parents
---give its new path, with parents ordered outermost first. Logs failures.
---@param hook string for the log
---@param publishSettings table
---@param info table
local function syncMoved(hook, publishSettings, info)
	guarded(hook, function()
		local sets = {}
		for _, parent in ipairs(info.parents or {}) do sets[#sets + 1] = parent.name end
		sets[#sets + 1] = info.name
		local target, change = info.publishedCollection, {}
		if target:type() == 'LrPublishedCollectionSet' then
			for _, c in ipairs(collectionsOf(target, sets)) do change[c.id] = c.path end
		else
			change[target.localIdentifier] = sets
		end
		syncCollections(publishSettings, info.publishService, change)
	end)
end

function provider.renamePublishedCollection(publishSettings, info)
	syncMoved('renamePublishedCollection', publishSettings, info)
end

function provider.reparentPublishedCollection(publishSettings, info)
	syncMoved('reparentPublishedCollection', publishSettings, info)
end

-- Lightroom calls this only when the user deletes photos from the service;
-- otherwise the next publish reports the deletion. Deleting a set calls it
-- once for the set, not for each collection (observed in Classic 15).
function provider.deletePublishedCollection(publishSettings, info)
	guarded('deletePublishedCollection', function()
		local target = info.publishedCollection
		log:trace(string.format('deletePublishedCollection: %s %q', target:type(), tostring(info.name)))
		local change = {}
		if target:type() == 'LrPublishedCollectionSet' then
			for _, c in ipairs(collectionsOf(target, {})) do change[c.id] = false end
		else
			change[target.localIdentifier] = false
		end
		syncCollections(publishSettings, info.publishService, change)
	end)
end

return provider
