for _,v in script:GetChildren() do
	if v:IsA("ModuleScript") then
		pcall(require, v)
	end
end

require(script.matchservice).new()