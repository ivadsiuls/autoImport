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
export type Keyword = "local" | "const"

export type Settings = {
	enabled: boolean,
	stringRequires: boolean,
	requireMode: RequireMode,
	keyword: Keyword,
	prefix: string,
	autoServices: boolean,
	additionalServices: { string },
	clientDirectories: { string },
	ignoredNames: { string },
	overrideWorkspaceSettings: boolean,
}

export type SettingsScope = "global" | "workspace"

return {}
