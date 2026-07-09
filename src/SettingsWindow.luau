-- selene: allow(mixed_table)
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

const new = vide.create
const mount = vide.mount
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
	reset: (Types.SettingsScope) -> (),
	refreshWorkspace: () -> (),
	destroy: () -> (),
}

const WIDGET_ID = "codekit-settings"

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

const function createWindow(plugin: Plugin, store: Store)
	const widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		330,
		430,
		300,
		360
	)
	const widget = plugin:CreateDockWidgetPluginGui(WIDGET_ID, widgetInfo)
	widget.Name = "CodeKit Settings"
	widget.Title = "CodeKit Settings"

	local additionalServicesBox: TextBox
	local clientDirectoriesBox: TextBox
	local prefixBox: TextBox
	local namesBox: TextBox
	local enabledToggle
	local autoModulesToggle
	local autoServicesToggle
	local autoRemotesToggle
	local autoFoldersToggle
	local overrideWorkspaceToggle
	local stringRequiresToggle
	local semicolonsToggle
	local modeDropdown
	local keywordDropdown
	local importSortDropdown
	local generalSection
	local requiresSection
	local servicesSection
	local clientDirectoriesSection
	local ignoreSection

	const activeScope = (source("global" :: Types.SettingsScope) :: any) :: (arg: Types.SettingsScope?) -> Types.SettingsScope
	const currentSettings = source(store.getGlobal())
	const renderTick = source(0)
	const destroyUi = mount(function()
		const function bindAutomaticSectionHeight(section)
			const function updateHeight()
				section.setHeight(section.layout.AbsoluteContentSize.Y)
			end

			cleanup(section.layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateHeight))
			updateHeight()
		end

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
			new("ScrollingFrame")({
				Name = "Content",
				Size = UDim2.new(1, 0, 1, -48),
				Position = UDim2.fromOffset(0, 3),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,

				new("UIPadding")({
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
				}),
				new("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 0),
				}),
				new("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, 0, 0, 34),
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = "  CodeKit",
					Font = Enum.Font.SourceSansSemibold,
					TextSize = 20,
					TextColor3 = Theme.TEXT,
					BackgroundColor3 = Theme.DARK,
					BorderSizePixel = 0,
				}),
				new("Frame")({
					Name = "TitleSeparator",
					Size = UDim2.new(1, 0, 0, 2),
					BackgroundColor3 = Theme.BORDER,
					BorderSizePixel = 0,
				}),
				new("Frame")({
					Name = "Tabs",
					Size = UDim2.new(1, 0, 0, 38),
					BackgroundColor3 = Theme.DARK,
					BorderSizePixel = 0,

					new("UIPadding")({
						PaddingLeft = UDim.new(0, 2),
						PaddingRight = UDim.new(0, 2),
						PaddingTop = UDim.new(0, 6),
						PaddingBottom = UDim.new(0, 0),
					}),
					new("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					vide.action(function(tabs)
						const globalTab = TabButton(tabs, "GLOBAL", function()
							modeDropdown.close()
							keywordDropdown.close()
							importSortDropdown.close()
							activeScope("global")
						end)
						const workspaceTab = TabButton(tabs, "WORKSPACE", function()
							modeDropdown.close()
							keywordDropdown.close()
							importSortDropdown.close()
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
				new("Frame")({
					Name = "TabSpacer",
					Size = UDim2.new(1, 0, 0, 8),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				}),
				vide.action(function(content)
					generalSection = Section(content, "General", Theme.ROW_HEIGHT * 6)
					enabledToggle = ToggleSetting(generalSection.body, "Enabled", 1, function()
						const settings = currentSettings()
						store.update(activeScope(), "enabled", not settings.enabled)
					end)
					autoModulesToggle = ToggleSetting(generalSection.body, "Auto Modules", 2, function()
						const settings = currentSettings()
						store.update(activeScope(), "autoModules", not settings.autoModules)
					end)
					autoServicesToggle = ToggleSetting(generalSection.body, "Auto Services", 3, function()
						const settings = currentSettings()
						store.update(activeScope(), "autoServices", not settings.autoServices)
					end)
					autoRemotesToggle = ToggleSetting(generalSection.body, "Auto Remotes", 4, function()
						const settings = currentSettings()
						store.update(activeScope(), "autoRemotes", not settings.autoRemotes)
					end)
					autoFoldersToggle = ToggleSetting(generalSection.body, "Auto Folders", 5, function()
						const settings = currentSettings()
						store.update(activeScope(), "autoFolders", not settings.autoFolders)
					end)

					overrideWorkspaceToggle = ToggleSetting(generalSection.body, "Override Workspace Settings", 6, function()
						if activeScope() ~= "global" then
							return
						end
						const settings = store.getGlobal()
						store.update("global", "overrideWorkspaceSettings", not settings.overrideWorkspaceSettings)
					end)

					requiresSection = Section(content, "Requires", Theme.ROW_HEIGHT * 6)
					stringRequiresToggle = ToggleSetting(requiresSection.body, "String Requires", 1, function()
						const settings = currentSettings()
						store.update(activeScope(), "stringRequires", not settings.stringRequires)
					end)
					semicolonsToggle = ToggleSetting(requiresSection.body, "Semicolons", 2, function()
						const settings = currentSettings()
						store.update(activeScope(), "semicolons", not settings.semicolons)
					end)

					local function updateRequiresHeight()
						local height = Theme.ROW_HEIGHT * 6
						if modeDropdown ~= nil and modeDropdown.isOpen() then
							height += modeDropdown.getOpenHeight()
						end
						if keywordDropdown ~= nil and keywordDropdown.isOpen() then
							height += keywordDropdown.getOpenHeight()
						end
						if importSortDropdown ~= nil and importSortDropdown.isOpen() then
							height += importSortDropdown.getOpenHeight()
						end
						requiresSection.setHeight(height)
					end

					modeDropdown = DropdownSetting(requiresSection.body, "Require Mode", 3, { "local", "global" }, function(value)
						store.update(activeScope(), "requireMode", value)
					end, updateRequiresHeight)
					keywordDropdown = DropdownSetting(requiresSection.body, "Keyword", 4, { "local", "const" }, function(value)
						store.update(activeScope(), "keyword", value)
					end, updateRequiresHeight)
					importSortDropdown = DropdownSetting(
						requiresSection.body,
						"Import Sort",
						5,
						{
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
						},
						function(value)
							store.update(activeScope(), "importSort", value)
						end,
						updateRequiresHeight
					)
					prefixBox = TextBoxSetting({
						parent = requiresSection.body,
						name = "Prefix",
						index = 6,
						focusLost = function()
							store.update(activeScope(), "prefix", prefixBox.Text)
						end,
					})

					servicesSection = Section(content, "Additional Services", 42)
					additionalServicesBox = LargeTextBoxSetting({
						parent = servicesSection.body,
						name = "AdditionalServices",
						placeholderText = "ExampleService, SecondExampleService, ThirdExampleService",
						focusLost = function()
							store.update(activeScope(), "additionalServices", parseList(additionalServicesBox.Text))
						end,
					})
					bindAutomaticSectionHeight(servicesSection)

					clientDirectoriesSection = Section(content, "Client Directories", 42)
					clientDirectoriesBox = LargeTextBoxSetting({
						parent = clientDirectoriesSection.body,
						name = "ClientDirectories",
						placeholderText = "ReplicatedStorage.Services, ReplicatedStorage.Modules.Client",
						focusLost = function()
							store.update(activeScope(), "clientDirectories", parseList(clientDirectoriesBox.Text))
						end,
					})
					bindAutomaticSectionHeight(clientDirectoriesSection)

					ignoreSection = Section(content, "Ignore", 42)
					namesBox = LargeTextBoxSetting({
						parent = ignoreSection.body,
						name = "IgnoredNames",
						placeholderText = "_Index, node_modules",
						focusLost = function()
							store.update(activeScope(), "ignoredNames", parseList(namesBox.Text))
						end,
					})
					bindAutomaticSectionHeight(ignoreSection)

					effect(function()
						const isGlobal = activeScope() == "global"
						overrideWorkspaceToggle.row.Size = UDim2.new(1, 0, 0, if isGlobal then Theme.ROW_HEIGHT else 0)
						generalSection.setHeight(if isGlobal then Theme.ROW_HEIGHT * 6 else Theme.ROW_HEIGHT * 5)
					end)
				end),
			}),
			new("Frame")({
				Name = "Footer",
				Size = UDim2.new(1, 0, 0, 44),
				Position = UDim2.new(0, 0, 1, -44),
				BackgroundColor3 = Theme.DARK,
				BorderSizePixel = 0,

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
						modeDropdown.close()
						keywordDropdown.close()
						importSortDropdown.close()
						store.reset(activeScope())
					end)
					FooterButton(footer, "Done", true, function()
						widget.Enabled = false
					end)
				end),
			}),
		})

		effect(function()
			renderTick()
			const settings = if activeScope() == "global" then store.getGlobal() else store.getWorkspace()
			currentSettings(settings)
			enabledToggle.set(settings.enabled)
			autoModulesToggle.set(settings.autoModules)
			autoServicesToggle.set(settings.autoServices)
			autoRemotesToggle.set(settings.autoRemotes)
			autoFoldersToggle.set(settings.autoFolders)
			overrideWorkspaceToggle.set(settings.overrideWorkspaceSettings)
			stringRequiresToggle.set(settings.stringRequires)
			semicolonsToggle.set(settings.semicolons)
			modeDropdown.text(settings.requireMode)
			keywordDropdown.text(settings.keyword)
			importSortDropdown.text(settings.importSort)
			if not additionalServicesBox:IsFocused() then
				additionalServicesBox.Text = table.concat(settings.additionalServices, ", ")
			end
			if not clientDirectoriesBox:IsFocused() then
				clientDirectoriesBox.Text = table.concat(settings.clientDirectories, ", ")
			end
			if not prefixBox:IsFocused() then
				prefixBox.Text = settings.prefix
			end
			if not namesBox:IsFocused() then
				namesBox.Text = table.concat(settings.ignoredNames, ", ")
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
				activeScope(activeScope())
			end
		end,
		destroy = function()
			destroyUi()
		end,
	}
end

return {
	create = createWindow,
}
