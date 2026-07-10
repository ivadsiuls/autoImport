-- selene: allow(mixed_table)
const ScriptEditorService = game:GetService("ScriptEditorService")
const TextService = game:GetService("TextService")
const vide = require("./vide")
const Theme = require("./components/Theme")
const parseScript = require("./parseScript")
const Types = require("./Types")

const new = vide.create
const mount = vide.mount
const source = vide.source
const effect = vide.effect
const cleanup = vide.cleanup

type TodoItem = {
	script: LuaSourceContainer,
	line: number,
	text: string,
	path: string,
}

const WIDGET_ID = "codekit-todos"
const ROW_HEIGHT = 42
const SCRIPT_COLUMN = 0.38
const LINE_COLUMN = 0.16
const REFRESH_IMAGE = "rbxassetid://6031094678"

const function isScript(instance: Instance): boolean
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

const function trim(text: string): string
	return string.gsub(text, "^%s*(.-)%s*$", "%1")
end

const function getTodoText(commentText: string): string?
	const startIndex = string.find(string.upper(commentText), "TODO", 1, true)
	if startIndex == nil then
		return nil
	end

	return trim(string.sub(commentText, startIndex))
end

const function getTodoLine(comment: Types.Comment): number
	const startIndex = string.find(string.upper(comment.text), "TODO", 1, true)
	if startIndex == nil then
		return comment.range.start.line
	end

	const beforeTodo = string.sub(comment.text, 1, startIndex - 1)
	local lineOffset = 0
	for _ in string.gmatch(beforeTodo, "\n") do
		lineOffset += 1
	end
	return comment.range.start.line + lineOffset
end

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

