-- selene: allow(mixed_table)
const ScriptEditorService = game:GetService("ScriptEditorService")
const Types = require("./Types")
const vide = require("./vide")
const Theme = require("./components/Theme")
const Section = require("./components/Section")
const ToggleSetting = require("./components/ToggleSetting")
const DropdownSetting = require("./components/DropdownSetting")
const TextBoxSetting = require("./components/TextBoxSetting")
const LargeTextBoxSetting = require("./components/LargeTextBoxSetting")
const FooterButton = require("./components/FooterButton")
const TabButton = require("./components/TabButton")
const SnippetsWindow = require("./SnippetsWindow")
const ThemesWindow = require("./ThemesWindow")
const TodoWindow = require("./TodoWindow")
const RefactorWindow = require("./RefactorWindow")

const new = vide.create
const mount = vide.mount
const createRoot = vide.root
const source = vide.source
const effect = vide.effect
const cleanup = vide.cleanup

type Store = {
	changed: RBXScriptSignal,
	get: () -> Types.Settings,
	getGlobal: () -> Types.Settings,
	getWorkspace: () -> Types.Settings,
	hasWorkspace: () -> boolean,
	update: (Types.SettingsScope, string, any) -> (),
	reset: () -> (),
	refreshWorkspace: () -> (),
	destroy: () -> (),
}

type WindowResources = {
	snippetsStore: any,
	refactorQueue: any,
}

const WIDGET_ID = "codekit-settings"
const BACK_ICON = "rbxassetid://6031091004"

const IMPORT_SORT_OPTIONS = {
	"longestFirst",
	"longestLast",
	"alphabetical",
	"reverseAlphabetical",
	"constantsFirst",
	"localsFirst",
	"pathFirst",
	"pathLast",
	"identifierFirst",
	"identifierLast",
}

const CASING_OPTIONS = { "preserve", "camel", "pascal", "snake" }
const INDEXING_OPTIONS = { "WaitForChild", "FindFirstChild", "Direct" }
const MODULE_REQUIRE_OPTIONS = { "dynamic", "relative", "absolute" }
const BUILDER_ICON_FONT = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"
const PAGE_TABS = {
	{ name = "settings", label = "Settings", icon = "gear" },
	{ name = "snippets", label = "Snippets", icon = "rectangle-list-pencil" },
	{ name = "themes", label = "Themes", icon = "paint-brush" },
	{ name = "todos", label = "TODO", icon = "rectangle-list" },
	{ name = "refactor", label = "Refactor", icon = "arrow-rotate-right" },
}

const function builderIcon(name: string): string
	return `<font family="{BUILDER_ICON_FONT}">{name}</font>`
end

const function parseList(text: string): { string }
	local names = {}
	for rawName in string.gmatch(text, "[^,%s]+") do
		const name = string.gsub(rawName, "^['\"]?(.-)['\"]?$", "%1")
		if name ~= "" then
			table.insert(names, name)
		end
	end
	return names
end

const function bindAutomaticSectionHeight(section)
	const function updateHeight()
		section.setHeight(section.layout.AbsoluteContentSize.Y)
	end

	cleanup(section.layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateHeight))
	updateHeight()
end

