const Types = require("./Types")
const Data = require("./Data")

const GLOBAL_SETTING_KEY = "IvadsAutoImportSettings"
const LEGACY_SETTING_KEY = "AutoImportSettings"
const WORKSPACE_SETTINGS_NAME = "_IAI_SETTINGS"
const DEFAULT_IMPORT_LAYOUT = "[services]\n\n[folders]\n\n[modules]\n\n[remotes]"
const LEGACY_IMPORT_LAYOUT = "[services]\n\n[modules]\n\n[folders]\n\n[remotes]"

const DEFAULT_SETTINGS: Types.Settings = {
	enabled = true,
	autoModules = true,
	requireMode = "global",
	callStyle = "parentheses",
	stringQuote = "double",
	autocompletePrefix = ":",
	autoServices = true,
	autoInstances = true,
	autoRemotes = true,
	autoFolders = false,
	enableQuickAccess = true,
	commandBarAutocomplete = false,
	noImportTag = "CodeKitIgnore",
	customNameAttribute = "CodeKitName",
	importFolderDepth = "First",
	importPlacement = "Organized",
	semicolons = false,
	importSort = "longestFirst",
	importLayout = DEFAULT_IMPORT_LAYOUT,
	additionalServices = {},
	customServiceAliases = {},
	clientDirectories = {},
	ignoredNames = { "_Index", "_index", "node_modules", "include" },
	duckableMode = false,
	services = {
		useConst = true,
		casing = "preserve",
	},
	modules = {
		useConst = true,
		casing = "preserve",
		serverScriptsRequire = "dynamic",
		clientScriptsRequire = "dynamic",
		relativeRequireByString = false,
		absoluteRequireByString = false,
	},
	instances = {
		useConst = true,
		casing = "preserve",
	},
	definitions = {
		enabled = true,
		useConst = true,
		casing = "preserve",
	},
	indexing = {
		clientScripts = "WaitForChild",
		serverScripts = "Direct",
	},
	overrideWorkspaceSettings = false,
}

const VALID_IMPORT_SORTS = {
	longestFirst = true,
	longestLast = true,
	alphabetical = true,
	reverseAlphabetical = true,
	constantsFirst = true,
	localsFirst = true,
	pathFirst = true,
	pathLast = true,
	identifierFirst = true,
	identifierLast = true,
}

const VALID_IMPORT_FOLDER_DEPTHS = {
	["First"] = true,
	["First Two"] = true,
	["All"] = true,
}

const VALID_IMPORT_PLACEMENTS = {
	Organized = true,
	["At Cursor"] = true,
}

const VALID_CALL_STYLES = {
	parentheses = true,
	bare = true,
}

const VALID_STRING_QUOTES = {
	double = true,
	single = true,
}

const VALID_CASINGS = {
	preserve = true,
	camel = true,
	pascal = true,
	snake = true,
}

const VALID_INDEXING_MODES = {
	WaitForChild = true,
	FindFirstChild = true,
	Direct = true,
}

const VALID_MODULE_REQUIRE_MODES = {
	dynamic = true,
	relative = true,
	absolute = true,
}


const function cloneList(list: { string }): { string }
	const cloned = {}
	for _, value in list do
		table.insert(cloned, value)
	end

	return cloned
end

const function normalizeList(value: any, fallback: { string }): { string }
	if typeof(value) ~= "table" then
		return cloneList(fallback)
	end

	const normalized = {}
	for _, item in value do
		if typeof(item) == "string" and item ~= "" then
			table.insert(normalized, item)
		end
	end

	return normalized
end

const function normalizeEnum(value: any, fallback: string, valid: { [string]: boolean }): string
	if typeof(value) ~= "string" or valid[value] ~= true then
		return fallback
	end
	return value
end

const function normalizeSection(value: any, fallback: Types.SectionSettings): Types.SectionSettings
	if typeof(value) ~= "table" then
		value = {}
	end

	return {
		useConst = value.useConst ~= false,
		casing = normalizeEnum(value.casing, fallback.casing, VALID_CASINGS) :: Types.Casing,
	}
end

