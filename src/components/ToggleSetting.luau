-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")
const BaseSetting = require("./BaseSetting")

const new = vide.create
const source = vide.source
const effect = vide.effect

export type ToggleSetting = {
	row: Frame,
	button: TextButton,
	set: (boolean) -> (),
}

const function ToggleSetting(parent: Instance, name: string, index: number, activated: (() -> ())?): ToggleSetting
	const checked = source(false)
	const row = BaseSetting({
		parent = parent,
		name = name,
		index = index,
	})
	local box: Frame
	local check: TextLabel

	const button = new("TextButton")({
		Name = "Value",
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		Activated = activated,
		Parent = row,

		new("Frame")({
			Name = "Box",
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, 6, 0.5, -7),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(37, 39, 48),
			vide.action(function(instance)
				box = instance :: Frame
			end),

			Theme.stroke(Theme.BORDER),
			new("TextLabel")({
				Name = "Check",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				TextColor3 = Theme.BLUE,
				Font = Enum.Font.SourceSansBold,
				TextSize = 18,
				vide.action(function(instance)
					check = instance :: TextLabel
				end),
			}),
		}),
	}) :: TextButton

	effect(function()
		const value = checked()
		Theme.tween(box, {
			BackgroundColor3 = if value then Color3.fromRGB(35, 48, 88) else Color3.fromRGB(37, 39, 48),
		})
		check.Text = if value then "✓" else ""
	end)

	return {
		row = row,
		button = button,
		set = checked,
	}
end

return ToggleSetting
