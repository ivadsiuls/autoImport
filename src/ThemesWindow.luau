-- selene: allow(mixed_table)
const HttpService = game:GetService("HttpService")
const RunService = game:GetService("RunService")
const TweenService = game:GetService("TweenService")
const vide = require("./vide")
const UiTheme = require("./components/Theme")
const Themes = require("./Themes")
const Data = require("./Data")

const new = vide.create
const mount = vide.mount
const source = vide.source
const effect = vide.effect
const cleanup = vide.cleanup

const WIDGET_ID = "codekit-themes"
const CUSTOM_THEMES_KEY = "CodeKitCustomThemes"
const CARD_HEIGHT = 126
const CARD_PADDING = 10
const CARD_ORDER_OFFSET = 4
const PREVIEW_TEXT_SIZE = 14
const PREVIEW_LINE_HEIGHT = 16
const MAX_Z_INDEX = 2_147_483_647
const MIN_LOADING_TIME = 0.25

const function applyTheme(theme)
	const studio = settings().Studio
	for name, color in theme.colors do
		const nextColor = Color3.fromRGB(color[1], color[2], color[3])
		const success = pcall(function()
			studio[name] = nextColor
		end)
		if not success then
			warn(`{name} is not a valid theme color`)
		end
	end
	print(`Successfully changed your Script Editor theme to {theme.name}!`)
end

const function getCurrentTheme(colors)
	const studio = settings().Studio
	const currentColors = {}
	for name in colors do
		const color = studio[name]
		currentColors[name] = {
			math.round(color.R * 255),
			math.round(color.G * 255),
			math.round(color.B * 255),
		}
	end
	return currentColors
end

const function normalizeThemePayload(decoded)
	if typeof(decoded) ~= "table" then
		return nil
	end

	if typeof(decoded[1]) == "table" and typeof(decoded[1][1]) == "table" then
		decoded = decoded[1][1]
	elseif typeof(decoded[1]) == "table" then
		decoded = decoded[1]
	end

	const colors = {}
	for name, color in decoded do
		if typeof(name) ~= "string" or typeof(color) ~= "table" then
			continue
		end
		if typeof(color[1]) == "number" and typeof(color[2]) == "number" and typeof(color[3]) == "number" then
			colors[name] = { color[1], color[2], color[3] }
		end
	end
	return colors
end

const function getThemeColor(theme, name: string, fallback: Color3): Color3
	const color = theme.colors[name]
	if color == nil then
		return fallback
	end
	return Color3.fromRGB(color[1], color[2], color[3])
end

const function toHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

const function getPreviewLines(theme): { string }
	const keyword = toHex(getThemeColor(theme, "Luau Keyword Color", Color3.fromRGB(198, 120, 221)))
	const functionColor = toHex(getThemeColor(theme, "Function Name Color", Color3.fromRGB(97, 175, 239)))
	const builtin = toHex(getThemeColor(theme, "Built-in Function Color", Color3.fromRGB(86, 182, 194)))
	const stringColor = toHex(getThemeColor(theme, "String Color", Color3.fromRGB(152, 195, 121)))
	const comment = toHex(getThemeColor(theme, "Comment Color", Color3.fromRGB(92, 99, 112)))
	const bool = toHex(getThemeColor(theme, "Bool Color", Color3.fromRGB(209, 154, 102)))
	const number = toHex(getThemeColor(theme, "Number Color", Color3.fromRGB(209, 154, 102)))
	const method = toHex(getThemeColor(theme, "Method Color", Color3.fromRGB(97, 175, 239)))

	return {
		`<font color="{keyword}">const</font> <font color="{functionColor}">Theme</font> = <font color="{builtin}">require</font>(<font color="{stringColor}">"CodeKit"</font>)`,
		`<font color="{comment}">-- syntax preview</font>`,
		`<font color="{keyword}">local</font> <font color="{functionColor}">enabled</font> = <font color="{bool}">true</font>`,
		`<font color="{keyword}">if</font> <font color="{functionColor}">enabled</font> <font color="{keyword}">then</font> <font color="{functionColor}">Theme</font>:<font color="{method}">apply</font>(<font color="{number}">255</font>) <font color="{keyword}">end</font>`,
	}
end

