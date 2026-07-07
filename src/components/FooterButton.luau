-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")

const new = vide.create

const function FooterButton(parent: Instance, text: string, accent: boolean, activated: (() -> ())?): TextButton
	return new("TextButton")({
		Name = text,
		Size = UDim2.new(0.5, -5, 1, 0),
		BackgroundColor3 = if accent then Theme.BLUE else Color3.fromRGB(47, 50, 62),
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Theme.TEXT,
		Font = Enum.Font.SourceSansBold,
		TextSize = 15,
		AutoButtonColor = true,
		Activated = activated,
		Parent = parent,

		Theme.stroke(if accent then Theme.BLUE_DARK else Theme.BORDER),
	}) :: TextButton
end

return FooterButton
