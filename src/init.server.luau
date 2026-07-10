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
const getModules = require("@self/getModules")
const parseScript = require("@self/parseScript")
const moduleServices = require("@self/moduleServices")
const services = require("@self/services")

const CALLBACK_ID = "ivads-auto-import"
const PAT_IDENT = `[_%a][_%w]*`
const SETTINGS_ICON = "rbxassetid://107203088937000"
const BOOTSTRAP_DELAY = 0.15
const DEFINITION_ITEMS = {
	{
		label = "Parent",
		source = "script.Parent",
		detail = "Current script parent",
	},
	{
		label = "Camera",
		source = "Workspace.CurrentCamera",
		detail = "Workspace.CurrentCamera",
		service = "Workspace",
	},
	{
		label = "Player",
		source = "Players.LocalPlayer",
		detail = "Players.LocalPlayer",
		service = "Players",
	},
	{
		label = "Character",
		source = "Player.Character or Player.CharacterAdded:Wait()",
		detail = "Local player character",
		service = "Players",
	},
	{
		label = "Humanoid",
		source = "Character:WaitForChild(\"Humanoid\") :: Humanoid",
		detail = "Character humanoid",
		service = "Players",
	},
}
const QUICK_ACCESS_ITEMS = {
	{ label = "--!strict", detail = "Luau directive", insert = "--!strict" },
	{ label = "--!native", detail = "Luau directive", insert = "--!native" },
	{ label = "--!optimize", detail = "Luau directive", insert = "--!optimize 2" },
	{ label = "--!nonstrict", detail = "Luau directive", insert = "--!nonstrict" },
	{ label = "--!nolint", detail = "Luau nolint", insert = "--!nolint" },
	{ label = "--!nolint DeprecatedApi", detail = "Suppress deprecated API lint", insert = "--!nolint DeprecatedApi" },
	{ label = "--!nolint GlobalUsedAsLocal", detail = "Suppress global-used-as-local lint", insert = "--!nolint GlobalUsedAsLocal" },
	{ label = "--!nolint LocalShadow", detail = "Suppress local-shadow lint", insert = "--!nolint LocalShadow" },
	{ label = "@checked", detail = "Function attribute", insert = "@checked" },
	{ label = "@native", detail = "Function attribute", insert = "@native" },
	{ label = "@deprecated", detail = "Function attribute", insert = "@deprecated" },
}

const function isSafeIdentifier(text: string)
	return string.match(text, `^{PAT_IDENT}$`) ~= nil
end

const function quoteString(text: string, settings: Types.Settings): string
	if settings.stringQuote == "single" and string.find(text, "'", 1, true) == nil then
		return `'{text}'`
	end
	return string.format("%q", text)
end

const function getSectionKeyword(sectionSettings: Types.SectionSettings, fallback: Types.Settings): Types.Keyword
	return if sectionSettings.useConst then "const" else "local"
end

const function toSnakeCase(text: string): string
	local result = string.gsub(text, "(%u)", "_%1")
	result = string.gsub(result, "^_", "")
	result = string.gsub(result, "[^_%w]+", "_")
	return string.lower(result)
end

const function applyCasing(text: string, casing: Types.Casing): string
	if casing == "camel" then
		return string.lower(string.sub(text, 1, 1)) .. string.sub(text, 2)
	elseif casing == "pascal" then
		return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
	elseif casing == "snake" then
		return toSnakeCase(text)
	end
	return text
end

const function getAliasMap(values: { string }): { [string]: string }
	const aliases = {}
	for _, value in values do
		const sourceName, alias = string.match(value, "^%s*([^=:%s]+)%s*[=:]%s*([_%a][_%w]*)%s*$")
		if sourceName ~= nil and alias ~= nil then
			aliases[sourceName] = alias
		end
	end
	return aliases
end

const function getModuleIdentifier(module: ModuleScript, settings: Types.Settings)
	local customName = module:GetAttribute(settings.customNameAttribute)
	local name = if typeof(customName) == "string" and customName ~= "" then customName else module.Name
	name = applyCasing(name, settings.modules.casing)
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

const function getImportIdentifierFromInstance(instance: Instance, settings: Types.Settings): string
	local customName = instance:GetAttribute(settings.customNameAttribute)
	local name = if typeof(customName) == "string" and customName ~= "" then customName else instance.Name
	name = applyCasing(name, settings.instances.casing)
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

const function getDefinitionIdentifier(label: string, settings: Types.Settings): string
	return applyCasing(label, settings.definitions.casing)
end

const function isNoImport(instance: Instance, settings: Types.Settings): boolean
	const tagValue = instance:GetAttribute(settings.noImportTag)
	return tagValue == true
end

const function getPathSegmentExpression(name: string): string
	if isSafeIdentifier(name) then
		return `.{name}`
	end
	return string.format("[%q]", name)
