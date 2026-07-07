-- selene: allow(mixed_table)
const vide = require("../vide")
const Theme = require("./Theme")

const new = vide.create

export type Props = {
	parent: Instance,
	name: string,
	index: number,
	height: number?,
}

const function BaseSetting(props: Props): Frame
	const height = props.height or Theme.ROW_HEIGHT

	return new("Frame")({
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
end

return BaseSetting
