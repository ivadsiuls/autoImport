-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")
const BaseSetting = require("./BaseSetting")

const new = vide.create

export type Props = {
	parent: Instance,
	name: string,
	index: number,
	placeholderText: string?,
	focusLost: (() -> ())?,
}

const function TextBoxSetting(props: Props): TextBox
	const row = BaseSetting({
		parent = props.parent,
		name = props.name,
		index = props.index,
	})

	return new("TextBox")({
		Name = "Value",
		Size = UDim2.new(0.5, -6, 1, -6),
		Position = UDim2.new(0.5, 3, 0, 3),
		BackgroundColor3 = Color3.fromRGB(21, 22, 27),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSans,
		TextSize = 15,
		TextColor3 = Theme.TEXT,
		PlaceholderText = props.placeholderText or "",
		PlaceholderColor3 = Theme.MUTED,
		FocusLost = props.focusLost,
		Parent = row,

		Theme.stroke(Theme.BORDER),
		new("UIPadding")({
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	}) :: TextBox
end

return TextBoxSetting