const function createPanel(parent: Instance)
	local listFrame: Frame
	local listLayout: UIListLayout
	local emptyLabel: TextLabel
	local countLabel: TextLabel
	local scanTick = source(0)
	local todoItems = {}

	const function scanTodos(): { TodoItem }
		const items = {}
		for _, instance in game:GetDescendants() do
			if not isScript(instance) then
				continue
			end

			const scriptInstance = instance :: LuaSourceContainer
			local sourceText = ""
			local ok = pcall(function()
				sourceText = ScriptEditorService:GetEditorSource(scriptInstance)
			end)
			if not ok then
				sourceText = scriptInstance.Source
			end

			const parsed = parseScript(sourceText)
			for _, comment in parsed.comments do
				const todoText = getTodoText(comment.text)
				if todoText == nil then
					continue
				end

				table.insert(items, {
					script = scriptInstance,
					line = getTodoLine(comment),
					text = todoText,
					path = scriptInstance:GetFullName(),
				})
			end
		end

		table.sort(items, function(a, b)
			if a.path == b.path then
				return a.line < b.line
			end
			return a.path < b.path
		end)

		return items
	end

	const function openTodo(item: TodoItem)
		task.spawn(function()
			const success, message = ScriptEditorService:OpenScriptDocumentAsync(item.script)
			if not success then
				warn(`CodeKit failed to open TODO script: {message}`)
				return
			end

			local document = ScriptEditorService:FindScriptDocument(item.script)
			if document == nil then
				task.wait()
				document = ScriptEditorService:FindScriptDocument(item.script)
			end
			if document == nil then
				return
			end

			const lineText = document:GetLine(item.line)
			document:ForceSetSelectionAsync(item.line, 1, item.line, #lineText + 1)
		end)
	end

	const function clearRows()
		for _, child in listFrame:GetChildren() do
			if child.Name == "TodoRow" then
				child:Destroy()
			end
		end
	end

	const function renderRows()
		clearRows()
		local rowIndex = 0
		for _, item in todoItems do
			rowIndex += 1
			const rowHeight = math.max(ROW_HEIGHT, #string.split(item.text, "\n") * 20 + 12)
			const row = new("TextButton")({
				Name = "TodoRow",
				LayoutOrder = rowIndex,
				Size = UDim2.new(1, 0, 0, rowHeight),
				BackgroundColor3 = if rowIndex % 2 == 0 then Theme.ROW_ALT else Theme.ROW,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = true,
				Activated = function()
					openTodo(item)
				end,
				Parent = listFrame,

				Theme.stroke(Theme.BORDER),
				createSeparator(SCRIPT_COLUMN),
				createSeparator(SCRIPT_COLUMN + LINE_COLUMN),
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
						bindShortenedText(label :: TextLabel, item.path)
					end),

					new("UIPadding")({
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),
				}),
				new("TextLabel")({
					Name = "Line",
					Size = UDim2.new(LINE_COLUMN, 0, 1, 0),
					Position = UDim2.fromScale(SCRIPT_COLUMN, 0),
					BackgroundTransparency = 1,
					Text = tostring(item.line),
					TextColor3 = Theme.MUTED,
					Font = Enum.Font.SourceSansBold,
					TextSize = 15,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
				new("TextLabel")({
					Name = "Text",
					Size = UDim2.new(1 - SCRIPT_COLUMN - LINE_COLUMN, 0, 1, 0),
					Position = UDim2.fromScale(SCRIPT_COLUMN + LINE_COLUMN, 0),
					BackgroundTransparency = 1,
					Text = item.text,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextWrapped = true,
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 15,

					new("UIPadding")({
						PaddingTop = UDim.new(0, 8),
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),
				}),
			})
		end

		emptyLabel.Visible = #todoItems == 0
		countLabel.Text = `{#todoItems} TODOs`
		listFrame.Size = UDim2.new(1, 0, 0, listLayout.AbsoluteContentSize.Y)
	end

	const function refresh()
		todoItems = scanTodos()
		scanTick(scanTick() + 1)
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
					Size = UDim2.new(1, -142, 1, 0),
					Position = UDim2.fromOffset(10, 0),
					BackgroundTransparency = 1,
					Text = "TODO Tracker",
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSansSemibold,
					TextSize = 20,
				}),
				new("TextLabel")({
					Name = "Count",
					Size = UDim2.fromOffset(72, 48),
					Position = UDim2.new(1, -126, 0, 0),
					BackgroundTransparency = 1,
					Text = "0 TODOs",
					TextColor3 = Theme.MUTED,
					Font = Enum.Font.SourceSans,
					TextSize = 14,
					vide.action(function(label)
						countLabel = label :: TextLabel
					end),
				}),
				new("ImageButton")({
					Name = "Refresh",
					Size = UDim2.fromOffset(28, 28),
					Position = UDim2.new(1, -38, 0.5, -14),
					BackgroundColor3 = Theme.ROW_ALT,
					BorderSizePixel = 0,
					Image = REFRESH_IMAGE,
					ImageColor3 = Theme.TEXT,
					Activated = refresh,

					Theme.stroke(Theme.BORDER),
				}),
			}),
			new("ScrollingFrame")({
				Name = "Content",
				Size = UDim2.new(1, 0, 1, -51),
				Position = UDim2.fromOffset(0, 51),
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
					Size = UDim2.new(1, 0, 0, 84),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					vide.action(function(instance)
						listFrame = instance :: Frame
					end),

					new("UIListLayout")({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						vide.action(function(instance)
							listLayout = instance :: UIListLayout
						end),
					}),
					new("Frame")({
						Name = "Header",
						LayoutOrder = 0,
						Size = UDim2.new(1, 0, 0, 32),
						BackgroundColor3 = Theme.SECTION,
						BorderSizePixel = 0,

						Theme.stroke(Theme.BORDER),
						createSeparator(SCRIPT_COLUMN),
						createSeparator(SCRIPT_COLUMN + LINE_COLUMN),
						new("TextLabel")({
							Name = "Script",
							Size = UDim2.new(SCRIPT_COLUMN, 0, 1, 0),
							BackgroundTransparency = 1,
							Text = "Script",
							TextColor3 = Theme.TEXT,
							Font = Enum.Font.SourceSansBold,
							TextSize = 15,
						}),
						new("TextLabel")({
							Name = "Line",
							Size = UDim2.new(LINE_COLUMN, 0, 1, 0),
							Position = UDim2.fromScale(SCRIPT_COLUMN, 0),
							BackgroundTransparency = 1,
							Text = "Line",
							TextColor3 = Theme.TEXT,
							Font = Enum.Font.SourceSansBold,
							TextSize = 15,
						}),
						new("TextLabel")({
							Name = "Text",
							Size = UDim2.new(1 - SCRIPT_COLUMN - LINE_COLUMN, 0, 1, 0),
							Position = UDim2.fromScale(SCRIPT_COLUMN + LINE_COLUMN, 0),
							BackgroundTransparency = 1,
							Text = "Comment",
							TextColor3 = Theme.TEXT,
							Font = Enum.Font.SourceSansBold,
							TextSize = 15,
						}),
					}),
					new("TextLabel")({
						Name = "Empty",
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 44),
						BackgroundColor3 = Theme.ROW,
						BorderSizePixel = 0,
						Text = "No TODO comments found",
						TextColor3 = Theme.MUTED,
						Font = Enum.Font.SourceSans,
						TextSize = 16,
						vide.action(function(label)
							emptyLabel = label :: TextLabel
						end),

						Theme.stroke(Theme.BORDER),
					}),
				}),
			}),
		})

		effect(function()
			scanTick()
			renderRows()
		end)

		cleanup(listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			listFrame.Size = UDim2.new(1, 0, 0, listLayout.AbsoluteContentSize.Y)
		end))

		return root
	end, parent)

	return {
		refresh = refresh,
		destroy = function()
			destroyUi()
		end,
	}
end

const function createWindow(plugin: Plugin)
	const widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		520,
		420,
		390,
		300
	)
	const widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
	widget.Name = "CodeKit TODOs"
	widget.Title = "CodeKit TODOs"
	const panel = createPanel(widget)

	return {
		widget = widget,
		toggle = function()
			widget.Enabled = not widget.Enabled
			if widget.Enabled then
				panel.refresh()
			end
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
