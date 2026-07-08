--[[
	AUTO IMPORT BY IVADSIULS
	v1.0.0
]]--

const ScriptEditorService = game:GetService("ScriptEditorService")
const RunService = game:GetService("RunService")

if not RunService:IsEdit() then
	return
end

const Types = require("@self/Types")
const Settings = require("@self/Settings")
const SettingsWindow = require("@self/SettingsWindow")
const getModules = require("@self/getModules")
const parseScript = require("@self/parseScript")
const moduleServices = require("@self/moduleServices")
const services = require("@self/services")

const CALLBACK_ID = "ivads-auto-import"
const PAT_IDENT = `[_%a][_%w]*`
const SETTINGS_ICON = "rbxassetid://107203088937000"
const BOOTSTRAP_DELAY = 0.15

const function isSafeIdentifier(text: string)
	return string.match(text, `^{PAT_IDENT}$`) ~= nil
end

const function getModuleIdentifier(module: ModuleScript)
	local name = module.Name
	if isSafeIdentifier(name) then
		return name
	end

	name = string.gsub(name, "[^_%w]", "")
	if #name == 0 then
		name = "_"
	elseif string.match(string.sub(name, 1, 1), "[^_%a]") then
		name = `_{name}`
	end

	return name
end

const function getModuleProvenance(module: ModuleScript): (Instance, string)
	local root: Instance?
	for _, service in moduleServices do
		if module:IsDescendantOf(service) then
			root = service
			break
		end
	end
	assert(root, "module service not found")

	local path = {}
	local current: Instance = module
	repeat
		const name = current.Name
		local item = `.{name}`
		if not isSafeIdentifier(name) then
			item = string.format("[%q]", name)
		end
		table.insert(path, 1, item)
		current = current.Parent :: Instance -- we know that the instance is rooted
	until current == root

	return root, table.concat(path)
end

const function getPathSegments(root: Instance, target: Instance): { string }
	local path = {}
	local current: Instance = target
	while current ~= root do
		table.insert(path, 1, current.Name)
		current = current.Parent :: Instance
	end

	return path
end

