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
const Snippets = require("@self/Snippets")
const SettingsWindow = require("@self/SettingsWindow")
const SnippetsWindow = require("@self/SnippetsWindow")
const ThemesWindow = require("@self/ThemesWindow")
const getModules = require("@self/getModules")
const parseScript = require("@self/parseScript")
const moduleServices = require("@self/moduleServices")
const services = require("@self/services")

const CALLBACK_ID = "ivads-auto-import"
const PAT_IDENT = `[_%a][_%w]*`
const SETTINGS_ICON = "rbxassetid://107203088937000"
const SNIPPETS_ICON = "rbxassetid://78322934048581"
const THEMES_ICON = "rbxassetid://90425432902432"
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

const function getImportIdentifierFromInstance(instance: Instance): string
	local name = instance.Name
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

const function getPathSegmentExpression(name: string): string
	if isSafeIdentifier(name) then
		return `.{name}`
	end
	return string.format("[%q]", name)
end

const function getDataModelRoot(instance: Instance): Instance?
	local current: Instance = instance
	while current.Parent ~= nil and current.Parent ~= game do
		current = current.Parent :: Instance
	end
	return if current.Parent == game then current else nil
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

const function getFolderDepthLimit(settings: Types.Settings): number
	if settings.importFolderDepth == "All" then
		return math.huge
	elseif settings.importFolderDepth == "First Two" then
		return 2
	end
	return 1
end

