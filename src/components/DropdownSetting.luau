-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")
const BaseSetting = require("./BaseSetting")

const new = vide.create
const source = vide.source
const effect = vide.effect

export type DropdownSetting = {
	text: (string?) -> string,
	label: TextLabel,
	close: () -> (),
	isOpen: () -> boolean,
	getOpenHeight: () -> number,
}

const function DropdownSetting(
	parent: Instance,
	name: string,
	index: number,
	options: { string },
	onSelect: (string) -> (),
	onToggle: (() -> ())?
): DropdownSetting
	const open = source(false)
	const selected = source("")
	const row = BaseSetting({
		parent = parent,
		name = name,
		index = index,
	})
	local textLabel: TextLabel
	local arrowIcon: ImageLabel
	local dropdownFrame: Frame
	const openHeight = #options * Theme.DROPDOWN_ROW_HEIGHT

	const button = new("TextButton")({
		Name = "Value",
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSans,
		TextSize = 15,
		TextColor3 = Theme.TEXT,
		AutoButtonColor = true,
		Activated = function()
			open(not open())
		end,
		Parent = row,
	}) :: TextButton

	new("TextLabel")({
		Name = "Text",
		Size = UDim2.new(1, -24, 1, 0),
		BackgroundTransparency = 1,
		Text = selected,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSans,
		TextSize = 15,
		TextColor3 = Theme.TEXT,
		Parent = button,
		vide.action(function(instance)
			textLabel = instance :: TextLabel
		end),
	})

	new("ImageLabel")({
		Name = "Arrow",
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0.5, -6),
		BackgroundTransparency = 1,
		Image = Theme.ARROW_IMAGE,
		ImageColor3 = Theme.TEXT,
		Parent = button,
		vide.action(function(instance)
			arrowIcon = instance :: ImageLabel
		end),
	})

	dropdownFrame = new("Frame")({
		Name = `{name}Dropdown`,
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.DARKER,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,

		Theme.stroke(Theme.BORDER),
		new("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
		}),
	}) :: Frame

	for i, option in options do
		new("TextButton")({
			Name = option,
			Size = UDim2.new(1, 0, 0, Theme.DROPDOWN_ROW_HEIGHT),
			BackgroundColor3 = if i % 2 == 0 then Theme.ROW_ALT else Theme.ROW,
			BorderSizePixel = 0,
			Text = `    {option}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TEXT,
			Font = Enum.Font.SourceSans,
			TextSize = 15,
			AutoButtonColor = true,
			Activated = function()
				onSelect(option)
				open(false)
			end,
			Parent = dropdownFrame,

			Theme.stroke(Theme.BORDER),
		})
	end

	effect(function()
		const isOpen = open()
		Theme.tween(dropdownFrame, {
			Size = UDim2.new(1, 0, 0, if isOpen then openHeight else 0),
		})
		Theme.tween(arrowIcon, {
			Rotation = if isOpen then 0 else -90,
		})
		if onToggle ~= nil then
			onToggle()
		end
	end)

	return {
		text = selected,
		label = textLabel,
		close = function()
			open(false)
		end,
		isOpen = open,
		getOpenHeight = function(): number
			return openHeight
		end,
	}
end

return DropdownSetting
