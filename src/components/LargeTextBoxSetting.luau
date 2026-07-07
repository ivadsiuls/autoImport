-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")

const new = vide.create

export type Props = {
	parent: Instance,
	name: string,
	height: number?,
	placeholderText: string?,
	focusLost: (() -> ())?,
}

const function LargeTextBoxSetting(props: Props): TextBox
	return new("TextBox")({
		Name = props.name,
		Size = UDim2.new(1, 0, 0, props.height or 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.DARKER,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.SourceSans,
		TextSize = 15,
		TextColor3 = Theme.TEXT,
		PlaceholderText = props.placeholderText or "",
		PlaceholderColor3 = Theme.MUTED,
		FocusLost = props.focusLost,
		Parent = props.parent,

		Theme.stroke(Theme.BORDER),
		new("UISizeConstraint")({
			MinSize = Vector2.new(0, 42),
		}),
		new("UIPadding")({
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	}) :: TextBox
end

return LargeTextBoxSetting