const function normalizeModules(value: any, fallback: Types.ModulesSettings): Types.ModulesSettings
	const base = normalizeSection(value, fallback)
	if typeof(value) ~= "table" then
		value = {}
	end

	return {
		useConst = base.useConst,
		casing = base.casing,
		serverScriptsRequire = normalizeEnum(
			value.serverScriptsRequire,
			fallback.serverScriptsRequire,
			VALID_MODULE_REQUIRE_MODES
		) :: Types.ModuleRequireMode,
		clientScriptsRequire = normalizeEnum(
			value.clientScriptsRequire,
			fallback.clientScriptsRequire,
			VALID_MODULE_REQUIRE_MODES
		) :: Types.ModuleRequireMode,
		relativeRequireByString = value.relativeRequireByString == true,
		absoluteRequireByString = value.absoluteRequireByString == true,
	}
end

const function normalizeDefinitions(value: any, fallback: Types.DefinitionsSettings): Types.DefinitionsSettings
	const base = normalizeSection(value, fallback)
	if typeof(value) ~= "table" then
		value = {}
	end

	return {
		enabled = value.enabled ~= false,
		useConst = base.useConst,
		casing = base.casing,
	}
end

const function normalizeIndexing(value: any, fallback: Types.IndexingSettings): Types.IndexingSettings
	if typeof(value) ~= "table" then
		value = {}
	end

	return {
		clientScripts = normalizeEnum(value.clientScripts, fallback.clientScripts, VALID_INDEXING_MODES) :: Types.IndexingMode,
		serverScripts = normalizeEnum(value.serverScripts, fallback.serverScripts, VALID_INDEXING_MODES) :: Types.IndexingMode,
	}
end

const function normalizeSettings(value: any): Types.Settings
	if typeof(value) ~= "table" then
		value = {}
	end

	local requireMode = value.requireMode
	if requireMode ~= "local" and requireMode ~= "global" then
		requireMode = DEFAULT_SETTINGS.requireMode
	end
	local importSort = value.importSort
	if typeof(importSort) ~= "string" or VALID_IMPORT_SORTS[importSort] ~= true then
		importSort = DEFAULT_SETTINGS.importSort
	end
	local importFolderDepth = value.importFolderDepth
	if typeof(importFolderDepth) ~= "string" or VALID_IMPORT_FOLDER_DEPTHS[importFolderDepth] ~= true then
		importFolderDepth = DEFAULT_SETTINGS.importFolderDepth
	end
	local importPlacement = value.importPlacement
	if typeof(importPlacement) ~= "string" or VALID_IMPORT_PLACEMENTS[importPlacement] ~= true then
		importPlacement = DEFAULT_SETTINGS.importPlacement
	end
	local autocompletePrefix = if typeof(value.autocompletePrefix) == "string"
		then value.autocompletePrefix
		elseif typeof(value.prefix) == "string"
			then value.prefix
			else DEFAULT_SETTINGS.autocompletePrefix

	return {
		enabled = value.enabled ~= false,
		autoModules = value.autoModules ~= false,
		requireMode = requireMode,
		callStyle = normalizeEnum(value.callStyle, DEFAULT_SETTINGS.callStyle, VALID_CALL_STYLES) :: Types.CallStyle,
		stringQuote = normalizeEnum(value.stringQuote, DEFAULT_SETTINGS.stringQuote, VALID_STRING_QUOTES) :: Types.StringQuote,
		autocompletePrefix = autocompletePrefix,
		autoServices = value.autoServices ~= false,
		autoInstances = value.autoInstances ~= false,
		autoRemotes = value.autoRemotes ~= false,
		autoFolders = value.autoFolders == true,
		enableQuickAccess = value.enableQuickAccess ~= false,
		commandBarAutocomplete = value.commandBarAutocomplete == true,
		noImportTag = if typeof(value.noImportTag) == "string" and value.noImportTag ~= ""
			then value.noImportTag
			else DEFAULT_SETTINGS.noImportTag,
		customNameAttribute = if typeof(value.customNameAttribute) == "string" and value.customNameAttribute ~= ""
			then value.customNameAttribute
			else DEFAULT_SETTINGS.customNameAttribute,
		importFolderDepth = importFolderDepth,
		importPlacement = importPlacement,
		semicolons = value.semicolons == true,
		importSort = importSort,
		importLayout = if value.importLayout == LEGACY_IMPORT_LAYOUT
			then DEFAULT_SETTINGS.importLayout
			elseif typeof(value.importLayout) == "string" and value.importLayout ~= ""
				then value.importLayout
				else DEFAULT_SETTINGS.importLayout,
		additionalServices = normalizeList(value.additionalServices, DEFAULT_SETTINGS.additionalServices),
		customServiceAliases = normalizeList(value.customServiceAliases, DEFAULT_SETTINGS.customServiceAliases),
		clientDirectories = normalizeList(value.clientDirectories, DEFAULT_SETTINGS.clientDirectories),
		ignoredNames = normalizeList(value.ignoredNames, DEFAULT_SETTINGS.ignoredNames),
		duckableMode = value.duckableMode == true,
		services = normalizeSection(value.services, DEFAULT_SETTINGS.services),
		modules = normalizeModules(value.modules, DEFAULT_SETTINGS.modules),
		instances = normalizeSection(value.instances, DEFAULT_SETTINGS.instances),
		definitions = normalizeDefinitions(value.definitions, DEFAULT_SETTINGS.definitions),
		indexing = normalizeIndexing(value.indexing, DEFAULT_SETTINGS.indexing),
		overrideWorkspaceSettings = value.overrideWorkspaceSettings == true,
	}