const function createWindow(plugin: Plugin, store: Store, resources: WindowResources)
	const widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		390,
		540,
		330,
		420
	)
	const widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
	widget.Name = "CodeKit"
	widget.Title = "CodeKit"

	local scopeTabs: Frame
	local contentFrame: Frame
	local footerFrame: Frame
	local titleLabel: TextLabel
	local backButton: ImageButton
	local additionalServicesBox: TextBox
	local customServiceAliasesBox: TextBox
	local clientDirectoriesBox: TextBox
	local namesBox: TextBox
	local noImportTagBox: TextBox
	local customNameAttributeBox: TextBox
	local prefixBox: TextBox
	local servicePrefixBox: TextBox
	local modulePrefixBox: TextBox
	local instancePrefixBox: TextBox
	local definitionPrefixBox: TextBox
	local toggles = {}
	local dropdowns = {}
	local sectionDropdowns = {}
	local activePanel = nil
	local activePage = "settings"
	local destroyPageRoot: (() -> ())? = nil
	local pageButtons = {}
	local layoutEditModule: ModuleScript? = nil
	local layoutEditScope: Types.SettingsScope? = nil
	local layoutEditSource = ""
	local layoutEditRunning = false

	const activeScope = (source("global" :: Types.SettingsScope) :: any) :: (arg: Types.SettingsScope?) -> Types.SettingsScope
	const currentSettings = source(store.getGlobal())
	const renderTick = source(0)
	const resetSettingsVisible = source(false)

	const function update(key: string, value: any)
		store.update(activeScope(), key, value)
	end

	const function updateSection(sectionName: string, key: string, value: any)
		const nextSection = table.clone(currentSettings()[sectionName])
		nextSection[key] = value
		update(sectionName, nextSection)
	end

	const function closeDropdowns()
		for _, dropdown in dropdowns do
			dropdown.close()
		end
		for _, dropdown in sectionDropdowns do
			dropdown.close()
		end
	end

	const function saveImportLayoutFromEditor()
		const module = layoutEditModule
		const scope = layoutEditScope
		if module == nil or scope == nil then
			return
		end

		local sourceText = module.Source
		pcall(function()
			sourceText = ScriptEditorService:GetEditorSource(module)
		end)
		if sourceText == layoutEditSource then
			return
		end

		layoutEditSource = sourceText
		store.update(scope, "importLayout", sourceText)
	end

	const function openImportLayoutEditor()
		if layoutEditModule ~= nil then
			ScriptEditorService:OpenScriptDocumentAsync(layoutEditModule)
			return
		end

		const module = Instance.new("ModuleScript")
		module.Name = "_CODEKIT_IMPORT_LAYOUT"
		module.Source = currentSettings().importLayout
		module.Parent = game
		layoutEditModule = module
		layoutEditScope = activeScope()
		layoutEditSource = module.Source
		ScriptEditorService:OpenScriptDocumentAsync(module)

		if layoutEditRunning then
			return
		end
		layoutEditRunning = true
		task.spawn(function()
			while layoutEditModule ~= nil do
				saveImportLayoutFromEditor()
				task.wait(0.5)
			end
			layoutEditRunning = false
		end)
	end

	const function destroyImportLayoutEditor()
		saveImportLayoutFromEditor()
		if layoutEditModule ~= nil then
			layoutEditModule:Destroy()
			layoutEditModule = nil
		end
		layoutEditScope = nil
	end

	const function addToggle(section, label: string, index: number, settingKey: string)
		const toggle = ToggleSetting(section.body, label, index, function()
			update(settingKey, not currentSettings()[settingKey])
		end)
		toggles[settingKey] = toggle
		return toggle
	end

	const function addSectionToggle(section, label: string, index: number, sectionName: string, settingKey: string)
		const key = `{sectionName}.{settingKey}`
		const toggle = ToggleSetting(section.body, label, index, function()
			updateSection(sectionName, settingKey, not currentSettings()[sectionName][settingKey])
		end)
		toggles[key] = toggle
		return toggle
	end

	const function addDropdown(section, label: string, index: number, settingKey: string, options: { string })
		const dropdown = DropdownSetting(section.body, label, index, options, function(value)
			if settingKey == "sectionPadding" then
				update(settingKey, tonumber(value) or 1)
			elseif settingKey == "indexing.clientScripts" then
				const nextIndexing = table.clone(currentSettings().indexing)
				nextIndexing.clientScripts = value
				update("indexing", nextIndexing)
			elseif settingKey == "indexing.serverScripts" then
				const nextIndexing = table.clone(currentSettings().indexing)
				nextIndexing.serverScripts = value
				update("indexing", nextIndexing)
			else
				update(settingKey, value)
			end
		end, nil)
		dropdowns[settingKey] = dropdown
		return dropdown
	end

	const function addSectionDropdown(section, label: string, index: number, sectionName: string, settingKey: string, options: { string })
		const key = `{sectionName}.{settingKey}`
		const dropdown = DropdownSetting(section.body, label, index, options, function(value)
			updateSection(sectionName, settingKey, value)
		end, nil)
		sectionDropdowns[key] = dropdown
		return dropdown
	end

	const function addActionButton(parent: Instance, label: string, activated: () -> ())
		new("TextButton")({
			Name = label,
			Size = UDim2.new(1, 0, 0, Theme.ROW_HEIGHT),
			BackgroundColor3 = Theme.ROW_ALT,
			BorderSizePixel = 0,
			Text = label,
			TextColor3 = Theme.TEXT,
			Font = Enum.Font.SourceSansBold,
			TextSize = 15,
			AutoButtonColor = true,
			Activated = activated,
			Parent = parent,

			Theme.stroke(Theme.BORDER),
		})
	end

	const function clearContent()
		closeDropdowns()
		for _, child in contentFrame:GetChildren() do
			child:Destroy()
		end
		toggles = {}
		dropdowns = {}
		sectionDropdowns = {}
		additionalServicesBox = nil
		customServiceAliasesBox = nil
		clientDirectoriesBox = nil
		namesBox = nil
		noImportTagBox = nil
		customNameAttributeBox = nil
		prefixBox = nil
		servicePrefixBox = nil
		modulePrefixBox = nil
		instancePrefixBox = nil
		definitionPrefixBox = nil
	end

	const function createSectionSettings(parent: Instance, title: string, sectionName: string, withEnabled: boolean?)
		const section = Section(parent, title, 0)
		local index = 1
		if withEnabled then
			addSectionToggle(section, "Enabled", index, sectionName, "enabled")
			index += 1
		end
		if sectionName ~= "definitions" then
			addSectionToggle(section, "Use const", index, sectionName, "useConst")
			index += 1
		else
			addSectionToggle(section, "Use const", index, sectionName, "useConst")
			index += 1
		end
		addSectionDropdown(section, "Sort order", index, sectionName, "sortOrder", IMPORT_SORT_OPTIONS)
		index += 1
		addSectionDropdown(section, "Casing", index, sectionName, "casing", CASING_OPTIONS)
		index += 1
		addSectionToggle(section, "Type annotation", index, sectionName, "typeAnnotation")
		index += 1
		addSectionToggle(section, "Type assertion", index, sectionName, "typeAssertion")
		index += 1

		local prefixSettingBox: TextBox
		prefixSettingBox = TextBoxSetting({
			parent = section.body,
			name = "Prefix",
			index = index,
			focusLost = function()
				updateSection(sectionName, "prefix", prefixSettingBox.Text)
			end,
		})

		if sectionName == "services" then
			servicePrefixBox = prefixSettingBox
		elseif sectionName == "modules" then
			modulePrefixBox = prefixSettingBox
		elseif sectionName == "instances" then
			instancePrefixBox = prefixSettingBox
		else
			definitionPrefixBox = prefixSettingBox
		end

		bindAutomaticSectionHeight(section)
		return section
	end

	const function updatePageTabs()
		for pageName, button in pageButtons do
			const selected = pageName == activePage
			button.BackgroundColor3 = if selected then Theme.SECTION else Theme.DARK
			button.TextColor3 = if selected then Theme.TEXT else Theme.MUTED
		end
	end

	const function renderSettings()
		clearContent()
		titleLabel.Text = "  CodeKit"
		scopeTabs.Visible = true
		footerFrame.Visible = true
		contentFrame.Position = UDim2.fromOffset(0, 121)
		contentFrame.Size = UDim2.new(1, 0, 1, -165)

		new("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
			Parent = contentFrame,
		})
		new("UIPadding")({
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			Parent = contentFrame,
		})

		const miscellaneous = Section(contentFrame, "Miscellaneous", 0)
		addToggle(miscellaneous, "Enabled", 1, "enabled")
		addToggle(miscellaneous, "Modules", 2, "autoModules")
		addToggle(miscellaneous, "Services", 3, "autoServices")
		addToggle(miscellaneous, "Instances", 4, "autoInstances")
		addToggle(miscellaneous, "Remotes", 5, "autoRemotes")
		addToggle(miscellaneous, "Folders", 6, "autoFolders")
		addToggle(miscellaneous, "Skip Folders", 7, "skipFolders")
		addToggle(miscellaneous, "Quick Access", 8, "enableQuickAccess")
	addToggle(miscellaneous, "Command Bar", 9, "commandBarAutocomplete")
	addToggle(miscellaneous, "Semicolons", 10, "semicolons")
	addToggle(miscellaneous, "Duckable Mode", 11, "duckableMode")
	addDropdown(miscellaneous, "String Quote", 12, "stringQuote", { "double", "single" })
	addDropdown(miscellaneous, "Call Style", 13, "callStyle", { "parentheses", "bare" })
	addDropdown(miscellaneous, "Keyword", 14, "keyword", { "local", "const" })
	addDropdown(miscellaneous, "Require Mode", 15, "requireMode", { "local", "global" })
	addDropdown(miscellaneous, "Sort Order", 16, "importSort", IMPORT_SORT_OPTIONS)
	addDropdown(miscellaneous, "Folder Depth", 17, "importFolderDepth", { "First", "First Two", "All" })
	addDropdown(miscellaneous, "Section Padding", 18, "sectionPadding", { "0", "1", "2", "3", "4" })
		prefixBox = TextBoxSetting({
			parent = miscellaneous.body,
			name = "Prefix",
			index = 19,
			focusLost = function()
				update("prefix", prefixBox.Text)
			end,
		})
		noImportTagBox = TextBoxSetting({
			parent = miscellaneous.body,
			name = "No-import Tag",
			index = 20,
			focusLost = function()
				update("noImportTag", noImportTagBox.Text)
			end,
		})
		customNameAttributeBox = TextBoxSetting({
			parent = miscellaneous.body,
			name = "Custom-Name Attribute",
			index = 21,
			focusLost = function()
				update("customNameAttribute", customNameAttributeBox.Text)
			end,
		})
		bindAutomaticSectionHeight(miscellaneous)

		createSectionSettings(contentFrame, "Services", "services", false)
		createSectionSettings(contentFrame, "Modules", "modules", false)

		const modulesAdvanced = Section(contentFrame, "Module Require", 0)
		addSectionToggle(modulesAdvanced, "Has padding", 1, "modules", "hasPadding")
		addSectionToggle(modulesAdvanced, "Nested", 2, "modules", "nested")
		addSectionToggle(modulesAdvanced, "Show in type checking", 3, "modules", "showInTypeChecking")
		addSectionToggle(modulesAdvanced, "Relative require-by-string", 4, "modules", "relativeRequireByString")
		addSectionToggle(modulesAdvanced, "Absolute require-by-string", 5, "modules", "absoluteRequireByString")
		addSectionDropdown(modulesAdvanced, "Server Scripts Require", 6, "modules", "serverScriptsRequire", MODULE_REQUIRE_OPTIONS)
		addSectionDropdown(modulesAdvanced, "Client Scripts Require", 7, "modules", "clientScriptsRequire", MODULE_REQUIRE_OPTIONS)
		addActionButton(modulesAdvanced.body, "Edit Import Layout", openImportLayoutEditor)
		bindAutomaticSectionHeight(modulesAdvanced)

		createSectionSettings(contentFrame, "Instances", "instances", false)
		createSectionSettings(contentFrame, "Definitions", "definitions", true)

		const indexing = Section(contentFrame, "Indexing", 0)
		addDropdown(indexing, "Client Scripts", 1, "indexing.clientScripts", INDEXING_OPTIONS)
		addDropdown(indexing, "Server Scripts", 2, "indexing.serverScripts", INDEXING_OPTIONS)
		bindAutomaticSectionHeight(indexing)

		const servicesSection = Section(contentFrame, "Custom Services", 0)
		additionalServicesBox = LargeTextBoxSetting({
			parent = servicesSection.body,
			name = "AdditionalServices",
			label = "Additional Services",
			description = "Comma-separated service names that CodeKit should offer for autocomplete.",
			placeholderText = "ExampleService, SecondExampleService",
			focusLost = function()
				update("additionalServices", parseList(additionalServicesBox.Text))
			end,
		})
		customServiceAliasesBox = LargeTextBoxSetting({
			parent = servicesSection.body,
			name = "ServiceAliases",
			label = "Service Aliases",
			description = "Rename services in generated code, for example Workspace=World.",
			placeholderText = "Workspace=World, ReplicatedStorage=Shared",
			focusLost = function()
				update("customServiceAliases", parseList(customServiceAliasesBox.Text))
			end,
		})
		bindAutomaticSectionHeight(servicesSection)

		const contextSection = Section(contentFrame, "Context", 0)
		clientDirectoriesBox = LargeTextBoxSetting({
			parent = contextSection.body,
			name = "ClientDirectories",
			label = "Client Directories",
			description = "Directories treated as client-only when CodeKit checks import context.",
			placeholderText = "ReplicatedStorage.Services, ReplicatedStorage.Modules.Client",
			focusLost = function()
				update("clientDirectories", parseList(clientDirectoriesBox.Text))
			end,
		})
		namesBox = LargeTextBoxSetting({
			parent = contextSection.body,
			name = "IgnoredNames",
			label = "Ignored Names",
			description = "Folder and instance names ignored while discovering import candidates.",
			placeholderText = "_Index, node_modules, include",
			focusLost = function()
				update("ignoredNames", parseList(namesBox.Text))
			end,
		})
		bindAutomaticSectionHeight(contextSection)

	end

	const function renderPanelPage(pageName: string)
		clearContent()
		titleLabel.Text = "  CodeKit"
		scopeTabs.Visible = false
		footerFrame.Visible = false
		contentFrame.Position = UDim2.fromOffset(0, 83)
		contentFrame.Size = UDim2.new(1, 0, 1, -83)

		if pageName == "snippets" then
			activePanel = SnippetsWindow.createPanel(contentFrame, resources.snippetsStore)
		elseif pageName == "themes" then
			activePanel = ThemesWindow.createPanel(contentFrame, plugin)
		elseif pageName == "todos" then
			activePanel = TodoWindow.createPanel(contentFrame)
			activePanel.refresh()
		elseif pageName == "refactor" then
			activePanel = RefactorWindow.createPanel(contentFrame, resources.refactorQueue)
			activePanel.refresh()
		end
	end

	const function showPage(pageName: string)
		if pageName == "autocomplete" then
			pageName = "settings"
		end
		if activePanel ~= nil then
			activePanel.destroy()
			activePanel = nil
		end
		if destroyPageRoot ~= nil then
			destroyPageRoot()
			destroyPageRoot = nil
		end

		activePage = pageName
		destroyPageRoot = createRoot(function()
			updatePageTabs()
			if pageName == "settings" then
				renderSettings()
			else
				renderPanelPage(pageName)
			end
		end)
		renderTick(renderTick() + 1)
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
				Size = UDim2.new(1, 0, 0, 42),
				Position = UDim2.fromOffset(0, 3),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,

				new("ImageButton")({
					Name = "Back",
					Size = UDim2.fromOffset(30, 30),
					Position = UDim2.fromOffset(6, 6),
					BackgroundTransparency = 1,
					Image = BACK_ICON,
					ImageColor3 = Theme.TEXT,
					Visible = false,
					vide.action(function(instance)
						backButton = instance :: ImageButton
					end),
				}),
				new("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, 0, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = "  CodeKit",
					Font = Enum.Font.SourceSansSemibold,
					TextSize = 20,
					TextColor3 = Theme.TEXT,
					BackgroundTransparency = 1,
					vide.action(function(instance)
						titleLabel = instance :: TextLabel
					end),
				}),
			}),
			new("Frame")({
				Name = "PageTabs",
				Size = UDim2.new(1, 0, 0, 38),
				Position = UDim2.fromOffset(0, 45),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,

				new("UIPadding")({
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),
				new("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				}),
				vide.action(function(tabs)
					for index, page in PAGE_TABS do
						const pageName = page.name
						const button = new("TextButton")({
							Name = `{page.label}Tab`,
							LayoutOrder = index,
							Size = UDim2.new(1 / #PAGE_TABS, -5, 1, 0),
							BackgroundColor3 = Theme.DARK,
							BorderSizePixel = 0,
							Text = `{builderIcon(page.icon)} {page.label}`,
							TextColor3 = Theme.MUTED,
							RichText = true,
							Font = Enum.Font.SourceSansBold,
							TextSize = 14,
							AutoButtonColor = true,
							Activated = function()
								showPage(pageName)
							end,
							Parent = tabs,

							Theme.stroke(Theme.BORDER),
						}) :: TextButton
						pageButtons[pageName] = button
					end
					updatePageTabs()
				end),
			}),
			new("Frame")({
				Name = "ScopeTabs",
				Size = UDim2.new(1, 0, 0, 38),
				Position = UDim2.fromOffset(0, 83),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(instance)
					scopeTabs = instance :: Frame
				end),

				new("UIPadding")({
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
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
					end)
					const workspaceTab = TabButton(tabs, "WORKSPACE", function()
						store.refreshWorkspace()
						activeScope("workspace")
					end)

					effect(function()
						const isGlobal = activeScope() == "global"
						globalTab.active(isGlobal)
						workspaceTab.active(not isGlobal)
					end)
				end),
			}),
			new("ScrollingFrame")({
				Name = "Content",
				Size = UDim2.new(1, 0, 1, -165),
				Position = UDim2.fromOffset(0, 121),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				vide.action(function(instance)
					contentFrame = instance :: Frame
				end),
			}),
			new("Frame")({
				Name = "Footer",
				Size = UDim2.new(1, 0, 0, 44),
				Position = UDim2.new(0, 0, 1, -44),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(instance)
					footerFrame = instance :: Frame
				end),

				new("UIPadding")({
					PaddingTop = UDim.new(0, 6),
					PaddingBottom = UDim.new(0, 6),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
				}),
				new("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 10),
				}),
				vide.action(function(footer)
					FooterButton(footer, "Reset", false, function()
						closeDropdowns()
						resetSettingsVisible(true)
					end)
					FooterButton(footer, "Done", true, function()
						widget.Enabled = false
					end)
				end),
			}),
			new("Frame")({
				Name = "ResetSettingsDimmer",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Active = true,
				Visible = false,
				vide.action(function(dimmer)
					effect(function()
						dimmer.Visible = resetSettingsVisible()
					end)
				end),
			}),
			new("Frame")({
				Name = "ResetSettingsConfirm",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(370, 200),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,
				Visible = false,
				vide.action(function(popup)
					effect(function()
						popup.Visible = resetSettingsVisible()
					end)
				end),

				Theme.stroke(Theme.BORDER),
				new("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, -32, 0, 30),
					Position = UDim2.fromOffset(16, 22),
					BackgroundTransparency = 1,
					Text = "Reset all CodeKit settings?",
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 22,
				}),
				new("TextLabel")({
					Name = "Message",
					Size = UDim2.new(1, -32, 0, 62),
					Position = UDim2.fromOffset(16, 58),
					BackgroundTransparency = 1,
					Text = "Restores global and workspace settings, including import layout. Snippets, themes, and TODOs are not changed.",
					TextWrapped = true,
					TextColor3 = Theme.MUTED,
					Font = Enum.Font.SourceSans,
					TextSize = 16,
				}),
				new("TextButton")({
					Name = "Confirm",
					Size = UDim2.new(0.5, -22, 0, 38),
					Position = UDim2.new(0, 16, 1, -54),
					BackgroundColor3 = Color3.fromRGB(93, 28, 28),
					BorderSizePixel = 0,
					Text = "Reset Settings",
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 16,
					Activated = function()
						store.reset()
						resetSettingsVisible(false)
					end,

					Theme.stroke(Color3.fromRGB(55, 22, 22)),
				}),
				new("TextButton")({
					Name = "Cancel",
					Size = UDim2.new(0.5, -22, 0, 38),
					Position = UDim2.new(0.5, 6, 1, -54),
					BackgroundColor3 = Color3.fromRGB(47, 50, 62),
					BorderSizePixel = 0,
					Text = "Cancel",
					TextColor3 = Theme.TEXT,
					Font = Enum.Font.SourceSansBold,
					TextSize = 16,
					Activated = function()
						resetSettingsVisible(false)
					end,

					Theme.stroke(Theme.BORDER),
				}),
			}),
		})

		task.defer(function()
			showPage(activePage)
		end)

		effect(function()
			renderTick()
			const settings = if activeScope() == "global" then store.getGlobal() else store.getWorkspace()
			currentSettings(settings)

			for key, toggle in toggles do
				const dot = string.find(key, ".", 1, true)
				if dot == nil then
					toggle.set(settings[key])
				else
					const sectionName = string.sub(key, 1, dot - 1)
					const settingName = string.sub(key, dot + 1)
					toggle.set(settings[sectionName][settingName])
				end
			end
			for key, dropdown in dropdowns do
				if key == "sectionPadding" then
					dropdown.text(tostring(settings.sectionPadding))
				elseif key == "indexing.clientScripts" then
					dropdown.text(settings.indexing.clientScripts)
				elseif key == "indexing.serverScripts" then
					dropdown.text(settings.indexing.serverScripts)
				else
					dropdown.text(tostring(settings[key]))
				end
			end
			for key, dropdown in sectionDropdowns do
				const dot = string.find(key, ".", 1, true)
				const sectionName = string.sub(key, 1, dot - 1)
				const settingName = string.sub(key, dot + 1)
				dropdown.text(settings[sectionName][settingName])
			end

			if prefixBox ~= nil and not prefixBox:IsFocused() then
				prefixBox.Text = settings.prefix
			end
			if noImportTagBox ~= nil and not noImportTagBox:IsFocused() then
				noImportTagBox.Text = settings.noImportTag
			end
			if customNameAttributeBox ~= nil and not customNameAttributeBox:IsFocused() then
				customNameAttributeBox.Text = settings.customNameAttribute
			end
			if additionalServicesBox ~= nil and not additionalServicesBox:IsFocused() then
				additionalServicesBox.Text = table.concat(settings.additionalServices, ", ")
			end
			if customServiceAliasesBox ~= nil and not customServiceAliasesBox:IsFocused() then
				customServiceAliasesBox.Text = table.concat(settings.customServiceAliases, ", ")
			end
			if clientDirectoriesBox ~= nil and not clientDirectoriesBox:IsFocused() then
				clientDirectoriesBox.Text = table.concat(settings.clientDirectories, ", ")
			end
			if namesBox ~= nil and not namesBox:IsFocused() then
				namesBox.Text = table.concat(settings.ignoredNames, ", ")
			end

			const sectionBoxes = {
				services = { prefix = servicePrefixBox },
				modules = { prefix = modulePrefixBox },
				instances = { prefix = instancePrefixBox },
				definitions = { prefix = definitionPrefixBox },
			}
			for sectionName, boxes in sectionBoxes do
				if boxes.prefix ~= nil and not boxes.prefix:IsFocused() then
					boxes.prefix.Text = settings[sectionName].prefix
				end
			end
		end)

		cleanup(store.changed:Connect(function()
			renderTick(renderTick() + 1)
		end))

		return root
	end, widget)

	return {
		widget = widget,
		toggle = function()
			widget.Enabled = not widget.Enabled
			if widget.Enabled then
				showPage(activePage)
			end
		end,
		openPage = function(pageName: string)
			widget.Enabled = true
			showPage(pageName)
		end,
		destroy = function()
			destroyImportLayoutEditor()
			if activePanel ~= nil then
				activePanel.destroy()
				activePanel = nil
			end
			if destroyPageRoot ~= nil then
				destroyPageRoot()
				destroyPageRoot = nil
			end
			destroyUi()
		end,
	}
end

return {
	create = createWindow,
}
