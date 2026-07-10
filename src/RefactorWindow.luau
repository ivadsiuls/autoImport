-- selene: allow(mixed_table)
const ScriptEditorService = game:GetService("ScriptEditorService")
const TextService = game:GetService("TextService")
const vide = require("./vide")
const Theme = require("./components/Theme")

const new = vide.create
const mount = vide.mount
const source = vide.source
const effect = vide.effect
const cleanup = vide.cleanup

export type ImportUsage = {
	script: LuaSourceContainer,
	line: number,
	path: string,
	text: string,
}

export type PendingRefactor = {
	kind: "update" | "delete",
	title: string,
	message: string,
	usages: { ImportUsage },
	acceptText: string?,
	accept: (() -> ())?,
	dismiss: () -> (),
}

type RefactorQueue = {
	changed: RBXScriptSignal,
	get: () -> { PendingRefactor },
	dismiss: (PendingRefactor) -> (),
}

const WIDGET_ID = "codekit-refactors"
const ROW_HEIGHT = 42
const COLUMN_HEADER_HEIGHT = 28
const SCRIPT_COLUMN = 0.78

const function shortenText(text: string, width: number, font: Enum.Font, textSize: number): string
	if width <= 0 then
		return text
	end

	const fullSize = TextService:GetTextSize(text, textSize, font, Vector2.new(math.huge, textSize + 8))
	if fullSize.X <= width then
		return text
	end

	local left = 0
	local right = #text
	local best = ""
	while left <= right do
		const mid = math.floor((left + right) / 2)
		const candidate = `{string.sub(text, 1, mid)}...`
		const candidateSize = TextService:GetTextSize(candidate, textSize, font, Vector2.new(math.huge, textSize + 8))
		if candidateSize.X <= width then
			best = candidate
			left = mid + 1
		else
			right = mid - 1
		end
	end

	return best
end

const function bindShortenedText(label: TextLabel, fullText: string)
	const function updateText()
		label.Text = shortenText(fullText, label.AbsoluteSize.X - 12, label.Font, label.TextSize)
	end

	cleanup(label:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateText))
	updateText()
end

const function createSeparator(xScale: number)
	return new("Frame")({
		Name = "ColumnSeparator",
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.fromScale(xScale, 0),
		BackgroundColor3 = Theme.BORDER,
		BorderSizePixel = 0,
	})
end