end

const function getInstanceIndexExpression(baseExpression: string, instance: Instance, mode: Types.IndexingMode, settings: Types.Settings): string
	if mode == "WaitForChild" then
		return `{baseExpression}:WaitForChild({quoteString(instance.Name, settings)})`
	elseif mode == "FindFirstChild" then
		return `{baseExpression}:FindFirstChild({quoteString(instance.Name, settings)})`
	end
	return `{baseExpression}{getPathSegmentExpression(instance.Name)}`
end

const function getScriptIndexingMode(origin: LuaSourceContainer?, settings: Types.Settings): Types.IndexingMode
	if origin ~= nil and origin:IsA("LocalScript") then
		return settings.indexing.clientScripts
	end
	return settings.indexing.serverScripts
end

const function getScriptRequireMode(origin: LuaSourceContainer, settings: Types.Settings): Types.RequireMode
	local mode = if origin:IsA("LocalScript") then settings.modules.clientScriptsRequire else settings.modules.serverScriptsRequire
	if mode == "relative" then
		return "local"
	elseif mode == "absolute" then
		return "global"
	end
	return settings.requireMode
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
		const prefix = `^%s*({declaration})%s+({PAT_IDENT})%s*=%s*{rightHandPattern}%s*;?%s*`
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

const function getImportExpression(line: string): string
	const call = string.match(line, "require%s*(%b())")
	if call ~= nil then
		return string.sub(call, 2, -2)
	end
	return string.match(line, "=%s*(.-)%s*;?%s*$") or ""
end

const function getImportSegments(line: string): { string }
	const segments = {}
	for segment in string.gmatch(getImportExpression(line), "[_%w]+") do
		if segment ~= "game" and segment ~= "script" and segment ~= "require" and segment ~= "GetService" then
			table.insert(segments, string.lower(segment))
		end
	end
	return segments
end

const function getImportNameWords(identifier: string): { [string]: boolean }
	const words = {}
	const separated = string.gsub(identifier, "([%l%d])([%u])", "%1 %2")
	for word in string.gmatch(string.lower(separated), "[%a%d]+") do
		words[word] = true
	end
	return words
end

const function getImportGroupEnd(entries, entryIndex: number): number
	local groupEnd = entries[entryIndex].lineNumber
	for nextIndex = entryIndex + 1, #entries do
		if entries[nextIndex].lineNumber ~= groupEnd + 1 then
			break
		end
		groupEnd = entries[nextIndex].lineNumber
	end
	return groupEnd
end