end

const function loadWorkspaceSettings(): Types.Settings?
	return Data.loadWorkspace(WORKSPACE_SETTINGS_NAME, nil)
end

const function saveWorkspaceSettings(settings: Types.Settings)
	Data.saveWorkspace(WORKSPACE_SETTINGS_NAME, "edit from the plugin settings window", settings)
end

const function create(plugin: Plugin)
	local globalSettings = normalizeSettings(
		Data.load(plugin, GLOBAL_SETTING_KEY, Data.load(plugin, LEGACY_SETTING_KEY, {}))
	)
	local loadedWorkspaceSettings = loadWorkspaceSettings()
	local workspaceSettings = if loadedWorkspaceSettings == nil
		then nil
		else normalizeSettings(loadedWorkspaceSettings)
	const changed = Instance.new("BindableEvent")

	const function getEffectiveSettings(): Types.Settings
		if globalSettings.overrideWorkspaceSettings then
			return globalSettings
		end
		return workspaceSettings or globalSettings
	end

	const function fireChanged()
		changed:Fire(getEffectiveSettings())
	end

	const function saveGlobal()
		Data.save(plugin, GLOBAL_SETTING_KEY, globalSettings)
		fireChanged()
	end

	const function saveWorkspace()
		workspaceSettings = normalizeSettings(workspaceSettings)
		saveWorkspaceSettings(workspaceSettings :: Types.Settings)
		fireChanged()
	end

	return {
		changed = changed.Event,
		get = getEffectiveSettings,
		getGlobal = function(): Types.Settings
			return globalSettings
		end,
		getWorkspace = function(): Types.Settings
			return workspaceSettings or globalSettings
		end,
		hasWorkspace = function(): boolean
			return workspaceSettings ~= nil
		end,
		update = function(scope: Types.SettingsScope, key: string, value: any)
			if scope == "global" then
				globalSettings[key] = value
				globalSettings = normalizeSettings(globalSettings)
				saveGlobal()
			else
				const settings = if workspaceSettings == nil then normalizeSettings(globalSettings) else workspaceSettings
				settings[key] = value
				settings.overrideWorkspaceSettings = false
				workspaceSettings = normalizeSettings(settings)
				saveWorkspace()
			end
		end,
		reset = function()
			globalSettings = normalizeSettings(DEFAULT_SETTINGS)
			workspaceSettings = nil
			Data.deleteWorkspace(WORKSPACE_SETTINGS_NAME)
			Data.save(plugin, GLOBAL_SETTING_KEY, globalSettings)
			fireChanged()
		end,
		refreshWorkspace = function()
			const loaded = loadWorkspaceSettings()
			workspaceSettings = if loaded == nil then nil else normalizeSettings(loaded)
			fireChanged()
		end,
		destroy = function()
			changed:Destroy()
		end,
	}
end

return {
	create = create,
	DEFAULT_SETTINGS = DEFAULT_SETTINGS,
	DEFAULT_IMPORT_LAYOUT = DEFAULT_IMPORT_LAYOUT,
	WORKSPACE_SETTINGS_NAME = WORKSPACE_SETTINGS_NAME,
}