const function openUsage(usage: ImportUsage)
	task.spawn(function()
		const success, message = ScriptEditorService:OpenScriptDocumentAsync(usage.script)
		if not success then
			warn(`CodeKit failed to open import usage: {message}`)
			return
		end

		local document = ScriptEditorService:FindScriptDocument(usage.script)
		if document == nil then
			task.wait()
			document = ScriptEditorService:FindScriptDocument(usage.script)
		end
		if document == nil then
			return
		end

		const lineText = document:GetLine(usage.line)
		document:ForceSetSelectionAsync(usage.line, 1, usage.line, #lineText + 1)
	end)
end

const function createButton(parent: Instance, label: string, order: number, primary: boolean, activated: () -> ())
	return new("TextButton")({
		Name = label,
		LayoutOrder = order,
		Size = UDim2.new(0.5, -5, 1, 0),
		BackgroundColor3 = if primary then Theme.BLUE else Theme.ROW_ALT,
		BorderSizePixel = 0,
		Text = label,
		TextColor3 = Theme.TEXT,
		Font = Enum.Font.SourceSansBold,
		TextSize = 15,
		AutoButtonColor = true,
		Activated = activated,
		Parent = parent,

		Theme.stroke(Theme.BORDER),
	}) :: TextButton
end

const function createPanel(parent: Instance, queue: RefactorQueue, onDone: (() -> ())?)
	local titleLabel: TextLabel
	local messageLabel: TextLabel
	local countLabel: TextLabel
	local listFrame: Frame
	local listLayout: UIListLayout
	local buttonFrame: Frame
	local renderTick = source(0)

	const function clearRows()
		for _, child in listFrame:GetChildren() do
			if child.Name == "ImportRow" then
				child:Destroy()
			end
		end
		for _, child in buttonFrame:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
	end

	const function getCurrent(): PendingRefactor?
		return queue.get()[1]
	end

	const function render()
		clearRows()
		const item = getCurrent()
		if item == nil then
			titleLabel.Text = "Refactor"
			messageLabel.Text = "No pending code updates."
			countLabel.Text = "0 pending"
			listFrame.Size = UDim2.new(1, 0, 0, COLUMN_HEADER_HEIGHT + ROW_HEIGHT)
			createButton(buttonFrame, "Done", 1, true, function()
				if onDone ~= nil then
					onDone()
				end
			end)
			return
		end

		titleLabel.Text = item.title
		messageLabel.Text = item.message
		countLabel.Text = `{#queue.get()} pending`

		local rowIndex = 0
		for _, usage in item.usages do
			rowIndex += 1
			new("TextButton")({
				Name = "ImportRow",
				LayoutOrder = rowIndex,
				Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				BackgroundColor3 = if rowIndex % 2 == 0 then Theme.ROW_ALT else Theme.ROW,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = true,
				Activated = function()
					openUsage(usage)
				end,
				Parent = listFrame,

				Theme.stroke(Theme.BORDER),
				createSeparator(SCRIPT_COLUMN),
				new("TextLabel")({
					Name = "Script",
					Size = UDim2.new(SCRIPT_COLUMN, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = "",
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 15,
					vide.action(function(label)
						bindShortenedText(label :: TextLabel, usage.path)
					end),

					new("UIPadding")({
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),
				}),
				new("TextLabel")({
					Name = "Line",
					Size = UDim2.new(1 - SCRIPT_COLUMN, 0, 1, 0),
					Position = UDim2.fromScale(SCRIPT_COLUMN, 0),
					BackgroundTransparency = 1,
					Text = tostring(usage.line),
					TextColor3 = Theme.MUTED,
					Font = Enum.Font.SourceSansBold,
					TextSize = 15,
				}),
			})
		end

		listFrame.Size = UDim2.new(1, 0, 0, math.max(ROW_HEIGHT, listLayout.AbsoluteContentSize.Y))
		if item.accept ~= nil then
			createButton(buttonFrame, item.acceptText or "Yes", 1, true, function()
				(item.accept :: () -> ())()
				queue.dismiss(item)
			end)
			createButton(buttonFrame, "No", 2, false, function()
				queue.dismiss(item)
			end)
		else
			createButton(buttonFrame, "Dismiss", 1, true, function()
				queue.dismiss(item)
			end)
		end
	end

	const destroyUi = mount(function()
		const root = new("Frame")({
			Name = "Root",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.DARK,
			BorderSizePixel = 0,

			new("Frame")({
				Name = "Accent",
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = Theme.BLUE,
				BorderSizePixel = 0,
			}),
			new("Frame")({
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 48),
				Position = UDim2.fromOffset(0, 3),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,

				new("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, -132, 1, 0),
					Position = UDim2.fromOffset(10, 0),
					BackgroundTransparency = 1,
					Text = "Refactor",
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSansSemibold,
					TextSize = 20,
					vide.action(function(label)
						titleLabel = label :: TextLabel
					end),
				}),
				new("TextLabel")({
					Name = "Count",
					Size = UDim2.fromOffset(98, 48),
					Position = UDim2.new(1, -108, 0, 0),
					BackgroundTransparency = 1,
					Text = "0 pending",
					TextColor3 = Theme.MUTED,
					Font = Enum.Font.SourceSans,
					TextSize = 14,
					vide.action(function(label)
						countLabel = label :: TextLabel
					end),
				}),
			}),
			new("TextLabel")({
				Name = "Message",
				Size = UDim2.new(1, -20, 0, 58),
				Position = UDim2.fromOffset(10, 51),
				BackgroundColor3 = Theme.SECTION,
				BorderSizePixel = 0,
				Text = "",
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				TextColor3 = Theme.MUTED,
				Font = Enum.Font.SourceSans,
				TextSize = 15,
				vide.action(function(label)
					messageLabel = label :: TextLabel
				end),

				Theme.stroke(Theme.BORDER),
				new("UIPadding")({
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				}),
			}),
			new("ScrollingFrame")({
				Name = "Content",
				Size = UDim2.new(1, 0, 1, -163),
				Position = UDim2.fromOffset(0, 117),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,

				new("UIPadding")({
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 8),
				}),
				new("Frame")({
					Name = "List",
					Size = UDim2.new(1, 0, 0, COLUMN_HEADER_HEIGHT + ROW_HEIGHT),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					vide.action(function(instance)
						listFrame = instance :: Frame
					end),

					new("Frame")({
						Name = "ColumnHeader",
						LayoutOrder = 0,
						Size = UDim2.new(1, 0, 0, COLUMN_HEADER_HEIGHT),
						BackgroundColor3 = Theme.SECTION,
						BorderSizePixel = 0,

						Theme.stroke(Theme.BORDER),
						createSeparator(SCRIPT_COLUMN),
						new("TextLabel")({
							Name = "Script",
							Size = UDim2.new(SCRIPT_COLUMN, 0, 1, 0),
							BackgroundTransparency = 1,
							Text = "Affected file",
							TextXAlignment = Enum.TextXAlignment.Left,
							TextColor3 = Theme.MUTED,
							Font = Enum.Font.SourceSansBold,
							TextSize = 13,

							new("UIPadding")({
								PaddingLeft = UDim.new(0, 8),
								PaddingRight = UDim.new(0, 8),
							}),
						}),
						new("TextLabel")({
							Name = "Line",
							Size = UDim2.new(1 - SCRIPT_COLUMN, 0, 1, 0),
							Position = UDim2.fromScale(SCRIPT_COLUMN, 0),
							BackgroundTransparency = 1,
							Text = "Line",
							TextColor3 = Theme.MUTED,
							Font = Enum.Font.SourceSansBold,
							TextSize = 13,
						}),
					}),

					new("UIListLayout")({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						vide.action(function(instance)
							listLayout = instance :: UIListLayout
						end),
					}),
				}),
			}),
			new("Frame")({
				Name = "Buttons",
				Size = UDim2.new(1, -8, 0, 36),
				Position = UDim2.new(0, 4, 1, -40),
				BackgroundColor3 = Theme.DARKER,
				BorderSizePixel = 0,
				vide.action(function(instance)
					buttonFrame = instance :: Frame
				end),

				new("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 10),
				}),
			}),
		})

		effect(function()
			renderTick()
			render()
		end)

		cleanup(queue.changed:Connect(function()
			renderTick(renderTick() + 1)
		end))

		return root
	end, parent)

	return {
		refresh = function()
			renderTick(renderTick() + 1)
		end,
		destroy = function()
			destroyUi()
		end,
	}
end

const function createWindow(plugin: Plugin, queue: RefactorQueue)
	const widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		540,
		410,
		420,
		300
	)
	const widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
	widget.Name = "CodeKit Refactors"
	widget.Title = "CodeKit Refactors"
	const panel = createPanel(widget, queue, function()
		widget.Enabled = false
	end)

	return {
		widget = widget,
		open = function()
			widget.Enabled = true
			panel.refresh()
		end,
		toggle = function()
			widget.Enabled = not widget.Enabled
			panel.refresh()
		end,
		destroy = function()
			panel.destroy()
		end,
	}
end

return {
	create = createWindow,
	createPanel = createPanel,
}