const function getImportSimilarity(newLine: string, existingLine: string, newIdentifier: string, existingIdentifier: string): number
	const newSegments = getImportSegments(newLine)
	const existingSegments = getImportSegments(existingLine)
	local score = 0
	local commonPrefix = 0
	for index = 1, math.min(#newSegments, #existingSegments) do
		if newSegments[index] ~= existingSegments[index] then
			break
		end
		commonPrefix += 1
	end
	score += commonPrefix * 12
	if #newSegments > 0 and #existingSegments > 0 and newSegments[#newSegments] == existingSegments[#existingSegments] then
		score += 8
	end

	const newWords = getImportNameWords(newIdentifier)
	const existingWords = getImportNameWords(existingIdentifier)
	for word in newWords do
		if existingWords[word] then
			score += 5
		end
	end

	return score
end

const function getSmartImportInsertionIndex(lines: { string }, entries, newLine: string, fallback: number): number
	if #entries == 0 then
		return fallback
	end

	const _, newIdentifier = matchTopLevelDeclaration(newLine, "require%s*%b()")
	local bestIndex: number? = nil
	local bestScore = 0
	for entryIndex, entry in entries do
		const existingLine = lines[entry.lineNumber]
		const score = getImportSimilarity(newLine, existingLine, newIdentifier or "", entry.identifier)
		if score > bestScore then
			bestScore = score
			bestIndex = entryIndex
		end
	end

	if bestIndex == nil then
		return fallback
	end
	return getImportGroupEnd(entries, bestIndex :: number) + 1
end

const function insertDuckableImports(
	lines: { string },
	requires: Types.Requires,
	acquires: Types.ServiceAcquisitions,
	newAcquire: string?,
	newRequire: string?,
	newFolderLines: { string }?,
	newRemote: string?,
	importLayout: string
): { string }
	if newAcquire == nil and newRequire == nil and newFolderLines == nil and newRemote == nil then
		return lines
	end

	local firstRequireLine = math.huge
	local lastRequireLine = 0
	for _, entry in requires.entries do
		firstRequireLine = math.min(firstRequireLine, entry.lineNumber)
		lastRequireLine = math.max(lastRequireLine, entry.lineNumber)
	end
	if firstRequireLine == math.huge then
		firstRequireLine = 0
	end

	local firstAcquireLine = math.huge
	local lastAcquireLine = 0
	for _, entry in acquires.entries do
		firstAcquireLine = math.min(firstAcquireLine, entry.lineNumber)
		lastAcquireLine = math.max(lastAcquireLine, entry.lineNumber)
	end
	if firstAcquireLine == math.huge then
		firstAcquireLine = 0
	end

	const lastImportLine = math.max(lastRequireLine, lastAcquireLine)
	const insertions = {}

	const function queue(index: number, line: string)
		if insertions[index] == nil then
			insertions[index] = {}
		end
		table.insert(insertions[index], line)
	end

	const layoutGroups = getLayoutGroups(importLayout)
	const function getLayoutPrefix(token: string): { string }?
		for _, group in layoutGroups do
			if group.token == token then
				return group.prefix
			end
		end
		return nil
	end

	const function hasLayoutPrefix(prefix: { string }): boolean
		local start = 1
		while start <= #prefix and prefix[start] == "" do
			start += 1
		end
		if start > #prefix then
			return false
		end

		local foundMarker = false
		for prefixIndex = start, #prefix do
			const expected = string.gsub(prefix[prefixIndex], "^%s*(.-)%s*$", "%1")
			if expected == "" then
				continue
			end
			foundMarker = true
			local foundLine = false
			for _, line in lines do
				const actual = string.gsub(line, "^%s*(.-)%s*$", "%1")
				if actual == expected then
					foundLine = true
					break
				end
			end
			if not foundLine then
				return false
			end
		end
		return foundMarker
	end

	const function queueLayout(token: string, index: number)
		const prefix = getLayoutPrefix(token)
		if prefix == nil or hasLayoutPrefix(prefix) then
			return
		end

		local start = 1
		while start <= #prefix and prefix[start] == "" do
			start += 1
		end
		if start > #prefix then
			return
		end
		local finish = #prefix
		while finish >= start and prefix[finish] == "" do
			finish -= 1
		end
		if index > 1 and lines[index - 1] ~= "" then
			queue(index, "")
		end
		for prefixIndex = start, finish do
			queue(index, prefix[prefixIndex])
		end
	end

	if newAcquire ~= nil then
		const fallback = if lastAcquireLine > 0 then lastAcquireLine + 1 else firstRequireLine
		const insertionIndex = getSmartImportInsertionIndex(lines, acquires.entries, newAcquire, fallback)
		const actualInsertionIndex = if insertionIndex > 0 then insertionIndex else lastImportLine + 1
		queueLayout("[services]", if firstAcquireLine > 0 then firstAcquireLine else actualInsertionIndex)
		queue(actualInsertionIndex, newAcquire)
		if firstRequireLine > 0 and lastAcquireLine == 0 and lines[insertionIndex] ~= "" then
			queue(insertionIndex, "")
		elseif firstRequireLine > lastAcquireLine and lines[insertionIndex] ~= "" then
			queue(insertionIndex, "")
		end
	end

	if newFolderLines ~= nil and #newFolderLines > 0 then
		const insertionIndex = getSmartImportInsertionIndex(
			lines,
			requires.entries,
			newFolderLines[1],
			if firstRequireLine > 0 then firstRequireLine else lastImportLine + 1
		)
		queueLayout("[folders]", insertionIndex)
		for _, folderLine in newFolderLines do
			queue(insertionIndex, folderLine)
		end
	end

	if newRequire ~= nil then
		const insertionIndex = getSmartImportInsertionIndex(
			lines,
			requires.entries,
			newRequire,
			if lastRequireLine > 0
				then lastRequireLine + 1
				elseif lastAcquireLine > 0
					then lastAcquireLine + 1
					else lastImportLine + 1
		)
		queueLayout("[modules]", if firstRequireLine > 0 then firstRequireLine else insertionIndex)
		if lastRequireLine == 0 and lastAcquireLine > 0 and lines[insertionIndex] ~= "" then
			queue(insertionIndex, "")
		end
		queue(insertionIndex, newRequire)
	end

	if newRemote ~= nil then
		const insertionIndex = getSmartImportInsertionIndex(lines, requires.entries, newRemote, lastImportLine + 1)
		queueLayout("[remotes]", insertionIndex)
		queue(insertionIndex, newRemote)
	end

	const duckedLines = {}
	for lineNumber, line in lines do
		const queuedLines = insertions[lineNumber]
		if queuedLines ~= nil then
			for _, queuedLine in queuedLines do
				table.insert(duckedLines, queuedLine)
			end
		end
		table.insert(duckedLines, line)
	end
	const tailLines = insertions[#lines + 1]
	if tailLines ~= nil then
		for _, queuedLine in tailLines do
			table.insert(duckedLines, queuedLine)
		end
	end
	return duckedLines
end

type ModuleSnapshot = {
	name: string,
	path: string,
	parent: Instance?,
}

type RefactorUsage = {
	script: LuaSourceContainer,
	line: number,
	path: string,
	text: string,
	source: string,
	requireArgument: string,
	requireFullName: string?,
	identifier: string,
}

type RefactorEdit = RefactorUsage & {
	newSource: string,
	newIdentifier: string,
	newRequireArgument: string,
}

const function isScript(instance: Instance): boolean
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

const function getSource(scriptInstance: LuaSourceContainer): string
	local sourceText = ""
	local ok = pcall(function()
		sourceText = ScriptEditorService:GetEditorSource(scriptInstance)
	end)
	if ok and sourceText ~= "" then
		return sourceText
	end
	return scriptInstance.Source
end

const function setSource(scriptInstance: LuaSourceContainer, sourceText: string): boolean
	local document = ScriptEditorService:FindScriptDocument(scriptInstance)
	if document ~= nil then
		const lineCount = document:GetLineCount()
		const lastLine = document:GetLine(lineCount)
		const success, message = document:EditTextAsync(sourceText, 1, 1, lineCount, #lastLine + 1)
		if not success then
			warn(`CodeKit refactor edit failed: {message}`)
		end
		return success
	end

	scriptInstance.Source = sourceText
	return true
end

const function splitFullName(path: string): { string }
	return string.split(path, ".")
end

const function getPathFromRelativeRequire(origin: LuaSourceContainer, requirePath: string): string?
	local segments = splitFullName(origin:GetFullName())
	table.remove(segments, #segments)

	for _, segment in string.split(requirePath, "/") do
		if segment == "" or segment == "." then
			continue
		elseif segment == ".." then
			if #segments == 0 then
				return nil
			end
			table.remove(segments, #segments)
		else
			table.insert(segments, segment)
		end
	end

	return table.concat(segments, ".")
end

const function readQuotedRequire(argument: string): string?
	return string.match(argument, "^%s*[\"'](.+)[\"']%s*$")
end

const function getServiceAliases(source: string): { [string]: string }
	const aliases = {}
	for _, line in string.split(source, "\n") do
		const _, identifier, call = matchTopLevelDeclaration(line, "game%s*:%s*GetService%s*(%b())")
		if identifier == nil or call == nil then
			continue
		end

		const serviceName = string.match(call, `^%(%s*["']([_%w]+)["']%s*%)$`)
		if serviceName ~= nil then
			aliases[identifier] = serviceName
		end
	end
	return aliases
end

const function readExpressionToken(expression: string, offset: number): (string?, number)
	const token = string.match(expression, `^({PAT_IDENT})`, offset)
	if token == nil then
		return nil, offset
	end
	return token, offset + #token
end

const function getFullNameFromRequireExpression(origin: LuaSourceContainer, argument: string, source: string): string?
	const quoted = readQuotedRequire(argument)
	if quoted ~= nil then
		if string.find(quoted, "@game/", 1, true) == 1 then
			return string.gsub(string.sub(quoted, 7), "/", ".")
		end
		return getPathFromRelativeRequire(origin, quoted)
	end

	local token, offset = readExpressionToken(argument, 1)
	if token == nil then
		return nil
	end

	local segments: { string }
	const aliases = getServiceAliases(source)
	if aliases[token] ~= nil then
		segments = { aliases[token] }
	elseif token == "game" then
		segments = {}
	elseif token == "script" then
		segments = splitFullName(origin:GetFullName())
	else
		segments = { token }
	end

	while offset <= #argument do
		const char = string.sub(argument, offset, offset)
		if char == "." then
			offset += 1
			local segment
			segment, offset = readExpressionToken(argument, offset)
			if segment == nil then
				return nil
			end
			if segment == "Parent" then
				if #segments == 0 then
					return nil
				end
				table.remove(segments, #segments)
			else
				table.insert(segments, segment)
			end
		elseif char == "[" then
			const quotedName, finish = string.match(argument, "^%[%s*[\"'](.-)[\"']%s*%]()", offset)
			if quotedName == nil or finish == nil then
				return nil
			end
			table.insert(segments, quotedName)
			offset = finish
		elseif char == ":" then
			const methodName, rawName, finish = string.match(argument, "^:([_%a][_%w]*)%s*%(%s*[\"'](.-)[\"']%s*%)()", offset)
			if methodName == nil or rawName == nil or finish == nil then
				return nil
			end
			if methodName ~= "WaitForChild" and methodName ~= "FindFirstChild" then
				return nil
			end
			table.insert(segments, rawName)
			offset = finish
		elseif string.match(char, "%s") then
			offset += 1
		else
			return nil
		end
	end

	if #segments == 0 then
		return nil
	end
	return table.concat(segments, ".")
end

const function findRequireUsages(targetPath: string, ignoredScript: LuaSourceContainer?): { RefactorUsage }
	const usages = {}
	for _, instance in game:GetDescendants() do
		if not isScript(instance) or instance == ignoredScript then
			continue
		end

		const scriptInstance = instance :: LuaSourceContainer
		const sourceText = getSource(scriptInstance)
		for lineNumber, line in string.split(sourceText, "\n") do
			const _, identifier, call = matchTopLevelDeclaration(line, "require%s*(%b())")
			if identifier == nil or call == nil then
				continue
			end

			const argument = string.match(call, "^%((.*)%)$")
			if argument == nil then
				continue
			end

			const fullName = getFullNameFromRequireExpression(scriptInstance, argument, sourceText)
			local directPath = string.gsub(argument, "%s+", "")
			if string.sub(directPath, 1, 5) == "game." then
				directPath = string.sub(directPath, 6)
			end
			if fullName ~= targetPath and directPath ~= targetPath then
				continue
			end

			table.insert(usages, {
				script = scriptInstance,
				line = lineNumber,
				path = scriptInstance:GetFullName(),
				text = line,
				source = sourceText,
				requireArgument = argument,
				requireFullName = fullName,
				identifier = identifier,
			})
		end
	end

	table.sort(usages, function(a, b)
		if a.path == b.path then
			return a.line < b.line
		end
		return a.path < b.path
	end)

	return usages
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
	const parent = target.Parent
	if parent == nil or parent == root then
		return {}, rootIdentifier
	end

	const ancestors = {}
	local current: Instance = parent
	while current ~= root do
		table.insert(ancestors, 1, current)
		current = current.Parent :: Instance
	end

	const folderLines = {}
	local expression = rootIdentifier
	const depthLimit = getFolderDepthLimit(settings)
	local importedFolderCount = 0
	for _, ancestor in ancestors do
		expression ..= getPathSegmentExpression(ancestor.Name)
		if settings.autoFolders and ancestor:IsA("Folder") and importedFolderCount < depthLimit then
			const identifier = getImportIdentifierFromInstance(ancestor, settings)
			table.insert(folderLines, finishStatement(`{getSectionKeyword(settings.instances, settings)} {identifier} = {expression}`, settings))
			expression = identifier
			importedFolderCount += 1
		end
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
	requires: Types.Requires,
	acquires: Types.ServiceAcquisitions,
	newAcquire: string?,
	newRequire: string?,
	newFolderLines: { string }?,
	newRemote: string?,
	settings: Types.Settings
): { string }
	if settings.duckableMode and (#requires.entries > 0 or #acquires.entries > 0) then
		return insertDuckableImports(
			lines,
			requires,
			acquires,
			newAcquire,
			newRequire,
			newFolderLines,
			newRemote,
			settings.importLayout
		)
	end

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
	const layoutGroups = getLayoutGroups(settings.importLayout)

	for _, group in layoutGroups do
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
			if line == "" then
				continue
			end
			table.insert(organizedLines, "")
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
const settingsButton = toolbar:CreateButton("CodeKit", "CodeKit", SETTINGS_ICON)
const settingsStore = Settings.create(plugin)
const snippetsStore = Snippets.create(plugin)
const refactorChanged = Instance.new("BindableEvent")
local pendingRefactors = {}
local connections: { RBXScriptConnection } = {}
local settingsWindow = nil
local bootstrapQueued = false
local unloading = false
local lastAutocompleteError = ""

const refactorQueue = {
	changed = refactorChanged.Event,
	get = function()
		return pendingRefactors
	end,
	dismiss = function(item)
		const index = table.find(pendingRefactors, item)
		if index ~= nil then
			table.remove(pendingRefactors, index)
			item.dismiss()
			refactorChanged:Fire()
		end
	end,
}

const function openRefactorWindow()
	if settingsWindow == nil then
		settingsWindow = SettingsWindow.create(plugin, settingsStore, {
			snippetsStore = snippetsStore,
			refactorQueue = refactorQueue,
		})
	end
	settingsWindow.openPage("refactor")
end

settingsButton.Click:Connect(function()
	if settingsWindow == nil then
		settingsWindow = SettingsWindow.create(plugin, settingsStore, {
			snippetsStore = snippetsStore,
			refactorQueue = refactorQueue,
		})
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

const function getIdentifierFromName(name: string, settings: Types.Settings): string
	name = applyCasing(name, settings.modules.casing)
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

const function replaceFirst(source: string, needle: string, replacement: string): string
	const startIndex, endIndex = string.find(source, needle, 1, true)
	if startIndex == nil or endIndex == nil then
		return source
	end
	return string.sub(source, 1, startIndex - 1) .. replacement .. string.sub(source, endIndex + 1)
end

const function replaceIdentifier(source: string, oldIdentifier: string, newIdentifier: string): string
	if oldIdentifier == newIdentifier then
		return source
	end
	return string.gsub(source, `%f[%w_]{escapePattern(oldIdentifier)}%f[^%w_]`, newIdentifier)
end

const function replaceLine(source: string, lineNumber: number, replacement: string): string
	const lines = string.split(source, "\n")
	lines[lineNumber] = replacement
	return table.concat(lines, "\n")
end

const function getServiceIdentifierFromArgument(argument: string, source: string, serviceName: string): string
	const token = string.match(argument, `^%s*({PAT_IDENT})`)
	if token == nil then
		return serviceName
	end
	if token == serviceName then
		return token
	end
	const aliases = getServiceAliases(source)
	if aliases[token] == serviceName then
		return token
	end
	return serviceName
end

const function getRequireArgumentForUsage(usage: RefactorUsage, module: ModuleScript, settings: Types.Settings): string
	const quoted = readQuotedRequire(usage.requireArgument)
	if quoted ~= nil then
		if string.find(quoted, "@game/", 1, true) == 1 then
			const service = getModuleProvenance(module)
			return quoteString(getGlobalStringPath(service, module), settings)
		end
		return quoteString(getRelativePath(usage.script, module), settings)
	end

	if string.find(usage.requireArgument, "^%s*script[%W]") ~= nil or string.match(usage.requireArgument, "^%s*script%s*$") ~= nil then
		return getLocalPathExpression(usage.script, module)
	end

	const service = getModuleProvenance(module)
	const serviceIdentifier = getServiceIdentifierFromArgument(usage.requireArgument, usage.source, service.Name)
	local expression = serviceIdentifier
	const segments = getPathSegments(service, module)
	for _, segment in segments do
		expression ..= getPathSegmentExpression(segment)
	end
	return expression
end

const function getUpdatedRequireLine(usage: RefactorUsage, newIdentifier: string, newArgument: string): string
	local line = replaceFirst(usage.text, usage.requireArgument, newArgument)
	line = string.gsub(line, `^(%s*[%a]+%s+){escapePattern(usage.identifier)}(%s*=)`, `%1{newIdentifier}%2`, 1)
	return line
end

const function buildRefactorEdits(module: ModuleScript, snapshot: ModuleSnapshot): { RefactorEdit }
	const settings = settingsStore.get()
	const oldIdentifier = getIdentifierFromName(snapshot.name, settings)
	const newIdentifier = getModuleIdentifier(module, settings)
	const edits = {}
	const workingSources: { [LuaSourceContainer]: string } = {}

	for _, usage in findRequireUsages(snapshot.path, module) do
		const newArgument = getRequireArgumentForUsage(usage, module, settings)
		const newLine = getUpdatedRequireLine(usage, newIdentifier, newArgument)
		const source = workingSources[usage.script] or usage.source
		local newSource = replaceLine(source, usage.line, newLine)
		if usage.identifier == oldIdentifier then
			newSource = replaceIdentifier(newSource, oldIdentifier, newIdentifier)
		end
		workingSources[usage.script] = newSource

		table.insert(edits, {
			script = usage.script,
			line = usage.line,
			path = usage.path,
			text = usage.text,
			source = usage.source,
			requireArgument = usage.requireArgument,
			requireFullName = usage.requireFullName,
			identifier = usage.identifier,
			newSource = newSource,
			newIdentifier = newIdentifier,
			newRequireArgument = newArgument,
		})
	end

	return edits
end

const function applyRefactorEdits(edits: { RefactorEdit })
	const sources: { [LuaSourceContainer]: string } = {}
	for _, edit in edits do
		sources[edit.script] = edit.newSource
	end
	for script, source in sources do
		setSource(script, source)
	end
end

const function enqueueRefactor(item)
	table.insert(pendingRefactors, item)
	refactorChanged:Fire()
	openRefactorWindow()
end

local moduleSnapshots: { [ModuleScript]: ModuleSnapshot } = {}
local moduleConnections: { [ModuleScript]: { RBXScriptConnection } } = {}

const function updateModuleSnapshot(module: ModuleScript)
	moduleSnapshots[module] = {
		name = module.Name,
		path = module:GetFullName(),
		parent = module.Parent,
	}
end

const function handleModuleChanged(module: ModuleScript)
	const snapshot = moduleSnapshots[module]
	if snapshot == nil or module.Parent == nil then
		return
	end
	if snapshot.name == module.Name and snapshot.parent == module.Parent then
		updateModuleSnapshot(module)
		return
	end

	const edits = buildRefactorEdits(module, snapshot)
	updateModuleSnapshot(module)
	if #edits == 0 then
		return
	end

	const oldName = snapshot.name
	const newName = module.Name
	enqueueRefactor({
		kind = "update",
		title = "Update Imports?",
		message = `Would you like to update imports to reflect this rename? ({oldName} to {newName})`,
		usages = edits,
		acceptText = "Yes",
		accept = function()
			applyRefactorEdits(edits)
		end,
		dismiss = function() end,
	})
end

const function handleModuleDeleted(module: ModuleScript, snapshot: ModuleSnapshot)
	const usages = findRequireUsages(snapshot.path, module)
	if #usages == 0 then
		return
	end

	enqueueRefactor({
		kind = "delete",
		title = "Deleted Module Still Imported",
		message = `{snapshot.name} was deleted, but these scripts still import it. Click a script to jump to the require line.`,
		usages = usages,
		dismiss = function() end,
	})
end

const function untrackModule(module: ModuleScript)
	const existing = moduleConnections[module]
	if existing ~= nil then
		for _, connection in existing do
			connection:Disconnect()
		end
	end
	moduleConnections[module] = nil
	moduleSnapshots[module] = nil
end

const function trackModule(module: ModuleScript)
	if moduleConnections[module] ~= nil then
		updateModuleSnapshot(module)
		return
	end

	updateModuleSnapshot(module)
	moduleConnections[module] = {
		module:GetPropertyChangedSignal("Name"):Connect(function()
			task.defer(function()
				if module.Parent ~= nil then
					handleModuleChanged(module)
				end
			end)
		end),
		module:GetPropertyChangedSignal("Parent"):Connect(function()
			task.defer(function()
				if module.Parent == nil then
					return
				end
				handleModuleChanged(module)
			end)
		end),
	}
end

const autocomplete: Types.AutocompleteCallback = function(request, response)
	const settings = settingsStore.get()
	if not settings.enabled then
		return response
	end

	const origin = request.textDocument
	if origin.document == nil then
		return response
	end
	if origin.document:IsCommandBar() and not settings.commandBarAutocomplete then
		return response
	end
	const originScript = origin.script

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

	if settings.autoModules and originScript ~= nil then
		for _, module in getModules(originScript, settings) do
			if isNoImport(module, settings) then
				continue
			end
			const identifier = getModuleIdentifier(module, settings)
			if requires.byIdentifier[identifier] ~= nil then
				continue
			end

			const service, path = getModuleProvenance(module)

			local serviceIdentifier = service.Name
			local acquireSource: string? = nil
			local folderSources = {}
			local requirePath = ""
			const moduleRequireMode = getScriptRequireMode(originScript, settings)
			if moduleRequireMode == "local" then
				if settings.stringRequires or settings.modules.relativeRequireByString then
					requirePath = quoteString(getRelativePath(originScript, module), settings)
				else
					requirePath = getLocalPathExpression(originScript, module)
				end
			elseif settings.stringRequires or settings.modules.absoluteRequireByString then
				requirePath = quoteString(getGlobalStringPath(service, module), settings)
			else
				if acquires.byServiceName[serviceIdentifier] ~= nil then
					serviceIdentifier = acquires.byServiceName[serviceIdentifier].identifier
				else
					acquireSource = finishStatement(
						`{getSectionKeyword(settings.services, settings)} {serviceIdentifier} = game:GetService({quoteString(serviceIdentifier, settings)})`,
						settings
					)
				end
				local baseExpression = serviceIdentifier
				folderSources, baseExpression = getFolderImports(service, module, serviceIdentifier, settings)
				requirePath = `{baseExpression}{getPathSegmentExpression(module.Name)}`
			end

			const requireCall = if settings.callStyle == "bare" then `require {requirePath}` else `require({requirePath})`
			const requireSource = finishStatement(`{getSectionKeyword(settings.modules, settings)} {identifier} = {requireCall}`, settings)

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
		const serviceAliases = getAliasMap(settings.customServiceAliases)
		for _, service in services do
			const serviceName = service.name
			const identifier = serviceAliases[serviceName] or applyCasing(serviceName, settings.services.casing)
			seenServices[serviceName] = true
			if acquires.byServiceName[serviceName] ~= nil then
				continue
			end

			const acquireSource = finishStatement(
				`{getSectionKeyword(settings.services, settings)} {identifier} = game:GetService({quoteString(serviceName, settings)})`,
				settings
			)

			table.insert(items, {
				label = identifier,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "Auto-service" },
				detail = "Service",
				learnMoreLink = `https://create.roblox.com/docs/reference/engine/classes/{serviceName}`,
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
			const localIdentifier = serviceAliases[identifier] or applyCasing(identifier, settings.services.casing)

			const acquireSource = finishStatement(
				`{getSectionKeyword(settings.services, settings)} {localIdentifier} = game:GetService({quoteString(identifier, settings)})`,
				settings
			)

			table.insert(items, {
				label = localIdentifier,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "Auto-service" },
				detail = "Additional Service",
				textEdit = {
					newText = getNewText(localIdentifier, acquireSource, nil, nil, nil),
					insert = patchRange,
					replace = patchRange,
				},
			})
		end
	end

	if settings.autoInstances and (settings.autoRemotes or settings.autoFolders) then
		const normalizedTrigger = string.lower(trigger)
		for _, instance in game:GetDescendants() do
			if isNoImport(instance, settings) then
				continue
			end
			if settings.skipFolders and (instance:IsA("Folder") or instance:IsA("Configuration")) then
				continue
			end
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
						`{getSectionKeyword(settings.services, settings)} {rootIdentifier} = game:GetService({quoteString(rootIdentifier, settings)})`,
						settings
					)
				end

				local baseExpression = rootIdentifier
				folderSources, baseExpression = getFolderImports(root, instance, rootIdentifier, settings)
				const identifier = getImportIdentifierFromInstance(instance, settings)
				completionText = identifier
				const indexedExpression = getInstanceIndexExpression(baseExpression, instance, getScriptIndexingMode(originScript, settings), settings)
				if instance:IsA("Folder") then
					importSource = finishStatement(
						`{getSectionKeyword(settings.instances, settings)} {identifier} = {indexedExpression}`,
						settings
					)
					table.insert(folderSources, importSource)
					importSource = nil
				else
					importSource = finishStatement(
						`{getSectionKeyword(settings.instances, settings)} {identifier} = {indexedExpression}`,
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

	if settings.definitions.enabled then
		const normalizedTrigger = string.lower(trigger)
		for _, definition in DEFINITION_ITEMS do
			const identifier = getDefinitionIdentifier(definition.label, settings)
			if string.find(string.lower(identifier), normalizedTrigger, 1, true) ~= 1 then
				continue
			end

			local acquireSource: string? = nil
			if definition.service ~= nil and acquires.byServiceName[definition.service] == nil then
				acquireSource = finishStatement(
					`{getSectionKeyword(settings.services, settings)} {definition.service} = game:GetService({quoteString(definition.service, settings)})`,
					settings
				)
			end

			const definitionSource = finishStatement(
				`{getSectionKeyword(settings.definitions, settings)} {identifier} = {definition.source}`,
				settings
			)

			table.insert(items, {
				label = identifier,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = "CodeKit definition" },
				detail = definition.detail,
				textEdit = {
					newText = getNewText(identifier, acquireSource, nil, nil, definitionSource),
					insert = patchRange,
					replace = patchRange,
				},
			})
		end
	end

	if settings.enableQuickAccess then
		const normalizedTrigger = string.lower(trigger)
		const editRange = getReplaceRange(position, triggerStartCharacter)
		for _, quickItem in QUICK_ACCESS_ITEMS do
			if string.find(string.lower(quickItem.label), normalizedTrigger, 1, true) ~= 1 then
				continue
			end

			table.insert(items, {
				label = quickItem.label,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = quickItem.detail },
				detail = quickItem.detail,
				textEdit = {
					newText = quickItem.insert,
					insert = editRange,
					replace = editRange,
				},
			})
		end
	end

	for _, snippet in snippetsStore.get() do
		if originScript == nil then
			continue
		end
		const normalizedTrigger = string.lower(trigger)
		const editRange = getReplaceRange(position, triggerStartCharacter)
		const function addSnippetItem(label: string, detail: string)
			table.insert(items, {
				label = label,
				kind = Enum.CompletionItemKind.Snippet,
				documentation = { value = `CodeKit snippet: {snippet.name}` },
				detail = detail,
				textEdit = {
					newText = expandSnippet(snippet.source, originScript :: LuaSourceContainer, label),
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

for _, instance in game:GetDescendants() do
	if instance:IsA("ModuleScript") then
		trackModule(instance)
	end
end

table.insert(connections, game.DescendantAdded:Connect(function(instance)
	if instance:IsA("ModuleScript") then
		trackModule(instance)
		queueAutocompleteBootstrap()
	end
end))
table.insert(connections, game.DescendantRemoving:Connect(function(instance)
	if instance:IsA("ModuleScript") then
		const module = instance :: ModuleScript
		const snapshot = moduleSnapshots[module]
		task.defer(function()
			if module.Parent == nil and snapshot ~= nil then
				handleModuleDeleted(module, snapshot)
				untrackModule(module)
			end
		end)
		queueAutocompleteBootstrap()
	end
end))

plugin.Unloading:Connect(function()
	unloading = true
	for _, connection in connections do
		connection:Disconnect()
	end
	deregisterAutocomplete()
	if settingsWindow ~= nil then
		settingsWindow.destroy()
	end
	for module in moduleConnections do
		untrackModule(module)
	end
	refactorChanged:Destroy()
	settingsStore.destroy()
	snippetsStore.destroy()
end)
