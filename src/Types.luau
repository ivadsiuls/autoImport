export type RequireEntry = {
	lineNumber: number,
	identifier: string,
	declaration: "local" | "const",
}

export type Requires = {
	entries: { RequireEntry },
	byIdentifier: { [string]: RequireEntry },
}

export type ServiceAcquisitionEntry = {
	lineNumber: number,
	identifier: string,
	serviceName: string,
	declaration: "local" | "const",
}

export type ServiceAcquisitions = {
	entries: { ServiceAcquisitionEntry },
	byServiceName: { [string]: ServiceAcquisitionEntry },
}

export type Comment = {
	kind: "simple" | "long",
	range: Range,
	header: boolean,
	text: string,
}

export type String = {
	kind: "quoted" | "long" | "interp",
	range: Range,
	text: string,
}

export type Position = {
	line: number,
	character: number,
}

export type Range = {
	start: Position,
	["end"]: Position,
}

export type AutocompleteRequest = {
	position: Position,
	textDocument: {
		document: ScriptDocument?,
		script: LuaSourceContainer?,
	},
}

export type AutocompleteResponseItem = {
	label: string,
	kind: Enum.CompletionItemKind?,
	tags: { Enum.CompletionItemTag }?,
	detail: string?,
	documentation: {
		value: string,
	}?,
	overloads: number?,
	learnMoreLink: string?,
	codeSample: string?,
	preselect: boolean?,
	textEdit: {
		newText: string,
		insert: Range,
		replace: Range,
	}?,
}

export type AutocompleteResponse = {
	items: { AutocompleteResponseItem },
}

export type AutocompleteCallback = (
	request: AutocompleteRequest,
	response: AutocompleteResponse
) -> AutocompleteResponse

export type RequireMode = "local" | "global"
export type CallStyle = "parentheses" | "bare"
export type Keyword = "local" | "const"
export type StringQuote = "double" | "single"
export type ImportSort = "longestFirst"
	| "longestLast"
	| "alphabetical"
	| "reverseAlphabetical"
	| "constantsFirst"
	| "localsFirst"
	| "pathFirst"
	| "pathLast"
	| "identifierFirst"
	| "identifierLast"
export type ImportFolderDepth = "First" | "First Two" | "All"
export type ImportPlacement = "Organized" | "At Cursor"
export type Casing = "preserve" | "camel" | "pascal" | "snake"
export type IndexingMode = "WaitForChild" | "FindFirstChild" | "Direct"
export type ModuleRequireMode = "dynamic" | "relative" | "absolute"

export type SectionSettings = {
	useConst: boolean,
	casing: Casing,
}

export type ModulesSettings = SectionSettings & {
	serverScriptsRequire: ModuleRequireMode,
	clientScriptsRequire: ModuleRequireMode,
	relativeRequireByString: boolean,
	absoluteRequireByString: boolean,
}

export type DefinitionsSettings = SectionSettings & {
	enabled: boolean,
}

export type IndexingSettings = {
	clientScripts: IndexingMode,
	serverScripts: IndexingMode,
}

export type Settings = {
	enabled: boolean,
	autoModules: boolean,
	requireMode: RequireMode,
	callStyle: CallStyle,
	stringQuote: StringQuote,
	autocompletePrefix: string,
	autoServices: boolean,
	autoInstances: boolean,
	autoRemotes: boolean,
	autoFolders: boolean,
	enableQuickAccess: boolean,
	commandBarAutocomplete: boolean,
	noImportTag: string,
	customNameAttribute: string,
	importFolderDepth: ImportFolderDepth,
	importPlacement: ImportPlacement,
	semicolons: boolean,
	importSort: ImportSort,
	importLayout: string,
	additionalServices: { string },
	customServiceAliases: { string },
	clientDirectories: { string },
	ignoredNames: { string },
	duckableMode: boolean,
	services: SectionSettings,
	modules: ModulesSettings,
	instances: SectionSettings,
	definitions: DefinitionsSettings,
	indexing: IndexingSettings,
	overrideWorkspaceSettings: boolean,
}

export type SettingsScope = "global" | "workspace"

return {}