const function getFolderImports(root: Instance, target: Instance, rootIdentifier: string, settings: Types.Settings)
	if not settings.autoFolders then
		return {}, rootIdentifier
	end

	const parent = target.Parent
	if parent == nil or parent == root then
		return {}, rootIdentifier
	end

	const folders = {}
	local current: Instance = parent
	while current ~= root do
		if current:IsA("Folder") then
			table.insert(folders, 1, current)
		end
		current = current.Parent :: Instance
	end

	const folderLines = {}
	local expression = rootIdentifier
	const depthLimit = getFolderDepthLimit(settings)
	for index, folder in folders do
		if index > depthLimit then
			break
		end

		const identifier = getImportIdentifierFromInstance(folder)
		expression ..= getPathSegmentExpression(folder.Name)
		table.insert(folderLines, finishStatement(`{settings.keyword} {identifier} = {expression}`, settings))
		expression = identifier
	end

	for index = math.min(#folders, depthLimit) + 1, #folders do
		expression ..= getPathSegmentExpression(folders[index].Name)
	end

	return folderLines, expression
end

const function expandSnippet(source: string, origin: LuaSourceContainer, trigger: string): string
	local expanded = source
	expanded = string.gsub(expanded, "%${scriptName}", origin.Name)
	expanded = string.gsub(expanded, "%${trigger}", trigger)
	expanded = string.gsub(expanded, "%${%d+:([^}]-)}", "%1")
	return expanded
end

const function getReplaceRange(position: Types.Position, triggerStartCharacter: number): Types.Range
	return {
		start = { line = position.line, character = triggerStartCharacter },
		["end"] = { line = position.line, character = position.character },
	}
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

const IMPORT_TOKENS = {
	["[services]"] = true,
	["[modules]"] = true,
	["[folders]"] = true,
	["[remotes]"] = true,
}

const function getLayoutGroups(layout: string)
	const groups = {}
	local pendingLines = {}

	for _, layoutLine in string.split(layout, "\n") do
		const trimmed = string.gsub(layoutLine, "^%s*(.-)%s*$", "%1")
		if IMPORT_TOKENS[trimmed] == true then
			table.insert(groups, {
				token = trimmed,
				prefix = pendingLines,
			})
			pendingLines = {}
		else
			table.insert(pendingLines, layoutLine)
		end
	end

	return groups
end

const function getManagedImportLines(settings: Types.Settings)
	const managed = {}
	for _, group in getLayoutGroups(settings.importLayout) do
		managed[group.token] = true
		for _, line in group.prefix do
			if line ~= "" then
				managed[line] = true
			end
		end
	end
	return managed
end

const function appendTrimmedGroup(importBlock: { string }, prefix: { string }, bucket: { string })
	if #bucket == 0 then
		return
	end

	while #prefix > 0 and prefix[1] == "" do
		table.remove(prefix, 1)
	end
	while #prefix > 0 and prefix[#prefix] == "" do
		table.remove(prefix, #prefix)
	end

	if #importBlock > 0 then
		table.insert(importBlock, "")
	end
	for _, line in prefix do
		table.insert(importBlock, line)
	end
	for _, line in bucket do
		table.insert(importBlock, line)
	end
end

const function organizeImports(
	lines: { string },
	lastCommentLine: number,
	comments: { Types.Comment },
	requires: Types.Requires,
	acquires: Types.ServiceAcquisitions,
	newAcquire: string?,
	newRequire: string?,
	newFolderLines: { string }?,
	newRemote: string?,
	settings: Types.Settings
): { string }
	const serviceLines = {}
	const requireLines = {}
	const folderLines = {}
	const remoteLines = {}
	const importLineNumbers = {}
	const managedImportLines = getManagedImportLines(settings)

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
	if newFolderLines ~= nil then
		for _, folderLine in newFolderLines do
			table.insert(folderLines, folderLine)
		end
	end
	if newRemote ~= nil then
		table.insert(remoteLines, newRemote)
	end

	table.sort(serviceLines, function(a, b)
		return sortImportLines(a, b, settings.importSort)
	end)
	table.sort(requireLines, function(a, b)
		return sortImportLines(a, b, settings.importSort)
	end)
	table.sort(folderLines, function(a, b)
		return sortImportLines(a, b, settings.importSort)
	end)
	table.sort(remoteLines, function(a, b)
		return sortImportLines(a, b, settings.importSort)
	end)

	const tokenLines = {
		["[services]"] = serviceLines,
		["[modules]"] = requireLines,
		["[folders]"] = folderLines,
		["[remotes]"] = remoteLines,
	}
	local wroteToken = {}
	const importBlock = {}

	for _, group in getLayoutGroups(settings.importLayout) do
		wroteToken[group.token] = true
		appendTrimmedGroup(importBlock, table.clone(group.prefix), tokenLines[group.token])
	end

	for token, bucket in tokenLines do
		if wroteToken[token] then
			continue
		end
		for _, importLine in bucket do
			table.insert(importBlock, importLine)
		end
	end

	while #importBlock > 0 and importBlock[1] == "" do
		table.remove(importBlock, 1)
	end
	while #importBlock > 0 and importBlock[#importBlock] == "" do
		table.remove(importBlock, #importBlock)
	end

	const function isManagedLine(lineNumber: number, line: string): boolean
		const trimmed = string.gsub(line, "^%s*(.-)%s*$", "%1")
		return importLineNumbers[lineNumber] == true or managedImportLines[line] == true or IMPORT_TOKENS[trimmed] == true
	end

	local organizedLines = {}
	local insertedImportBlock = #importBlock == 0
	local pendingBlank = false

	organizedLines = {}
	for lineNumber, line in lines do
		if isManagedLine(lineNumber, line) then
			continue
		end

		if lineNumber <= lastCommentLine then
			table.insert(organizedLines, line)
			continue
		end

		if not insertedImportBlock then
			while #organizedLines > 0 and organizedLines[#organizedLines] == "" do
				table.remove(organizedLines, #organizedLines)
			end
			if #organizedLines > 0 then
				table.insert(organizedLines, "")
			end
			for _, importLine in importBlock do
				table.insert(organizedLines, importLine)
			end
			pendingBlank = true
			insertedImportBlock = true
		end

		if pendingBlank then
			if line ~= "" then
				table.insert(organizedLines, "")
			end
			pendingBlank = false
		end

		table.insert(organizedLines, line)
	end

	if not insertedImportBlock then
		while #organizedLines > 0 and organizedLines[#organizedLines] == "" do
			table.remove(organizedLines, #organizedLines)
		end
		if #organizedLines > 0 then
			table.insert(organizedLines, "")
		end
		for _, importLine in importBlock do
			table.insert(organizedLines, importLine)
		end
	end

	return organizedLines
end

const toolbar = plugin:CreateToolbar("CodeKit")
const settingsButton = toolbar:CreateButton("Settings", "CodeKit Settings", SETTINGS_ICON)
const snippetsButton = toolbar:CreateButton("Snippets", "CodeKit Snippets", SNIPPETS_ICON)
const themesButton = toolbar:CreateButton("Themes", "CodeKit Themes", THEMES_ICON)
const settingsStore = Settings.create(plugin)
const snippetsStore = Snippets.create(plugin)
local connections: { RBXScriptConnection } = {}
local settingsWindow = nil
local snippetsWindow = nil
local themesWindow = nil
local bootstrapQueued = false
local unloading = false
local lastAutocompleteError = ""

settingsButton.Click:Connect(function()
	if settingsWindow == nil then
		settingsWindow = SettingsWindow.create(plugin, settingsStore)
	end
	settingsWindow.toggle()
end)

snippetsButton.Click:Connect(function()
	if snippetsWindow == nil then
		snippetsWindow = SnippetsWindow.create(plugin, snippetsStore)
	end
	snippetsWindow.toggle()
end)

themesButton.Click:Connect(function()
	if themesWindow == nil then
		themesWindow = ThemesWindow.create(plugin)
	end
	themesWindow.toggle()
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

	const function getNewText(
		identifier: string,
		acquireSource: string?,
		requireSource: string?,
		folderSources: { string }?,
		remoteSource: string?
	): string
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
			folderSources,
			remoteSource,
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
			local folderSources = {}
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
				local baseExpression = serviceIdentifier
				folderSources, baseExpression = getFolderImports(service, module, serviceIdentifier, settings)
				requirePath = `{baseExpression}{getPathSegmentExpression(module.Name)}`
			end

			const requireSource = finishStatement(`{settings.keyword} {identifier} = require({requirePath})`, settings)

			table.insert(items, {
				label = module.Name,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "Auto-require" },
				detail = module:GetFullName(),
				textEdit = {
					newText = getNewText(identifier, acquireSource, requireSource, folderSources, nil),
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
					newText = getNewText(identifier, acquireSource, nil, nil, nil),
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
					newText = getNewText(identifier, acquireSource, nil, nil, nil),
					insert = patchRange,
					replace = patchRange,
				},
			})
		end
	end

	if settings.autoRemotes or settings.autoFolders then
		const normalizedTrigger = string.lower(trigger)
		for _, instance in game:GetDescendants() do
			local detail: string? = nil
			local importSource: string? = nil
			local folderSources = {}
			local acquireSource: string? = nil
			local completionText = instance.Name
			if settings.autoRemotes and (instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction")) then
				detail = instance.ClassName
			elseif settings.autoFolders and instance:IsA("Folder") then
				detail = "Folder"
			end

			if detail == nil or string.find(string.lower(instance.Name), normalizedTrigger, 1, true) ~= 1 then
				continue
			end

			const editRange = getReplaceRange(position, triggerStartCharacter)
			const root = getDataModelRoot(instance)
			if root ~= nil then
				local rootIdentifier = root.Name
				if acquires.byServiceName[rootIdentifier] ~= nil then
					rootIdentifier = acquires.byServiceName[rootIdentifier].identifier
				else
					acquireSource = finishStatement(
						`{settings.keyword} {rootIdentifier} = game:GetService("{rootIdentifier}")`,
						settings
					)
				end

				local baseExpression = rootIdentifier
				folderSources, baseExpression = getFolderImports(root, instance, rootIdentifier, settings)
				const identifier = getImportIdentifierFromInstance(instance)
				completionText = identifier
				if instance:IsA("Folder") then
					importSource = finishStatement(
						`{settings.keyword} {identifier} = {baseExpression}{getPathSegmentExpression(instance.Name)}`,
						settings
					)
					table.insert(folderSources, importSource)
					importSource = nil
				else
					importSource = finishStatement(
						`{settings.keyword} {identifier} = {baseExpression}{getPathSegmentExpression(instance.Name)}`,
						settings
					)
				end
			end

			table.insert(items, {
				label = instance.Name,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = `CodeKit {detail}` },
				detail = instance:GetFullName(),
				textEdit = {
					newText = if importSource ~= nil or #folderSources > 0 or acquireSource ~= nil
						then getNewText(completionText, acquireSource, nil, folderSources, importSource)
						else completionText,
					insert = if importSource ~= nil or #folderSources > 0 or acquireSource ~= nil then patchRange else editRange,
					replace = if importSource ~= nil or #folderSources > 0 or acquireSource ~= nil then patchRange else editRange,
				},
			})
		end
	end

	for _, snippet in snippetsStore.get() do
		const normalizedTrigger = string.lower(trigger)
		const editRange = getReplaceRange(position, triggerStartCharacter)
		const function addSnippetItem(label: string, detail: string)
			table.insert(items, {
				label = label,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = `CodeKit snippet: {snippet.name}` },
				detail = detail,
				textEdit = {
					newText = expandSnippet(snippet.source, origin.script :: LuaSourceContainer, label),
					insert = editRange,
					replace = editRange,
				},
			})
		end

		local addedLabels = {}
		if string.find(string.lower(snippet.name), normalizedTrigger, 1, true) == 1 then
			addedLabels[snippet.name] = true
			addSnippetItem(snippet.name, table.concat(snippet.aliases, ", "))
		end

		for _, alias in snippet.aliases do
			if string.find(string.lower(alias), normalizedTrigger, 1, true) == 1 then
				if addedLabels[alias] == true then
					continue
				end
				addedLabels[alias] = true
				addSnippetItem(alias, snippet.name)
			end
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
table.insert(connections, snippetsStore.changed:Connect(queueAutocompleteBootstrap))
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
	if snippetsWindow ~= nil then
		snippetsWindow.destroy()
	end
	if themesWindow ~= nil then
		themesWindow.destroy()
	end
	settingsStore.destroy()
	snippetsStore.destroy()
end)
