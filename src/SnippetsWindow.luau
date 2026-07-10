-- selene: allow(mixed_table)
const ScriptEditorService = game:GetService("ScriptEditorService")
const TextService = game:GetService("TextService")
const UserInputService = game:GetService("UserInputService")
const vide = require("./vide")
const UiTheme = require("./components/Theme")
const TabButton = require("./components/TabButton")

const new = vide.create
const mount = vide.mount
const source = vide.source
const effect = vide.effect
const cleanup = vide.cleanup

type Snippet = {
	id: string,
	name: string,
	aliases: { string },
	source: string,
	favorite: boolean,
}

type Scope = "global" | "workspace"

type Store = {
	changed: RBXScriptSignal,
	get: (Scope?) -> { Snippet },
	add: (Scope, string, { string }, string) -> Snippet,
	update: (Scope, string, string, { string }, string) -> (),
	remove: (Scope, string) -> (),
	duplicate: (Scope, string) -> (),
	toggleFavorite: (Scope, string) -> (),
	refreshWorkspace: () -> (),
}

const WIDGET_ID = "codekit-snippets"
const EDIT_MODULE_NAME = "_CODEKIT_SNIPPET_EDIT"
const BUTTON_HEIGHT = 32
const ROW_HEIGHT = 34
const NAME_COLUMN = 0.22
const ALIASES_COLUMN = 0.3
const EDIT_COLUMN = 0.18
const DUPLICATE_COLUMN = 0.15
const REMOVE_COLUMN = 0.15
const STAR_IMAGE = "rbxassetid://5639840621"
const SNIPPET_TEMPLATE = [[-- CodeKit snippet
-- variables:
-- ${scriptName} inserts the current script name
-- ${trigger} inserts the alias/name that triggered the snippet
-- ${1:default text} inserts default text

]]

const function parseAliases(text: string): { string }
	const aliases = {}
	for rawAlias in string.gmatch(text, "[^,]+") do
		const alias = string.gsub(rawAlias, "^%s*(.-)%s*$", "%1")
		if alias ~= "" then
			table.insert(aliases, alias)
		end
	end
	return aliases
end

const function aliasesText(aliases: { string }): string
	return table.concat(aliases, ", ")
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
		label.Text = shortenText(fullText, label.AbsoluteSize.X - 14, label.Font, label.TextSize)
	end

	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateText)
	updateText()
end

const function createColumnSeparator(xScale: number)
	return new("Frame")({
		Name = "ColumnSeparator",
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.fromScale(xScale, 0),
		BackgroundColor3 = UiTheme.BORDER,
		BorderSizePixel = 0,
	})
end

