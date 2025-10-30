local espPickerFrame = Instance.new("Frame")
espPickerFrame.Size = UDim2.new(0, 260, 0, 140)
espPickerFrame.Position = UDim2.new(0.5, -130, 0.5, -70)
espPickerFrame.BackgroundColor3 = Color3.fromRGB(16,29,31)
espPickerFrame.Visible = false
espPickerFrame.Parent = screenGui
espPickerFrame.Active = true
espPickerFrame.Draggable = true
local espPickerCorner = Instance.new("UICorner", espPickerFrame); espPickerCorner.CornerRadius = UDim.new(0,8)
local espPickerStroke = Instance.new("UIStroke", espPickerFrame); espPickerStroke.Thickness = 1.6; espPickerStroke.Color = Color3.fromRGB(160,0,213)

local rSlider = createSlider(espPickerFrame, 8, "R", 1, 255, espColor.R, function(v) return tostring(math.floor(v)) end)
rSlider.Container.Position = UDim2.new(0, 8, 0, 8)
rSlider.Container.Size = UDim2.new(1, -16, 0, 28)
local gSlider = createSlider(espPickerFrame, 56, "G", 1, 255, espColor.G, function(v) return tostring(math.floor(v)) end)
gSlider.Container.Position = UDim2.new(0, 8, 0, 44)
gSlider.Container.Size = UDim2.new(1, -16, 0, 28)
local bSlider = createSlider(espPickerFrame, 104, "B", 1, 255, espColor.B, function(v) return tostring(math.floor(v)) end)
bSlider.Container.Position = UDim2.new(0, 8, 0, 80)
bSlider.Container.Size = UDim2.new(1, -16, 0, 28)

local colorPreview = Instance.new("TextLabel", espPickerFrame)
colorPreview.Size = UDim2.new(0, 48, 0, 48)
colorPreview.Position = UDim2.new(1, -56, 0, 8)
colorPreview.BackgroundColor3 = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
colorPreview.Text = ""
local cpCorner = Instance.new("UICorner", colorPreview); cpCorner.CornerRadius = UDim.new(0,6)

local function enableESPForPlayer(p)
	if not p or p == LocalPlayer then return end
	local ch = p.Character
	if not ch then return end
	-- destroy old highlight to avoid duplicates
	local existing = ch:FindFirstChild("StrafeESP_Highlight")
	if existing then safeDestroy(existing) end
	local hl = Instance.new("Highlight")
	hl.Name = "StrafeESP_Highlight"
	hl.Adornee = ch
	hl.FillTransparency = 0.4
	hl.OutlineTransparency = 0
	hl.FillColor = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
	hl.Parent = ch
	playerHighlights[p] = hl
end

local function disableESPForPlayer(p)
	local hl = playerHighlights[p]
	if hl then
		safeDestroy(hl)
		playerHighlights[p] = nil
	end
end

local function updateESP(enabledFlag)
	espEnabled = enabledFlag
	if espEnabled then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then enableESPForPlayer(p) end
		end
		espBtn.TextColor3 = Color3.fromRGB(134,34,177)
	else
		for p,_ in pairs(playerHighlights) do disableESPForPlayer(p) end
		espBtn.TextColor3 = Color3.fromRGB(206,30,144)
	end
	saveState()
end

espBtn.MouseButton1Click:Connect(function() updateESP(not espEnabled) end)
espGearBtn.MouseButton1Click:Connect(function()
	espPickerFrame.Visible = not espPickerFrame.Visible
	if espPickerFrame.Visible then
		rSlider.SetValue(espColor.R)
		gSlider.SetValue(espColor.G)
		bSlider.SetValue(espColor.B)
	end
end)

RunService.RenderStepped:Connect(function()
	if espPickerFrame.Visible then
		local r = math.floor(rSlider.GetValue())
		local g = math.floor(gSlider.GetValue())
		local b = math.floor(bSlider.GetValue())
		espColor.R, espColor.G, espColor.B = r, g, b
		colorPreview.BackgroundColor3 = Color3.fromRGB(r,g,b)
		for p, hl in pairs(playerHighlights) do
			if hl and hl.Parent then hl.FillColor = Color3.fromRGB(r,g,b) end
		end
	end
end)

-- keep ESP updated for joins/resets
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(ch)
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end)
for _,p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(ch)
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end
Players.PlayerRemoving:Connect(function(p)
	disableESPForPlayer(p)
	if p == currentTarget then setTarget(nil, true) end
end)


-- (END of extracted ESP block)
