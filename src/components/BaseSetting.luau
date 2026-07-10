-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")

const new = vide.create
const HOVER_DELAY = 1

const DESCRIPTIONS = {
	Enabled = "Enable CodeKit automation.",
	Modules = "Offer module imports in autocomplete.",
	Services = "Offer Roblox service acquisitions in autocomplete.",
	Instances = "Offer instance and remote imports in autocomplete.",
	Remotes = "Offer RemoteEvent and RemoteFunction imports.",
	Folders = "Offer folder imports in autocomplete.",
	["Skip Folders"] = "Skip folder and configuration instances during discovery.",
	["Quick Access"] = "Enable the quick-access settings entry point.",
	["Command Bar"] = "Enable CodeKit completions in the command bar.",
	Semicolons = "Add semicolons to generated statements.",
	["Duckable Mode"] = "Preserve your existing import order and append new imports beneath the current import block, based on duckable's preferences.",
	["String Quote"] = "Choose quotes for generated strings.",
	["Call Style"] = "Choose parentheses or bare require calls.",
	Keyword = "Choose whether generated declarations use local or const.",
	["Require Mode"] = "Choose local or global require paths.",
	["Sort Order"] = "Choose how generated imports are ordered.",
	["Folder Depth"] = "Choose how many folder levels are imported.",
	["Section Padding"] = "Choose blank lines between import sections.",
	Prefix = "Prefix used when generating identifiers.",
	["No-import Tag"] = "Attribute tag that excludes an instance from imports.",
	["Custom-Name Attribute"] = "Attribute that overrides an instance's generated name.",
	Casing = "Choose generated identifier casing.",
	["Sort order"] = "Choose ordering for this import section.",
	["Use const"] = "Use const declarations for this section.",
	["Type annotation"] = "Add type annotations where CodeKit can infer them.",
	["Type assertion"] = "Add Luau type assertions where useful.",
	["Has padding"] = "Add spacing around this section.",
	Nested = "Allow nested module paths in generated imports.",
	["Show in type checking"] = "Include this section in type-checking imports.",
	["Relative require-by-string"] = "Use relative string paths for requires.",
	["Absolute require-by-string"] = "Use absolute string paths for requires.",
	["Client Scripts Require"] = "Require mode used by client scripts.",
	["Server Scripts Require"] = "Require mode used by server scripts.",
	["Client Scripts"] = "Indexing mode used in client scripts.",
	["Server Scripts"] = "Indexing mode used in server scripts.",
}

export type Props = {
	parent: Instance,
	name: string,
	index: number,
	height: number?,
	description: string?,
}

const function BaseSetting(props: Props): Frame
	const height = props.height or Theme.ROW_HEIGHT
	const root = props.parent.Parent.Parent :: Frame

	local row = new("Frame")({
		Name = props.name,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = if props.index % 2 == 0 then Theme.ROW_ALT else Theme.ROW,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = props.parent,

		Theme.stroke(Theme.BORDER),
		new("TextLabel")({
			Name = "Label",
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(0, 0),
			Text = `    {props.name}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.MUTED,
			Font = Enum.Font.SourceSans,
			TextSize = 15,
			BackgroundTransparency = 1,
		}),
	}) :: Frame
	local description = new("TextLabel")({
		Name = "HoverDescription",
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(12, 0),
		BackgroundColor3 = Theme.SECTION,
		BorderSizePixel = 0,
		Text = props.description or DESCRIPTIONS[props.name] or `{props.name} setting`,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.TEXT,
		Font = Enum.Font.SourceSans,
		TextSize = 16,
		LineHeight = 1.15,
		Visible = false,
		ZIndex = 100,
		Active = false,
		Parent = root,
		Theme.stroke(Theme.BORDER),
		new("UICorner")({
			CornerRadius = UDim.new(0, 6),
		}),
		new("UIPadding")({
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 11),
			PaddingBottom = UDim.new(0, 11),
		}),
	})
	const function positionDescription()
		const rootPosition = root.AbsolutePosition
		const rowPosition = row.AbsolutePosition
		const descriptionHeight = description.AbsoluteSize.Y
		const descriptionWidth = description.AbsoluteSize.X
		const maxX = math.max(12, root.AbsoluteSize.X - descriptionWidth - 12)
		const x = math.clamp(rowPosition.X - rootPosition.X + 8, 12, maxX)
		const belowY = rowPosition.Y - rootPosition.Y + row.AbsoluteSize.Y + 4
		const aboveY = rowPosition.Y - rootPosition.Y - descriptionHeight - 4
		const y = if belowY + descriptionHeight <= root.AbsoluteSize.Y - 8 then belowY else math.max(8, aboveY)
		description.Position = UDim2.fromOffset(x, y)
	end

	local hoverToken = 0
	row.MouseEnter:Connect(function()
		hoverToken += 1
		const currentHoverToken = hoverToken
		task.delay(HOVER_DELAY, function()
			if currentHoverToken ~= hoverToken or row.Parent == nil then
				return
			end
			description.Visible = true
			task.defer(function()
				if currentHoverToken ~= hoverToken or row.Parent == nil then
					return
				end
				positionDescription()
			end)
		end)
	end)
	row.MouseLeave:Connect(function()
		hoverToken += 1
		description.Visible = false
	end)
	row.Destroying:Connect(function()
		hoverToken += 1
		description:Destroy()
	end)
	return row
end

return BaseSetting