const function createButton(props): TextButton
	const baseColor = props.background
	const hoverColor = props.hoverBackground or baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.08)
	return new("TextButton")({
		Name = props.name,
		Size = props.size,
		Position = props.position,
		BackgroundColor3 = baseColor,
		BorderSizePixel = 0,
		Text = props.text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.SourceSansBold,
		TextSize = props.textSize or 14,
		AutoButtonColor = true,
		Activated = props.activated,
		Parent = props.parent,
		vide.action(function(button)
			cleanup(button.MouseEnter:Connect(function()
				UiTheme.tween(button, { BackgroundColor3 = hoverColor })
			end))
			cleanup(button.MouseLeave:Connect(function()
				UiTheme.tween(button, { BackgroundColor3 = baseColor })
			end))
		end),

		UiTheme.stroke(props.stroke or UiTheme.BORDER),
	}) :: TextButton
end

const function createPreviewLine(
	parent: Instance,
	text: string,
	lineNumber: number,
	selection: Color3,
	foreground: Color3
): TextLabel
	const highlighted = lineNumber == 3
	return new("TextLabel")({
		Name = if highlighted then "SelectedLine" else `Line{lineNumber}`,
		Size = if highlighted
			then UDim2.fromOffset(0, PREVIEW_LINE_HEIGHT)
			else UDim2.new(1, -20, 0, PREVIEW_LINE_HEIGHT),
		AutomaticSize = if highlighted then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		Position = UDim2.fromOffset(16, 4 + (lineNumber - 1) * PREVIEW_LINE_HEIGHT),
		BackgroundColor3 = selection,
		BackgroundTransparency = if highlighted then 0 else 1,
		BorderSizePixel = 0,
		Text = text,
		RichText = true,
		TextColor3 = foreground,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.Code,
		TextSize = PREVIEW_TEXT_SIZE,
		Parent = parent,
	}) :: TextLabel
end

const function createThemeCard(parent: Instance, theme, order: number, isCustom: boolean, onUse, onEdit, onDelete)
	const background = getThemeColor(theme, "Background Color", Color3.fromRGB(40, 44, 52))
	const currentLine = getThemeColor(theme, "Current Line Highlight Color", background)
	const selection = getThemeColor(theme, "Selection Background Color", currentLine)
	const foreground = getThemeColor(theme, "Text Color", Color3.fromRGB(232, 235, 245))
	const previewLines = getPreviewLines(theme)

	return new("Frame")({
		Name = "ThemeCard",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundColor3 = background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,

		UiTheme.stroke(UiTheme.BORDER),
		new("Frame")({
			Name = "Preview",
			Size = UDim2.new(1, 0, 1, -42),
			BackgroundColor3 = background,
			BorderSizePixel = 0,

			new("Frame")({
				Name = "Ruler",
				Size = UDim2.new(0, 1, 1, 0),
				Position = UDim2.fromOffset(8, 0),
				BackgroundColor3 = currentLine,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
			}),
			vide.action(function(preview)
				for lineNumber, lineText in previewLines do
					createPreviewLine(preview, lineText, lineNumber, selection, foreground)
				end
			end),
		}),
		new("Frame")({
			Name = "BottomBar",
			Size = UDim2.new(1, 0, 0, 42),
			Position = UDim2.new(0, 0, 1, -42),
			BackgroundColor3 = UiTheme.DARK,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
		}),
		new("TextLabel")({
			Name = "Name",
			Size = UDim2.new(1, if isCustom then -270 else -160, 0, 34),
			Position = UDim2.new(0, CARD_PADDING, 1, -42),
			BackgroundTransparency = 1,
			Text = theme.name,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.SourceSansBold,
			TextSize = 22,
		}),
		new("TextButton")({
			Name = "Use",
			Size = UDim2.fromOffset(if isCustom then 76 else 104, 30),
			Position = UDim2.new(1, -CARD_PADDING - if isCustom then 240 else 104, 1, -40),
			BackgroundColor3 = UiTheme.BLUE,
			BorderSizePixel = 0,
			Text = "Use",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.SourceSansBold,
			TextSize = 13,
			AutoButtonColor = true,
			Activated = function()
				onUse(theme)
			end,

			UiTheme.stroke(UiTheme.BLUE_DARK),
		}),
		new("TextButton")({
			Name = "Edit",
			Size = UDim2.fromOffset(76, 30),
			Position = UDim2.new(1, -CARD_PADDING - 158, 1, -40),
			BackgroundColor3 = Color3.fromRGB(47, 51, 63),
			BorderSizePixel = 0,
			Text = "Edit",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.SourceSansBold,
			TextSize = 13,
			AutoButtonColor = true,
			Visible = isCustom,
			Activated = function()
				onEdit(theme)
			end,

			UiTheme.stroke(UiTheme.BORDER),
		}),
		new("TextButton")({
			Name = "Delete",
			Size = UDim2.fromOffset(72, 30),
			Position = UDim2.new(1, -CARD_PADDING - 78, 1, -40),
			BackgroundColor3 = Color3.fromRGB(93, 28, 28),
			BorderSizePixel = 0,
			Text = "Delete",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.SourceSansBold,
			TextSize = 13,
			AutoButtonColor = true,
			Visible = isCustom,
			Activated = function()
				onDelete(theme)
			end,

			UiTheme.stroke(Color3.fromRGB(55, 22, 22)),
		}),
	})