const function getLocalPathExpression(origin: LuaSourceContainer, target: ModuleScript): string
	const originPath = string.split(origin:GetFullName(), ".")
	const targetPath = string.split(target:GetFullName(), ".")

	local commonLen = 0
	const minLen = math.min(#originPath, #targetPath)
	for i = 1, minLen do
		if originPath[i] == targetPath[i] then
			commonLen = i
		else
			break
		end
	end

	local expression = "script"
	for _ = commonLen + 1, #originPath do
		expression ..= ".Parent"
	end
	for i = commonLen + 1, #targetPath do
		const segment = targetPath[i]
		if isSafeIdentifier(segment) then
			expression ..= `.{segment}`
		else
			expression ..= string.format("[%q]", segment)
		end
	end

	return expression
end

const function getGlobalStringPath(service: Instance, module: ModuleScript): string
	const segments = getPathSegments(service, module)
	table.insert(segments, 1, service.Name)
	return `@game/{table.concat(segments, "/")}`
end

const function escapePattern(text: string): string
	return string.gsub(text, "([^%w])", "%%%1")
end

const function matchTopLevelDeclaration(line: string, rightHandPattern: string): (string?, string?, string?)
	for _, declaration in { "local", "const" } do
		const prefix = `^({declaration})%s+({PAT_IDENT})%s*=%s*{rightHandPattern}%s*;?%s*`
		local matchedDeclaration, identifier, value = string.match(line, `{prefix}$`)
		if identifier ~= nil then
			return matchedDeclaration, identifier, value
		end

		matchedDeclaration, identifier, value = string.match(line, `{prefix}%-%-.*$`)
		if identifier ~= nil then
			return matchedDeclaration, identifier, value
		end
	end

	return nil, nil, nil
end

const function getRequires(source: string): Types.Requires
	const entries = {}
	const byIdentifier = {}
	for i, line in string.split(source, "\n") do
		const declaration, identifier = matchTopLevelDeclaration(line, "require%s*%b()")

		if declaration ~= nil and identifier ~= nil then
			const entry: Types.RequireEntry = {
				lineNumber = i,
				identifier = identifier,
				declaration = declaration :: "local" | "const",
			}
			table.insert(entries, entry)

			const existing = byIdentifier[identifier]
			if existing == nil or (existing.declaration == "local" and declaration == "const") then
				byIdentifier[identifier] = entry
			end
		end
	end

	return {
		entries = entries,
		byIdentifier = byIdentifier,
	}
end

const function getServiceAcquisitions(source: string): Types.ServiceAcquisitions
	const entries = {}
	const byServiceName = {}
	for i, line in string.split(source, "\n") do
		const declaration, identifier, call = matchTopLevelDeclaration(
			line,
			"game%s*:%s*GetService%s*(%b())"
		)

		if declaration ~= nil and identifier ~= nil and call ~= nil then
			const serviceName = string.match(call, `^%(%s*["']([_%w]+)["']%s*%)$`)
			if serviceName == nil then
				continue
			end

			const entry: Types.ServiceAcquisitionEntry = {
				lineNumber = i,
				identifier = identifier,
				serviceName = serviceName,
				declaration = declaration :: "local" | "const",
			}
			table.insert(entries, entry)

			const existing = byServiceName[serviceName]
			if
				existing == nil
				or (
					existing.identifier == identifier
					and existing.declaration == "local"
					and declaration == "const"
				)
			then
				byServiceName[serviceName] = entry
			end
		end
	end

	return {
		entries = entries,
		byServiceName = byServiceName,
	}
end

const function isInLongRange(pos: Types.Position, range: Types.Range): boolean
	const p0 = range.start
	const p1 = range["end"]
	if
		pos.line == p0.line
		and pos.character >= p0.character
		and (pos.line < p1.line or pos.character <= p1.character)
	then
		return true -- first-line
	elseif
		pos.line == p1.line
		and pos.character <= p1.character
		and (pos.line > p0.line or pos.character >= p0.character)
	then
		return true -- last-line
	elseif pos.line > p0.line and pos.line < p1.line then
		return true -- mid-lines
	end
	return false
end

const function isInComment(pos: Types.Position, comment: Types.Comment): boolean
	const range = comment.range
	if comment.kind == "simple" then
		return pos.line == range.start.line and pos.character >= range.start.character
	end
	return isInLongRange(pos, range)
end

const function isInString(pos: Types.Position, str: Types.String): boolean
	const range = str.range
	if str.kind == "quoted" then
		const p0 = range.start
		const p1 = range["end"]
		return pos.line == p0.line and pos.character >= p0.character and pos.character <= p1.character
	end
	return isInLongRange(pos, range)
end

const function isNonBlankLine(text: string?)
	return text == nil or string.match(text, "%S") ~= nil
end

const function getImportIdentifier(line: string): string
	return string.match(line, `^%s*%a+%s+({PAT_IDENT})%s*=`) or line
end

const function getImportPath(line: string): string
	return string.match(line, "require%s*%((.+)%)") or string.match(line, "GetService%s*%((.+)%)") or line
end

const function getImportGroup(line: string, importSort: Types.ImportSort): number
	const isConst = string.match(line, "^%s*const%s+") ~= nil
	if importSort == "constantsFirst" then
		return if isConst then 0 else 1
	elseif importSort == "localsFirst" then
		return if isConst then 1 else 0
	end
	return 0
end

const function sortImportLines(a: string, b: string, importSort: Types.ImportSort): boolean
	if importSort == "alphabetical" then
		return a < b
	elseif importSort == "reverseAlphabetical" then
		return a > b
	elseif importSort == "longestLast" then
		if #a == #b then
			return a < b
		end
		return #a < #b
	elseif importSort == "pathFirst" then
		const pathA = getImportPath(a)
		const pathB = getImportPath(b)
		if pathA == pathB then
			return a < b
		end
		return pathA < pathB
	elseif importSort == "pathLast" then
		const pathA = getImportPath(a)
		const pathB = getImportPath(b)
		if pathA == pathB then
			return a < b
		end
		return pathA > pathB
	elseif importSort == "identifierFirst" then
		const identifierA = getImportIdentifier(a)
		const identifierB = getImportIdentifier(b)
		if identifierA == identifierB then
			return a < b
		end
		return identifierA < identifierB
	elseif importSort == "identifierLast" then
		const identifierA = getImportIdentifier(a)
		const identifierB = getImportIdentifier(b)
		if identifierA == identifierB then
			return a < b
		end
		return identifierA > identifierB
	end

	const groupA = getImportGroup(a, importSort)
	const groupB = getImportGroup(b, importSort)
	if groupA ~= groupB then
		return groupA < groupB
	end

	if #a == #b then
		return a < b
	end

	return #a > #b
end

const function finishStatement(source: string, settings: Types.Settings): string
	if settings.semicolons then
		return `{source};`
	end
	return source
end

const function getFirstEntryLine(entries): number?
	local lineNumber: number? = nil
	for _, entry in entries do
		if lineNumber == nil or entry.lineNumber < lineNumber then
			lineNumber = entry.lineNumber
		end
	end

	return lineNumber
end

const function getCommentInsertLine(lines: { string }, comments: { Types.Comment }, needle: string): number?
	for _, comment in comments do
		const text = string.lower(comment.text)
		if string.find(text, needle, 1, true) ~= nil then
			local lineNumber = comment.range["end"].line + 1
			while lines[lineNumber] ~= nil and isNonBlankLine(lines[lineNumber]) == false do
				lineNumber += 1
			end
			return lineNumber
		end
	end

	return nil
end

const function organizeImports(
	lines: { string },
	lastCommentLine: number,
	comments: { Types.Comment },
	requires: Types.Requires,
	acquires: Types.ServiceAcquisitions,
	newAcquire: string?,
	newRequire: string?,
	settings: Types.Settings
): { string }
	const serviceLines = {}
	const requireLines = {}
	const importLineNumbers = {}

	const seenServices = {}
	for _, entry in acquires.entries do
		importLineNumbers[entry.lineNumber] = true

		const key = `{entry.serviceName}:{entry.identifier}`
		const existingIndex = seenServices[key]
		if existingIndex == nil then
			table.insert(serviceLines, lines[entry.lineNumber])
			seenServices[key] = #serviceLines
		elseif entry.declaration == "const" then
			serviceLines[existingIndex] = lines[entry.lineNumber]
		end
	end

	const seenRequires = {}
	for _, entry in requires.entries do
		importLineNumbers[entry.lineNumber] = true

		const existingIndex = seenRequires[entry.identifier]
		if existingIndex == nil then
			table.insert(requireLines, lines[entry.lineNumber])
			seenRequires[entry.identifier] = #requireLines
		elseif entry.declaration == "const" then
			requireLines[existingIndex] = lines[entry.lineNumber]
		end
	end

	if newAcquire ~= nil then
		table.insert(serviceLines, newAcquire)
	end
	if newRequire ~= nil then
		table.insert(requireLines, newRequire)
	end

	table.sort(serviceLines, function(a, b)
		return sortImportLines(a, b, settings.importSort)
	end)
	table.sort(requireLines, function(a, b)
		return sortImportLines(a, b, settings.importSort)
	end)

	local serviceInsertLine = getFirstEntryLine(acquires.entries)
	local requireInsertLine = getFirstEntryLine(requires.entries)
	if serviceInsertLine == nil and newAcquire ~= nil then
		serviceInsertLine = getCommentInsertLine(lines, comments, "service") or requireInsertLine or lastCommentLine + 1
	end
	if requireInsertLine == nil and newRequire ~= nil then
		requireInsertLine = getCommentInsertLine(lines, comments, "module")
			or getCommentInsertLine(lines, comments, "require")
			or lastCommentLine + 1
	end

	const organizedLines = {}
	local serviceWritten = false
	local requireWritten = false
	for lineNumber, line in lines do
		if lineNumber == serviceInsertLine and not serviceWritten then
			for _, serviceLine in serviceLines do
				table.insert(organizedLines, serviceLine)
			end
			serviceWritten = true
		end
		if lineNumber == requireInsertLine and not requireWritten then
			for _, requireLine in requireLines do
				table.insert(organizedLines, requireLine)
			end
			requireWritten = true
		end

		if importLineNumbers[lineNumber] ~= true then
			table.insert(organizedLines, line)
		end
	end

	if not serviceWritten then
		for _, serviceLine in serviceLines do
			table.insert(organizedLines, serviceLine)
		end
	end
	if not requireWritten then
		for _, requireLine in requireLines do
			table.insert(organizedLines, requireLine)
		end
	end

	return organizedLines
end

const toolbar = plugin:CreateToolbar("CodeKit")
const settingsButton = toolbar:CreateButton("Settings", "CodeKit Settings", SETTINGS_ICON)
const settingsStore = Settings.create(plugin)
local connections: { RBXScriptConnection } = {}
local settingsWindow = nil
local bootstrapQueued = false
local unloading = false
local lastAutocompleteError = ""

settingsButton.Click:Connect(function()
	if settingsWindow == nil then
		settingsWindow = SettingsWindow.create(plugin, settingsStore)
	end
	settingsWindow.toggle()
end)

const function getRelativePath(origin: Instance, target: Instance): string?
	const originPath = string.split(origin:GetFullName(), ".")
	const targetPath = string.split(target:GetFullName(), ".")

	-- Find common prefix
	local commonLen = 0
	const minLen = math.min(#originPath, #targetPath)
	for i = 1, minLen do
		if originPath[i] == targetPath[i] then
			commonLen = i
		else
			break
		end
	end

	-- If no common root (e.g. different DataModel service roots?), technically standard require can't do string path across services easily unless mapped.
	-- But let's assume standard Rojo structure where everything is under a logical root.
	-- If no common root, we assume they share the DataModel root.
	-- commonLen can be 0.

	-- Up steps: ancestors of origin to reach LCA.
	-- originPath includes the script itself.
	-- relative to script's directory.
	-- e.g. A.B.C (Script). Parent is B.
	-- Sibling A.B.D. Common is A.B (2).
	-- #originPath = 3. 
	-- upSteps sentinels: "./" (0 up), "../" (1 up).
	-- We want to reach A.B.
	-- From A.B.C: parent is A.B.
	-- We are AT A.B.C.
	-- To get to sibling D, path is "./D".
	-- Logic: #originPath - commonLen - 1.
	-- 3 - 2 - 1 = 0. Correct.

	const upSteps = #originPath - commonLen - 1
	
	local parts = {}
	if upSteps <= 0 then
		-- origin is ancestor of target. e.g. A -> A.B
		-- common A (1). origin (1).
		-- 1 - 1 - 1 = -1.
		-- "./B".
		table.insert(parts, ".")
	else
		for _ = 1, upSteps do
			table.insert(parts, "..")
		end
	end

	-- Down steps from LCA (exclusive) to target
	for i = commonLen + 1, #targetPath do
		table.insert(parts, targetPath[i])
	end

	return table.concat(parts, "/")
end

const autocomplete: Types.AutocompleteCallback = function(request, response)
	const settings = settingsStore.get()
	if not settings.enabled then
		return response
	end

	const origin = request.textDocument
	if origin.script == nil or origin.document == nil or origin.document:IsCommandBar() then
		return response
	end

	const position = request.position
	const slice = origin.document:GetText(1, 1, position.line, position.character)

	local triggerText: string?
	if settings.prefix == "" then
		triggerText = string.match(slice, `({PAT_IDENT})$`)
	else
		triggerText = string.match(slice, `{escapePattern(settings.prefix)}({PAT_IDENT})$`)
	end
	if not triggerText then
		return response
	end

	if settings.prefix ~= "" then
		const beforePrefixIndex = #slice - #triggerText - #settings.prefix
		if beforePrefixIndex > 0 then
			const charBefore = string.sub(slice, beforePrefixIndex, beforePrefixIndex)
			if string.match(charBefore, "[%w_]") then
				return response
			end
		end
	end

	const trigger = triggerText

	const guardLexemes = parseScript(slice)

	for _, comment in guardLexemes.comments do
		if isInComment(position, comment) then
			return response
		end
	end
	for _, str in guardLexemes.strings do
		if isInString(position, str) then
			return response
		end
	end

	const patchLines = string.split(slice, "\n")
	const line = patchLines[position.line]
	const triggerStartCharacter = position.character - #trigger - #settings.prefix
	if line == nil or triggerStartCharacter < 1 then
		return response
	end

	const patchRange = {
		start = { line = 1, character = 1 },
		["end"] = {
			line = position.line,
			character = position.character,
		},
	}

	patchLines[position.line] = string.sub(line, 1, triggerStartCharacter - 1)
	const patchSource = table.concat(patchLines, "\n")
	const patchLexemes = parseScript(patchSource)

	local lastCommentLine = 0
	for _, comment in patchLexemes.comments do
		if comment.header == true then
			lastCommentLine = comment.range["end"].line
		end
	end

	const requires = getRequires(patchSource)
	const acquires = getServiceAcquisitions(patchSource)

	const items = table.clone(response.items)

	const function getNewText(identifier: string, acquireSource: string?, requireSource: string?): string
		const lines = table.clone(patchLines)
		lines[position.line] = string.sub(line, 1, triggerStartCharacter - 1) .. identifier
		const newLines = organizeImports(
			lines,
			lastCommentLine,
			patchLexemes.comments,
			requires,
			acquires,
			acquireSource,
			requireSource,
			settings
		)
		return table.concat(newLines, "\n")
	end

	if settings.autoModules then
		for _, module in getModules(origin.script, settings) do
			const identifier = getModuleIdentifier(module)
			if requires.byIdentifier[identifier] ~= nil then
				continue
			end

			const service, path = getModuleProvenance(module)

			local serviceIdentifier = service.Name
			local acquireSource: string? = nil
			local requirePath = ""
			if settings.requireMode == "local" then
				if settings.stringRequires then
					requirePath = string.format("%q", getRelativePath(origin.script, module))
				else
					requirePath = getLocalPathExpression(origin.script, module)
				end
			elseif settings.stringRequires then
				requirePath = string.format("%q", getGlobalStringPath(service, module))
			else
				if acquires.byServiceName[serviceIdentifier] ~= nil then
					serviceIdentifier = acquires.byServiceName[serviceIdentifier].identifier
				else
					acquireSource = finishStatement(
						`{settings.keyword} {serviceIdentifier} = game:GetService("{serviceIdentifier}")`,
						settings
					)
				end
				requirePath = `{serviceIdentifier}{path}`
			end

			const requireSource = finishStatement(`{settings.keyword} {identifier} = require({requirePath})`, settings)

			table.insert(items, {
				label = module.Name,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "Auto-require" },
				detail = module:GetFullName(),
				textEdit = {
					newText = getNewText(identifier, acquireSource, requireSource),
					insert = patchRange,
					replace = patchRange,
				},
			})
		end
	end

	if settings.autoServices then
		local seenServices = {}
		for _, service in services do
			const identifier = service.name
			seenServices[identifier] = true
			if acquires.byServiceName[identifier] ~= nil then
				continue
			end

			const acquireSource = finishStatement(`{settings.keyword} {identifier} = game:GetService("{identifier}")`, settings)

			table.insert(items, {
				label = identifier,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "Auto-service" },
				detail = "Service",
				learnMoreLink = `https://create.roblox.com/docs/reference/engine/classes/{identifier}`,
				textEdit = {
					newText = getNewText(identifier, acquireSource, nil),
					insert = patchRange,
					replace = patchRange,
				},
			})
		end

		for _, identifier in settings.additionalServices do
			if seenServices[identifier] or acquires.byServiceName[identifier] ~= nil then
				continue
			end
			seenServices[identifier] = true

			const acquireSource = finishStatement(`{settings.keyword} {identifier} = game:GetService("{identifier}")`, settings)

			table.insert(items, {
				label = identifier,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "Auto-service" },
				detail = "Additional Service",
				textEdit = {
					newText = getNewText(identifier, acquireSource, nil),
					insert = patchRange,
					replace = patchRange,
				},
			})
		end
	end

	return {
		items = items,
	}
