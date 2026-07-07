const moduleServices = require("./moduleServices")
const Types = require("./Types")

const function isIgnoredByName(instance: Instance, ignoredNames: { string }): boolean
	for _, ignoredName in ignoredNames do
		if instance.Name == ignoredName then
			return true
		end
	end

	return false
end

const function isImportable(module: ModuleScript, settings: Types.Settings)
	local parent = module.Parent
	while parent and parent ~= game do
		if isIgnoredByName(parent, settings.ignoredNames) then
			return false
		end
		parent = parent.Parent
	end

	return true
end

type Context = "server" | "shared" | "client"

const serverDirectories = {
	game:GetService("ServerScriptService"),
	game:GetService("ServerStorage"),
}

const clientDirectories = {
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
}

const function getContext(container: LuaSourceContainer): Context
	if container:IsA("LocalScript") then -- do this check first as localscript inherits script
		return "client"
	elseif container:IsA("Script") then
		if container.RunContext == Enum.RunContext.Client then
			return "client"
		end
		return "server"
	end
	for _, dir in serverDirectories do
		if container:IsDescendantOf(dir) then
			return "server"
		end
	end
	for _, dir in clientDirectories do
		if container:IsDescendantOf(dir) then
			return "client"
		end
	end
	return "shared"
end

const function canAccess(origin: LuaSourceContainer, target: ModuleScript)
	if origin == target then
		return false
	end

	const originContext = getContext(origin)
	const targetContext = getContext(target)
	if originContext == "server" then
		return targetContext == "server" or targetContext == "shared"
	elseif originContext == "client" then
		return targetContext == "client" or targetContext == "shared"
	end

	return true
end

local latestModules: { ModuleScript } = {}

const function getModules(origin: LuaSourceContainer, settings: Types.Settings): { ModuleScript }
	local modules = {}
	for _, module in latestModules do
		if canAccess(origin, module) and isImportable(module, settings) then
			table.insert(modules, module)
		end
	end

	return modules
end

for _, service in moduleServices do
	for _, inst in service:GetDescendants() do
		if inst:IsA("ModuleScript") then
			table.insert(latestModules, inst)
		end
	end
	service.DescendantAdded:Connect(function(inst)
		if inst:IsA("ModuleScript") then
			table.insert(latestModules, inst)
		end
	end)
	service.DescendantRemoving:Connect(function(inst)
		const index = table.find(latestModules, inst)
		if index ~= nil then
			table.remove(latestModules, index)
		end
	end)
end

return getModules