end

const function createPanel(parent: Instance, plugin: Plugin)
	local contentFrame: ScrollingFrame
	local importNameBox: TextBox
	local importJsonBox: TextBox
	local importJsonScroll: ScrollingFrame
	local importTitleLabel: TextLabel
	local exportBox: TextBox
	local exportScroll: ScrollingFrame
	local loadingImage: ImageLabel

	const selectedTheme = source(nil)
	const customThemes = source(Data.load(plugin, CUSTOM_THEMES_KEY, {}))
	const searchQuery = source("")
	const importVisible = source(false)
	const editingTheme = source(nil)
	const exportVisible = source(false)
	const loadingVisible = source(false)
	const previousTheme = source(nil)
	local loadingAnimationId = 0
	local loadingStartedAt = 0

	const function startLoading()
		loadingAnimationId += 1
		const animationId = loadingAnimationId
		loadingStartedAt = os.clock()
		loadingVisible(true)
		loadingImage.Size = UDim2.fromOffset(62, 62)

		task.spawn(function()
			while animationId == loadingAnimationId and loadingVisible() do
				const grow = TweenService:Create(
					loadingImage,
					TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Size = UDim2.fromOffset(86, 86) }
				)
				grow:Play()
				grow.Completed:Wait()
				if animationId ~= loadingAnimationId or not loadingVisible() then
					return
				end

				const shrink = TweenService:Create(
					loadingImage,
					TweenInfo.new(1.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Size = UDim2.fromOffset(62, 62) }
				)
				shrink:Play()
				shrink.Completed:Wait()
			end
		end)
	end

	const function stopLoading()
		loadingAnimationId += 1
		loadingVisible(false)
	end

	const function loadTheme(theme)
		startLoading()
		task.spawn(function()
			RunService.Heartbeat:Wait()
			task.wait(0.1)
			applyTheme(theme)
			const remaining = MIN_LOADING_TIME - (os.clock() - loadingStartedAt)
			if remaining > 0 then
				task.wait(remaining)
			end
			stopLoading()
		end)
	end

	const function saveCustomThemes(nextThemes)
		Data.save(plugin, CUSTOM_THEMES_KEY, nextThemes)
		customThemes(nextThemes)
	end

	const function openThemeEditor(theme)
		editingTheme(theme)
		importNameBox.Text = if theme == nil then "" else theme.name
		importJsonBox.Text = if theme == nil then "" else HttpService:JSONEncode(theme.colors)
		importJsonScroll.CanvasPosition = Vector2.zero
		importVisible(true)
	end

	const function deleteTheme(theme)
		const nextThemes = {}
		for _, customTheme in customThemes() do
			if customTheme ~= theme then
				table.insert(nextThemes, customTheme)
			end
		end
		saveCustomThemes(nextThemes)
	end

	const function getAllThemes()
		const allThemes = {}
		for _, theme in Themes do
			table.insert(allThemes, theme)
		end
		for _, theme in customThemes() do
			table.insert(allThemes, theme)
		end
		return allThemes
	end

	const function renderThemes()
		for _, child in contentFrame:GetChildren() do
			if child.Name == "ThemeCard" or child.Name == "NoResults" then
				child:Destroy()
			end
		end

		const query = string.lower(string.gsub(searchQuery(), "^%s*(.-)%s*$", "%1"))
		local themeIndex = 0
		for _, theme in Themes do
			if query ~= "" and string.find(string.lower(theme.name), query, 1, true) == nil then
				continue
			end

			themeIndex += 1
			createThemeCard(contentFrame, theme, themeIndex + CARD_ORDER_OFFSET, false, function(nextTheme)
				selectedTheme(nextTheme)
			end, function() end, function() end)
		end
		for _, theme in customThemes() do
			if query ~= "" and string.find(string.lower(theme.name), query, 1, true) == nil then
				continue
			end

			themeIndex += 1
			createThemeCard(contentFrame, theme, themeIndex + CARD_ORDER_OFFSET, true, function(nextTheme)
				selectedTheme(nextTheme)
			end, openThemeEditor, deleteTheme)
		end

		if themeIndex == 0 then
			new("TextLabel")({
				Name = "NoResults",
				LayoutOrder = CARD_ORDER_OFFSET,
				Size = UDim2.new(1, 0, 0, 50),
				BackgroundColor3 = UiTheme.SECTION,
				BorderSizePixel = 0,
				Text = "No themes match your search.",
				TextColor3 = UiTheme.MUTED,
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				UiTheme.stroke(UiTheme.BORDER),
			})
		end
	end

	const destroyUi = mount(function()
		const root = new("Frame")({
			Name = "Root",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = UiTheme.DARK,
			BorderSizePixel = 0,

			new("Frame")({
				Name = "Accent",
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = UiTheme.BLUE,
				BorderSizePixel = 0,
			}),
			new("ScrollingFrame")({
				Name = "Content",
				Size = UDim2.new(1, 0, 1, -3),
				Position = UDim2.fromOffset(0, 3),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				vide.action(function(instance)
					contentFrame = instance :: ScrollingFrame
				end),

				new("UIPadding")({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}),
				new("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				new("TextLabel")({
					Name = "Title",
					LayoutOrder = 0,
					Size = UDim2.new(1, 0, 0, 34),
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = "  Themes",
					Font = Enum.Font.SourceSansSemibold,
					TextSize = 20,
					TextColor3 = UiTheme.TEXT,
					BackgroundColor3 = UiTheme.DARK,
					BorderSizePixel = 0,
				}),
				new("Frame")({
					Name = "TitleSeparator",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 2),
					BackgroundColor3 = UiTheme.BORDER,
					BorderSizePixel = 0,
				}),
				new("Frame")({
					Name = "Actions",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,

					createButton({
						name = "Add",
						size = UDim2.new(0.33, -5, 0, 28),
						position = UDim2.fromOffset(0, 3),
						background = UiTheme.BLUE,
						stroke = UiTheme.BLUE_DARK,
						text = "Add",
						activated = function()
							openThemeEditor(nil)
						end,
					}),
					createButton({
						name = "Export",
						size = UDim2.new(0.33, -5, 0, 28),
						position = UDim2.new(0.33, 3, 0, 3),
						background = Color3.fromRGB(47, 50, 62),
						text = "Export",
						activated = function()
							exportBox.Text = HttpService:JSONEncode(getCurrentTheme(Themes[1].colors))
							exportScroll.CanvasPosition = Vector2.zero
							exportVisible(true)
						end,
					}),
					createButton({
						name = "Undo",
						size = UDim2.new(0.34, -5, 0, 28),
						position = UDim2.new(0.66, 6, 0, 3),
						background = Color3.fromRGB(47, 50, 62),
						text = "Undo",
						activated = function()
							const theme = previousTheme()
							if theme ~= nil then
								loadTheme(theme)
								previousTheme(nil)
							end
						end,
					}),
				}),
				new("TextBox")({
					Name = "Search",
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					PlaceholderText = "Search themes...",
					PlaceholderColor3 = UiTheme.MUTED,
					Text = "",
					TextColor3 = UiTheme.TEXT,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.SourceSans,
					TextSize = 16,
					vide.action(function(searchBox)
						cleanup(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
							searchQuery(searchBox.Text)
						end))
					end),

					UiTheme.stroke(UiTheme.BORDER),
					new("UIPadding")({
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
				}),
				vide.action(function()
					effect(function()
						customThemes()
						searchQuery()
						renderThemes()
					end)
				end),
			}),
			new("Frame")({
				Name = "ModalDimmer",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Active = true,
				Visible = false,
				vide.action(function(dimmer)
					effect(function()
						const visible = selectedTheme() ~= nil or importVisible() or exportVisible() or loadingVisible()
						if visible then
							dimmer.Visible = true
							dimmer.BackgroundTransparency = 1
							UiTheme.tween(dimmer, { BackgroundTransparency = 0.35 })
						else
							dimmer.Visible = false
						end
					end)
				end),
			}),
			new("Frame")({
				Name = "ConfirmTheme",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(390, 190),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = UiTheme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					const popupScale = Instance.new("UIScale")
					popupScale.Parent = popup
					effect(function()
						const visible = selectedTheme() ~= nil
						if visible then
							popup.Visible = true
							popupScale.Scale = 0.96
							popup.BackgroundTransparency = 0.08
							UiTheme.tween(popupScale, { Scale = 1 })
							UiTheme.tween(popup, { BackgroundTransparency = 0 })
						else
							popup.Visible = false
						end
					end)
				end),

				UiTheme.stroke(UiTheme.BORDER),
				new("TextLabel")({
					Name = "Message",
					Size = UDim2.new(1, 0, 0, 34),
					Position = UDim2.fromOffset(0, 28),
					BackgroundTransparency = 1,
					Text = "Use this Script Editor theme?",
					TextColor3 = UiTheme.MUTED,
					Font = Enum.Font.SourceSans,
					TextSize = 24,
				}),
				new("TextLabel")({
					Name = "ThemeName",
					Size = UDim2.new(1, -24, 0, 42),
					Position = UDim2.fromOffset(12, 64),
					BackgroundTransparency = 1,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 30,
					vide.action(function(label)
						effect(function()
							const theme = selectedTheme()
							label.Text = if theme == nil then "" else theme.name
						end)
					end),
				}),
				createButton({
					name = "Use",
					size = UDim2.new(0.5, -24, 0, 40),
					position = UDim2.new(0, 18, 1, -52),
					background = UiTheme.BLUE,
					stroke = UiTheme.BLUE_DARK,
					text = "Use",
					textSize = 16,
					activated = function()
						const theme = selectedTheme()
						if theme == nil then
							return
						end
						previousTheme({
							name = "Previous",
							colors = getCurrentTheme(theme.colors),
						})
						selectedTheme(nil)
						loadTheme(theme)
					end,
				}),
				createButton({
					name = "Cancel",
					size = UDim2.new(0.5, -24, 0, 40),
					position = UDim2.new(0.5, 6, 1, -52),
					background = Color3.fromRGB(47, 50, 62),
					text = "Cancel",
					textSize = 16,
					activated = function()
						selectedTheme(nil)
					end,
				}),
			}),
			new("Frame")({
				Name = "ImportTheme",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(440, 420),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = UiTheme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					effect(function()
						popup.Visible = importVisible()
					end)
				end),

				UiTheme.stroke(UiTheme.BORDER),
				new("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, -24, 0, 32),
					Position = UDim2.fromOffset(12, 10),
					BackgroundTransparency = 1,
					Text = "",
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 24,
					vide.action(function(label)
						importTitleLabel = label :: TextLabel
						effect(function()
							label.Text = if editingTheme() == nil then "Add Theme" else "Edit Theme"
						end)
					end),
				}),
				new("TextBox")({
					Name = "NameBox",
					Size = UDim2.new(1, -32, 0, 34),
					Position = UDim2.fromOffset(16, 52),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Text = "",
					PlaceholderText = "Theme name",
					PlaceholderColor3 = UiTheme.MUTED,
					TextColor3 = UiTheme.TEXT,
					TextXAlignment = Enum.TextXAlignment.Left,
					Font = Enum.Font.SourceSans,
					TextSize = 17,
					vide.action(function(instance)
						importNameBox = instance :: TextBox
					end),
					UiTheme.stroke(UiTheme.BORDER),
					new("UIPadding")({ PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
				}),
				new("ScrollingFrame")({
					Name = "JsonScroll",
					Size = UDim2.new(1, -32, 0, 270),
					Position = UDim2.fromOffset(16, 94),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ScrollBarThickness = 6,
					Active = true,
					ClipsDescendants = true,
					vide.action(function(instance)
						importJsonScroll = instance :: ScrollingFrame
					end),
					UiTheme.stroke(UiTheme.BORDER),
					new("UIListLayout")({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					new("TextBox")({
						Name = "JsonBox",
						LayoutOrder = 1,
						Size = UDim2.new(1, -8, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClearTextOnFocus = false,
						MultiLine = true,
						TextEditable = true,
						TextWrapped = true,
						Text = "",
						PlaceholderText = "Paste theme JSON here",
						PlaceholderColor3 = UiTheme.MUTED,
						TextColor3 = UiTheme.TEXT,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						Font = Enum.Font.SourceSans,
						TextSize = 15,
						vide.action(function(instance)
							importJsonBox = instance :: TextBox
						end),
						new("UIPadding")({
							PaddingTop = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 10),
							PaddingRight = UDim.new(0, 10),
						}),
					}),
				}),
				createButton({
					name = "Save",
					size = UDim2.new(0.5, -24, 0, 38),
					position = UDim2.new(0, 16, 1, -50),
					background = UiTheme.BLUE,
					stroke = UiTheme.BLUE_DARK,
					text = "Save",
					textSize = 16,
					activated = function()
						if importNameBox.Text == "" then
							return
						end
						local decoded
						const ok = pcall(function()
							decoded = HttpService:JSONDecode(importJsonBox.Text)
						end)
						if not ok then
							warn("Theme JSON is invalid")
							return
						end
						const colors = normalizeThemePayload(decoded)
						if colors == nil then
							warn("Theme JSON did not contain colors")
							return
						end
						const nextThemes = {}
						const currentTheme = editingTheme()
						if currentTheme == nil then
							for _, theme in customThemes() do
								table.insert(nextThemes, theme)
							end
							table.insert(nextThemes, {
								name = importNameBox.Text,
								colors = colors,
							})
						else
							for _, theme in customThemes() do
								table.insert(nextThemes, if theme == currentTheme
									then { name = importNameBox.Text, colors = colors }
									else theme)
							end
						end
						saveCustomThemes(nextThemes)
						importVisible(false)
						editingTheme(nil)
						importNameBox.Text = ""
						importJsonBox.Text = ""
					end,
				}),
				createButton({
					name = "Cancel",
					size = UDim2.new(0.5, -24, 0, 38),
					position = UDim2.new(0.5, 8, 1, -50),
					background = Color3.fromRGB(47, 50, 62),
					text = "Cancel",
					textSize = 16,
					activated = function()
						importVisible(false)
						editingTheme(nil)
					end,
				}),
			}),
			new("Frame")({
				Name = "ExportTheme",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(440, 420),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = UiTheme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					effect(function()
						popup.Visible = exportVisible()
					end)
				end),

				UiTheme.stroke(UiTheme.BORDER),
				new("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, -24, 0, 32),
					Position = UDim2.fromOffset(12, 10),
					BackgroundTransparency = 1,
					Text = "Export Current Theme",
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 23,
				}),
				new("ScrollingFrame")({
					Name = "ExportScroll",
					Size = UDim2.new(1, -32, 0, 320),
					Position = UDim2.fromOffset(16, 52),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ScrollBarThickness = 6,
					Active = true,
					ClipsDescendants = true,
					vide.action(function(instance)
						exportScroll = instance :: ScrollingFrame
					end),
					UiTheme.stroke(UiTheme.BORDER),
					new("UIListLayout")({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					new("TextBox")({
						Name = "ExportBox",
						LayoutOrder = 1,
						Size = UDim2.new(1, -8, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClearTextOnFocus = false,
						MultiLine = true,
						TextEditable = false,
						TextWrapped = true,
						Text = "",
						TextColor3 = UiTheme.TEXT,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						Font = Enum.Font.SourceSans,
						TextSize = 15,
						vide.action(function(instance)
							exportBox = instance :: TextBox
						end),
						new("UIPadding")({
							PaddingTop = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 10),
							PaddingRight = UDim.new(0, 10),
						}),
					}),
				}),
				createButton({
					name = "Close",
					size = UDim2.new(1, -32, 0, 38),
					position = UDim2.new(0, 16, 1, -48),
					background = UiTheme.BLUE,
					stroke = UiTheme.BLUE_DARK,
					text = "Close",
					textSize = 16,
					activated = function()
						exportVisible(false)
					end,
				}),
			}),
			new("Frame")({
				Name = "LoadingPopup",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = UiTheme.DARKER,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Active = true,
				Visible = false,
				ZIndex = MAX_Z_INDEX - 1,
				vide.action(function(popup)
					effect(function()
						popup.Visible = loadingVisible()
					end)
				end),

				new("ImageLabel")({
					Name = "LoadingImage",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(62, 62),
					Position = UDim2.fromScale(0.5, 0.5),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = "rbxassetid://83388302238556",
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = MAX_Z_INDEX,
					vide.action(function(image)
						loadingImage = image :: ImageLabel
					end),
				}),
				new("TextLabel")({
					Name = "LoadingLabel",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(180, 24),
					Position = UDim2.new(0.5, 0, 0.5, 58),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = "Loading...",
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansSemibold,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = MAX_Z_INDEX,
				}),
			}),
		})

		return root
	end, parent)

	return {
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
		420,
		330,
		320,
		250
	)
	const widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
	widget.Name = "CodeKit Themes"
	widget.Title = "CodeKit Themes"
	const panel = createPanel(widget, plugin)

	return {
		widget = widget,
		toggle = function()
			widget.Enabled = not widget.Enabled
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
