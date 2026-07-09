export type ThemeColor = { number }

export type Theme = {
	name: string,
	previewImage: string,
	colors: { [string]: ThemeColor },
}

const themes: { Theme } = {
	{
		name = "Sunset",
		previewImage = "rbxassetid://105445564574038",
		colors = {
			["Background Color"] = { 37, 37, 37 },
			["Selection Color"] = { 171, 178, 191 },
			["Selection Background Color"] = { 61, 69, 85 },
			["Error Color"] = { 194, 64, 56 },
			["Warning Color"] = { 209, 154, 102 },
			["Find Selection Background Color"] = { 66, 85, 123 },
			["Matching Word Background Color"] = { 61, 69, 85 },
			["Whitespace Color"] = { 171, 178, 191 },
			["Current Line Highlight Color"] = { 35, 39, 46 },
			["Ruler Color"] = { 55, 60, 68 },
			["Bracket Color"] = { 171, 178, 191 },
			["Text Color"] = { 224, 108, 117 },
			["Operator Color"] = { 171, 178, 191 },
			["Number Color"] = { 209, 154, 102 },
			["String Color"] = { 152, 195, 121 },
			["Comment Color"] = { 127, 132, 142 },
			["Bool Color"] = { 209, 154, 102 },
			["\"nil\" Color"] = { 209, 154, 102 },
			["Function Name Color"] = { 97, 175, 239 },
			["\"function\" Color"] = { 198, 120, 221 },
			["\"local\" Color"] = { 198, 120, 221 },
			["\"self\" Color"] = { 229, 192, 123 },
			["Luau Keyword Color"] = { 224, 108, 117 },
			["Keyword Color"] = { 198, 120, 221 },
			["Built-in Function Color"] = { 86, 182, 194 },
			["\"TODO\" Color"] = { 224, 108, 117 },
			["Method Color"] = { 97, 175, 239 },
			["Property Color"] = { 224, 108, 117 },
		},
	},
}

return themes