const function createButton(props): TextButton
	const baseColor = props.background
	const hoverColor = props.hoverBackground or baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.08)
	return new("TextButton")({
		Name = props.name,
		AnchorPoint = props.anchorPoint,
		Size = props.size,
		Position = props.position,
		BackgroundColor3 = baseColor,
		BorderSizePixel = 0,
		Text = props.text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.SourceSansBold,
		TextSize = props.textSize or 15,
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

const function bindPopup(popup: Frame, popupScale: UIScale, visibleSource)
	effect(function()
		const visible = visibleSource()
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
end

const function createPanel(parent: Instance, store: Store)
	local editModule: ModuleScript? = nil
	local editingSnippet: Snippet? = nil
	local editingAliases: { string } = {}
	local nameBox: TextBox
	local aliasesBox: TextBox
	local searchBox: TextBox
	local listFrame: Frame
	local contentLayout: UIListLayout
	local emptyLabel: TextLabel

	const activeScope = source("global" :: Scope)
	const searchText = source("")
	const snippets = source(store.get("global"))
	const createPopupVisible = source(false)
	const editingVisible = source(false)
	const editingName = source("")
	const deleteSnippet = source(nil :: Snippet?)
	const modalVisible = source(false)

	const function closeCreatePopup()
		if nameBox ~= nil then
			nameBox:ReleaseFocus()
		end
		if aliasesBox ~= nil then
			aliasesBox:ReleaseFocus()
		end
		createPopupVisible(false)
	end

	const function bindEscapeClose(textBox: TextBox)
		cleanup(textBox.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape and createPopupVisible() then
				closeCreatePopup()
			end
		end))
		cleanup(textBox.FocusLost:Connect(function(_, input)
			if input ~= nil and input.KeyCode == Enum.KeyCode.Escape and createPopupVisible() then
				closeCreatePopup()
			end
		end))
	end

	const function refresh()
		snippets(store.get(activeScope()))
	end

	const function cleanupEditModule()
		if editModule ~= nil then
			editModule:Destroy()
			editModule = nil
		end
	end

	const function beginEditing(name: string, aliases: { string }, existing: Snippet?)
		cleanupEditModule()
		editingSnippet = existing
		editingAliases = aliases

		const module = Instance.new("ModuleScript")
		module.Name = name
		module.Source = if existing == nil then SNIPPET_TEMPLATE else existing.source
		module.Parent = game
		editModule = module

		const success, message = ScriptEditorService:OpenScriptDocumentAsync(module)
		assert(success, message)
		editingName(module.Name)
		editingVisible(true)
	end

	const function finishEditing()
		const module = editModule
		if module == nil then
			return
		end

		const sourceText = ScriptEditorService:GetEditorSource(module)
		local document = ScriptEditorService:FindScriptDocument(module)
		if document ~= nil then
			const success, message = document:CloseAsync()
			if not success then
				warn(`Failed to close snippet editor: {message}`)
			end
		end

		const snippet = editingSnippet
		if snippet == nil then
			store.add(activeScope(), module.Name, editingAliases, sourceText)
		else
			store.update(activeScope(), snippet.id, module.Name, editingAliases, sourceText)
		end

		cleanupEditModule()
		editingSnippet = nil
		editingAliases = {}
		editingVisible(false)
		editingName("")
		refresh()
	end

	const function renderRows()
		for _, child in listFrame:GetChildren() do
			if child.Name == "SnippetRow" then
				child:Destroy()
			end
		end

		const query = string.lower(searchText())
		local rowIndex = 0
		for _, snippet in snippets() do
			const haystack = string.lower(`{snippet.name} {aliasesText(snippet.aliases)}`)
			if query ~= "" and string.find(haystack, query, 1, true) == nil then
				continue
			end
			rowIndex += 1
			const row = new("Frame")({
				Name = "SnippetRow",
				LayoutOrder = rowIndex + 1,
				Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				BackgroundColor3 = if rowIndex % 2 == 0 then UiTheme.ROW_ALT else UiTheme.ROW,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Parent = listFrame,

				UiTheme.stroke(UiTheme.BORDER),
				createColumnSeparator(NAME_COLUMN),
				createColumnSeparator(NAME_COLUMN + ALIASES_COLUMN),
				createColumnSeparator(NAME_COLUMN + ALIASES_COLUMN + EDIT_COLUMN),
				createColumnSeparator(NAME_COLUMN + ALIASES_COLUMN + EDIT_COLUMN + DUPLICATE_COLUMN),
				new("TextLabel")({
					Name = "Name",
					Size = UDim2.new(NAME_COLUMN, 0, 1, 0),
					BackgroundTransparency = 1,
					Text = "",
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 18,
					vide.action(function(label)
						bindShortenedText(label :: TextLabel, snippet.name)
					end),
				}),
				new("TextLabel")({
					Name = "Aliases",
					Size = UDim2.new(ALIASES_COLUMN, 0, 1, 0),
					Position = UDim2.fromScale(NAME_COLUMN, 0),
					BackgroundTransparency = 1,
					Text = "",
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 18,
					vide.action(function(label)
						bindShortenedText(label :: TextLabel, aliasesText(snippet.aliases))
					end),
				}),
			})
			task.delay(rowIndex * 0.025, function()
				if row.Parent ~= nil then
					UiTheme.tween(row, { BackgroundTransparency = 0 })
				end
			end)
			new("ImageButton")({
				Name = "Favorite",
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.new(NAME_COLUMN + ALIASES_COLUMN, 5, 0.5, -10),
				BackgroundTransparency = 1,
				Image = STAR_IMAGE,
				ImageColor3 = if snippet.favorite then Color3.fromRGB(255, 213, 79) else UiTheme.MUTED,
				Parent = row,
				Activated = function()
					store.toggleFavorite(activeScope(), snippet.id)
					refresh()
				end,
			})

			createButton({
				parent = row,
				name = "Edit",
				size = UDim2.new(EDIT_COLUMN, -34, 0, 26),
				position = UDim2.new(NAME_COLUMN + ALIASES_COLUMN, 30, 0.5, -13),
				background = Color3.fromRGB(47, 51, 63),
				text = "Edit",
				activated = function()
					beginEditing(snippet.name, snippet.aliases, snippet)
				end,
			})
			createButton({
				parent = row,
				name = "Duplicate",
				size = UDim2.new(DUPLICATE_COLUMN, -12, 0, 26),
				position = UDim2.new(NAME_COLUMN + ALIASES_COLUMN + EDIT_COLUMN, 6, 0.5, -13),
				background = Color3.fromRGB(47, 51, 63),
				text = "Copy",
				activated = function()
					store.duplicate(activeScope(), snippet.id)
					refresh()
				end,
			})
			createButton({
				parent = row,
				name = "Remove",
				size = UDim2.new(REMOVE_COLUMN, -12, 0, 26),
				position = UDim2.new(NAME_COLUMN + ALIASES_COLUMN + EDIT_COLUMN + DUPLICATE_COLUMN, 6, 0.5, -13),
				background = Color3.fromRGB(93, 28, 28),
				stroke = Color3.fromRGB(55, 22, 22),
				text = "Remove",
				activated = function()
					deleteSnippet(snippet)
				end,
			})
		end

		emptyLabel.Visible = rowIndex == 0
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

				new("UIPadding")({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 14),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
				}),
				new("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				new("TextLabel")({
					Name = "Title",
					LayoutOrder = 0,
					Size = UDim2.new(1, 0, 0, 34),
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = "  Snippets",
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
					Name = "Tabs",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,

					new("UIPadding")({
						PaddingLeft = UDim.new(0, 2),
						PaddingRight = UDim.new(0, 2),
						PaddingTop = UDim.new(0, 6),
					}),
					new("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					vide.action(function(tabs)
						const globalTab = TabButton(tabs, "GLOBAL", function()
							activeScope("global")
							refresh()
						end)
						const workspaceTab = TabButton(tabs, "WORKSPACE", function()
							store.refreshWorkspace()
							activeScope("workspace")
							refresh()
						end)

						effect(function()
							const isGlobal = activeScope() == "global"
							globalTab.active(isGlobal)
							workspaceTab.active(not isGlobal)
						end)
					end),
				}),
				new("TextBox")({
					Name = "Search",
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Text = "",
					PlaceholderText = "Search snippets...",
					PlaceholderColor3 = UiTheme.MUTED,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Left,
					vide.action(function(instance)
						searchBox = instance :: TextBox
						cleanup(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
							searchText(searchBox.Text)
						end))
					end),

					UiTheme.stroke(UiTheme.BORDER),
					new("UIPadding")({
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
				}),
				new("Frame")({
					Name = "List",
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 112),
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
							contentLayout = instance :: UIListLayout
						end),
					}),
					new("Frame")({
						Name = "Header",
						LayoutOrder = 0,
						Size = UDim2.new(1, 0, 0, 32),
						BackgroundColor3 = UiTheme.DARK,
						BorderSizePixel = 0,

						UiTheme.stroke(UiTheme.BORDER),
						createColumnSeparator(NAME_COLUMN),
						createColumnSeparator(NAME_COLUMN + ALIASES_COLUMN),
						createColumnSeparator(NAME_COLUMN + ALIASES_COLUMN + EDIT_COLUMN),
						createColumnSeparator(NAME_COLUMN + ALIASES_COLUMN + EDIT_COLUMN + DUPLICATE_COLUMN),
						new("TextLabel")({
							Name = "Name",
							Size = UDim2.new(NAME_COLUMN, 0, 1, 0),
							BackgroundTransparency = 1,
							Text = "Name",
							TextColor3 = UiTheme.TEXT,
							Font = Enum.Font.SourceSansBold,
							TextSize = 19,
						}),
						new("TextLabel")({
							Name = "Aliases",
							Size = UDim2.new(ALIASES_COLUMN, 0, 1, 0),
							Position = UDim2.fromScale(NAME_COLUMN, 0),
							BackgroundTransparency = 1,
							Text = "Aliases",
							TextColor3 = UiTheme.TEXT,
							Font = Enum.Font.SourceSansBold,
							TextSize = 19,
						}),
					}),
					new("TextLabel")({
						Name = "Empty",
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 38),
						BackgroundColor3 = UiTheme.ROW,
						BorderSizePixel = 0,
						Text = "No snippets yet",
						TextColor3 = UiTheme.MUTED,
						Font = Enum.Font.SourceSans,
						TextSize = 17,
						vide.action(function(instance)
							emptyLabel = instance :: TextLabel
						end),

						UiTheme.stroke(UiTheme.BORDER),
					}),
				}),
				new("Frame")({
					Name = "NewRow",
					LayoutOrder = 5,
					Size = UDim2.new(1, 0, 0, 52),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,

					createButton({
						name = "New",
						anchorPoint = Vector2.new(0.5, 0),
						size = UDim2.new(0.62, 0, 0, BUTTON_HEIGHT),
						position = UDim2.new(0.5, 0, 0, 10),
						background = UiTheme.BLUE,
						stroke = UiTheme.BLUE_DARK,
						text = "New",
						activated = function()
							createPopupVisible(true)
						end,
					}),
				}),
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
						const visible = modalVisible()
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
				Name = "CreatePopup",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(370, 390),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = UiTheme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					local popupScale = Instance.new("UIScale")
					popupScale.Parent = popup
					bindPopup(popup :: Frame, popupScale, createPopupVisible)
				end),

				UiTheme.stroke(UiTheme.BORDER),
				createButton({
					name = "Close",
					size = UDim2.fromOffset(58, 24),
					position = UDim2.new(1, -70, 0, 10),
					background = Color3.fromRGB(47, 50, 62),
					text = "Close",
					textSize = 13,
					activated = closeCreatePopup,
				}),
				new("UIPadding")({
					PaddingTop = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 20),
					PaddingRight = UDim.new(0, 20),
				}),
				new("TextLabel")({
					Name = "NameLabel",
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					Text = "Name",
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 24,
				}),
				new("TextBox")({
					Name = "NameBox",
					Size = UDim2.new(1, 0, 0, 108),
					Position = UDim2.fromOffset(0, 31),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Text = "",
					PlaceholderText = "Enter snippet name here...",
					PlaceholderColor3 = UiTheme.MUTED,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					vide.action(function(instance)
						nameBox = instance :: TextBox
						bindEscapeClose(nameBox)
					end),

					new("UIPadding")({
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
				}),
				new("TextLabel")({
					Name = "AliasesLabel",
					Size = UDim2.new(1, 0, 0, 28),
					Position = UDim2.fromOffset(0, 147),
					BackgroundTransparency = 1,
					Text = "Aliases",
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 24,
				}),
				new("TextBox")({
					Name = "AliasesBox",
					Size = UDim2.new(1, 0, 0, 108),
					Position = UDim2.fromOffset(0, 178),
					BackgroundColor3 = UiTheme.DARKER,
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Text = "",
					PlaceholderText = "my_snippet, mysnippet2, asnippet, snip",
					PlaceholderColor3 = UiTheme.MUTED,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSans,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					vide.action(function(instance)
						aliasesBox = instance :: TextBox
						bindEscapeClose(aliasesBox)
					end),

					new("UIPadding")({
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
						PaddingLeft = UDim.new(0, 10),
						PaddingRight = UDim.new(0, 10),
					}),
				}),
				createButton({
					name = "Confirm",
					size = UDim2.new(1, -80, 0, 56),
					position = UDim2.fromOffset(40, 304),
					background = UiTheme.BLUE,
					stroke = UiTheme.BLUE_DARK,
					text = "Confirm",
					textSize = 20,
					activated = function()
						if nameBox.Text == "" then
							return
						end
						createPopupVisible(false)
						beginEditing(nameBox.Text, parseAliases(aliasesBox.Text), nil)
						nameBox.Text = ""
						aliasesBox.Text = ""
					end,
				}),
			}),
			new("Frame")({
				Name = "EditingPopup",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(410, 205),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = UiTheme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					local popupScale = Instance.new("UIScale")
					popupScale.Parent = popup
					bindPopup(popup :: Frame, popupScale, editingVisible)
				end),

				UiTheme.stroke(UiTheme.BORDER),
				new("TextLabel")({
					Name = "YouAreEditing",
					Size = UDim2.new(1, 0, 0, 34),
					Position = UDim2.fromOffset(0, 32),
					BackgroundTransparency = 1,
					Text = "You are editing",
					TextColor3 = UiTheme.MUTED,
					Font = Enum.Font.SourceSans,
					TextSize = 25,
				}),
				new("TextLabel")({
					Name = "SnippetName",
					Size = UDim2.new(1, -24, 0, 44),
					Position = UDim2.fromOffset(12, 66),
					BackgroundTransparency = 1,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 31,
					vide.action(function(label)
						effect(function()
							label.Text = editingName()
						end)
					end),
				}),
				createButton({
					name = "Finish",
					size = UDim2.new(1, -68, 0, 56),
					position = UDim2.new(0, 34, 1, -70),
					background = UiTheme.BLUE,
					stroke = UiTheme.BLUE_DARK,
					text = "Finish",
					textSize = 20,
					activated = finishEditing,
				}),
			}),
			new("Frame")({
				Name = "DeletePopup",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(440, 205),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = UiTheme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					local popupScale = Instance.new("UIScale")
					popupScale.Parent = popup
					bindPopup(popup :: Frame, popupScale, function()
						return deleteSnippet() ~= nil
					end)
				end),

				UiTheme.stroke(UiTheme.BORDER),
				new("TextLabel")({
					Name = "Message",
					Size = UDim2.new(1, 0, 0, 34),
					Position = UDim2.fromOffset(0, 28),
					BackgroundTransparency = 1,
					Text = "Are you sure you want to delete",
					TextColor3 = UiTheme.MUTED,
					Font = Enum.Font.SourceSans,
					TextSize = 25,
				}),
				new("TextLabel")({
					Name = "SnippetName",
					Size = UDim2.new(1, -24, 0, 44),
					Position = UDim2.fromOffset(12, 66),
					BackgroundTransparency = 1,
					TextColor3 = UiTheme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 31,
					vide.action(function(label)
						effect(function()
							const snippet = deleteSnippet()
							label.Text = if snippet == nil then "" else snippet.name
						end)
					end),
				}),
				createButton({
					name = "YesIDo",
					size = UDim2.new(0.66, -18, 0, 56),
					position = UDim2.new(0, 18, 1, -66),
					background = Color3.fromRGB(93, 28, 28),
					stroke = Color3.fromRGB(55, 22, 22),
					text = "Yes, I do",
					textSize = 19,
					activated = function()
						const snippet = deleteSnippet()
						if snippet == nil then
							return
						end
						store.remove(activeScope(), snippet.id)
						deleteSnippet(nil)
						refresh()
					end,
				}),
				createButton({
					name = "NoThanks",
					size = UDim2.new(0.34, -24, 0, 56),
					position = UDim2.new(0.66, 6, 1, -66),
					background = UiTheme.BLUE,
					stroke = UiTheme.BLUE_DARK,
					text = "No thanks",
					textSize = 19,
					activated = function()
						deleteSnippet(nil)
					end,
				}),
			}),
		})

		effect(function()
			modalVisible(createPopupVisible() or editingVisible() or deleteSnippet() ~= nil)
		end)

		effect(function()
			snippets()
			renderRows()
			listFrame.Size = UDim2.new(1, 0, 0, contentLayout.AbsoluteContentSize.Y)
		end)

		cleanup(contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			listFrame.Size = UDim2.new(1, 0, 0, contentLayout.AbsoluteContentSize.Y)
		end))
		cleanup(UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode ~= Enum.KeyCode.Escape or not createPopupVisible() then
				return
			end

			closeCreatePopup()
		end))
		cleanup(store.changed:Connect(refresh))

		return root
	end, parent)

	return {
		destroy = function()
			cleanupEditModule()
			destroyUi()
		end,
	}
end

const function createWindow(plugin: Plugin, store: Store)
	const widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		460,
		330,
		360,
		250
	)
	const widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
	widget.Name = "CodeKit Snippets"
	widget.Title = "CodeKit Snippets"
	const panel = createPanel(widget, store)

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
