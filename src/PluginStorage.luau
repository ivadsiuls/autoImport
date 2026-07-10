const HttpService = game:GetService("HttpService")

const function load(plugin: Plugin, key: string, fallback: any): any
	const value = plugin:GetSetting(key)
	if value == nil then
		return fallback
	end
	if typeof(value) == "table" then
		return value
	end
	if typeof(value) ~= "string" then
		return fallback
	end

	local decoded
	const success = pcall(function()
		decoded = HttpService:JSONDecode(value)
	end)
	if not success then
		warn(`CodeKit could not decode saved setting {key}; using defaults.`)
		return fallback
	end
	return decoded
end

const function save(plugin: Plugin, key: string, value: any)
	plugin:SetSetting(key, HttpService:JSONEncode(value))
end

return {
	load = load,
	save = save,
}