end

const function deregisterAutocomplete()
	pcall(function()
		ScriptEditorService:DeregisterAutocompleteCallback(CALLBACK_ID)
	end)
end

const function queueAutocompleteBootstrap()
	if unloading or bootstrapQueued then
		return
	end

	bootstrapQueued = true
	task.delay(BOOTSTRAP_DELAY, function()
		bootstrapQueued = false
		if unloading then
			return
		end

		deregisterAutocomplete()

		const registered = pcall(function()
			ScriptEditorService:RegisterAutocompleteCallback(CALLBACK_ID, 1, function(request, response)
				const ok, result = pcall(autocomplete, request, response)
				if ok then
					return result
				end

				const message = tostring(result)
				if message ~= lastAutocompleteError then
					lastAutocompleteError = message
					warn(`CodeKit autocomplete recovered: {message}`)
				end
				queueAutocompleteBootstrap()
				return response
			end)
		end)

		if not registered then
			queueAutocompleteBootstrap()
		end
	end)
end

queueAutocompleteBootstrap()

table.insert(connections, settingsStore.changed:Connect(queueAutocompleteBootstrap))
table.insert(connections, ScriptEditorService.TextDocumentDidOpen:Connect(queueAutocompleteBootstrap))
table.insert(connections, ScriptEditorService.TextDocumentDidClose:Connect(queueAutocompleteBootstrap))

for _, service in moduleServices do
	table.insert(connections, service.DescendantAdded:Connect(function(instance)
		if instance:IsA("ModuleScript") then
			queueAutocompleteBootstrap()
		end
	end))
	table.insert(connections, service.DescendantRemoving:Connect(function(instance)
		if instance:IsA("ModuleScript") then
			queueAutocompleteBootstrap()
		end
	end))
end

plugin.Unloading:Connect(function()
	unloading = true
	for _, connection in connections do
		connection:Disconnect()
	end
	deregisterAutocomplete()
	if settingsWindow ~= nil then
		settingsWindow.destroy()
	end
	settingsStore.destroy()
end)
