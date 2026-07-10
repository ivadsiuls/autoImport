-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")

const new = vide.create

export type Props = {
	parent: Instance,
	name: string,
	label: string?,
	description: string?,
	height: number?,
	placeholderText: string?,
	focusLost: (() -> ())?,
}

const function LargeTextBoxSetting(props: Props): TextBox
	local container = new("Frame")({
		Name = props.name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = props.parent,
		new("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
		}),
		new("TextLabel")({
			Name = "Label",
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = `    {props.label or props.name}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.MUTED,
			Font = Enum.Font.SourceSans,
			TextSize = 15,
			LayoutOrder = 1,
		}),
	}) :: Frame
	local textBox = new("TextBox")({
		Name = props.name,
		Size = UDim2.new(1, 0, 0, props.height or 42),
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
		Parent = container,
		LayoutOrder = 2,

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
	local description = new("TextLabel")({
		Name = "HoverDescription",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Theme.SECTION,
		BorderSizePixel = 0,
		Text = props.description or `{props.label or props.name} setting`,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3 = Theme.TEXT,
		Font = Enum.Font.SourceSans,
		TextSize = 13,
		Visible = false,
		ZIndex = 20,
		Active = false,
		Parent = textBox,
		Theme.stroke(Theme.BLUE_DARK),
	})
	container.MouseEnter:Connect(function()
		description.Visible = true
	end)
	container.MouseLeave:Connect(function()
		description.Visible = false
	end)
	return textBox
end

return LargeTextBoxSetting
