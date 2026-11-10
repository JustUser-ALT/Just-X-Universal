-- UGC Animation Final Test
-- Two independent UGC animation bundles; applies resolved IDs to the current R15 Animate script.
-- Click the active bundle button again to restore the original animation IDs.

local Players = game:GetService("Players")
local AssetService = game:GetService("AssetService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BUNDLES = {
    {
        Name = "Godly Aura",
        Id = 85494457474531,
    },
    {
        Name = "Happy Preppy",
        Id = 177782922191005,
    },
}

local DESCRIPTION_PROPERTIES = {
    IdleAnimation = "IdleAnimation",
    WalkAnimation = "WalkAnimation",
    RunAnimation = "RunAnimation",
    JumpAnimation = "JumpAnimation",
    FallAnimation = "FallAnimation",
    ClimbAnimation = "ClimbAnimation",
    SwimAnimation = "SwimAnimation",
}

local ANIMATE_PATHS = {
    Idle1 = {"idle", "Animation1"},
    Idle2 = {"idle", "Animation2"},
    Walk = {"walk", "WalkAnim"},
    Run = {"run", "RunAnim"},
    Jump = {"jump", "JumpAnim"},
    Fall = {"fall", "FallAnim"},
    Climb = {"climb", "ClimbAnim"},
    Swim = {"swim", "Swim"},
    SwimIdle = {"swimidle", "SwimIdle"},
}

local DESCRIPTION_TO_ANIMATE = {
    IdleAnimation = {"Idle1", "Idle2"},
    WalkAnimation = {"Walk"},
    RunAnimation = {"Run"},
    JumpAnimation = {"Jump"},
    FallAnimation = {"Fall"},
    ClimbAnimation = {"Climb"},
    SwimAnimation = {"Swim", "SwimIdle"},
}

local function getCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local function findPath(root, path)
    local node = root
    for _, name in ipairs(path) do
        node = node and node:FindFirstChild(name)
        if not node then
            return nil
        end
    end
    return node
end

local function normalize(value)
    return string.lower((tostring(value or ""):gsub("[^%w]", "")))
end

local function getItemCategory(item)
    local typeName = normalize(item.AssetType or item.Type or item.ItemType)
    local itemName = normalize(item.Name)

    for category in pairs(DESCRIPTION_PROPERTIES) do
        local normalizedCategory = normalize(category)
        if string.find(typeName, normalizedCategory, 1, true)
            or string.find(itemName, normalizedCategory, 1, true) then
            return category
        end
    end

    return nil
end

local function resolveBundle(bundle)
    local details = AssetService:GetBundleDetailsAsync(bundle.Id)
    if type(details) ~= "table" or type(details.Items) ~= "table" then
        error("Bundle details did not contain an Items list")
    end

    local description = player.Character
        and player.Character:FindFirstChildOfClass("Humanoid")
        and player.Character:FindFirstChildOfClass("Humanoid"):GetAppliedDescription()

    if not description then
        error("Could not get the current HumanoidDescription")
    end

    local found = {}
    for _, item in ipairs(details.Items) do
        local category = getItemCategory(item)
        local assetId = tonumber(item.Id or item.AssetId)
        if category and assetId and not found[category] then
            description[DESCRIPTION_PROPERTIES[category]] = assetId
            found[category] = assetId
        end
    end

    if not found.IdleAnimation and not found.WalkAnimation and not found.RunAnimation then
        error("No locomotion animation items were found in this bundle")
    end

    local model = Players:CreateHumanoidModelFromDescription(
        description,
        Enum.HumanoidRigType.R15
    )

    if not model then
        error("Roblox did not create the temporary R15 model")
    end

    local generatedAnimate = model:FindFirstChild("Animate")
    if not generatedAnimate then
        model:Destroy()
        error("Temporary R15 model has no Animate script")
    end

    local resolved = {}
    for category, targetNames in pairs(DESCRIPTION_TO_ANIMATE) do
        if found[category] then
            for _, targetName in ipairs(targetNames) do
                local path = ANIMATE_PATHS[targetName]
                local animation = path and findPath(generatedAnimate, path)
                if animation and animation:IsA("Animation") then
                    local id = animation.AnimationId
                    if id and id ~= "" then
                        resolved[targetName] = id
                    end
                end
            end
        end
    end

    model:Destroy()

    if not next(resolved) then
        error("Roblox did not generate any resolved animation IDs")
    end

    return resolved, found
end

local function captureOriginals(animate)
    local originals = {}
    for name, path in pairs(ANIMATE_PATHS) do
        local animation = findPath(animate, path)
        if animation and animation:IsA("Animation") then
            originals[name] = animation.AnimationId
        end
    end
    return originals
end

local originalsByCharacter = setmetatable({}, {__mode = "k"})
local activeBundleId = nil
local busy = false

local function getOriginals(character, animate)
    if not originalsByCharacter[character] then
        originalsByCharacter[character] = captureOriginals(animate)
    end
    return originalsByCharacter[character]
end

local function restartAnimate(character, animate)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function()
                track:Stop(0.1)
            end)
        end
    end

    local wasEnabled = animate.Enabled
    animate.Enabled = false
    task.wait(0.15)
    animate.Enabled = wasEnabled
    task.wait(0.25)
end

local function applyMap(character, animate, map)
    local originals = getOriginals(character, animate)
    local changed = 0

    for name, id in pairs(map) do
        local animation = findPath(animate, ANIMATE_PATHS[name])
        if animation and animation:IsA("Animation") then
            animation.AnimationId = id
            changed += 1
        end
    end

    if changed == 0 then
        error("No matching Animation objects were found in the character Animate script")
    end

    restartAnimate(character, animate)
    return changed, originals
end

local function restoreOriginal(character, animate)
    local originals = originalsByCharacter[character]
    if not originals then
        return false
    end

    for name, id in pairs(originals) do
        local animation = findPath(animate, ANIMATE_PATHS[name])
        if animation and animation:IsA("Animation") then
            animation.AnimationId = id
        end
    end

    restartAnimate(character, animate)
    return true
end

local oldGui = playerGui:FindFirstChild("UGCAnimationFinalTest")
if oldGui then
    oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "UGCAnimationFinalTest"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Window"
frame.Size = UDim2.fromOffset(260, 166)
frame.Position = UDim2.new(0.5, -130, 0.72, -83)
frame.BackgroundColor3 = Color3.fromRGB(22, 24, 31)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(65, 72, 88)
stroke.Transparency = 0.2
stroke.Thickness = 1
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 28)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "UGC ANIMATION TEST"
title.TextColor3 = Color3.fromRGB(240, 242, 248)
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 28)
status.Position = UDim2.fromOffset(12, 34)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.Text = "Choose a UGC pack"
status.TextColor3 = Color3.fromRGB(160, 170, 188)
status.TextSize = 11
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame

local function makeButton(text, y, bundle)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -24, 0, 38)
    button.Position = UDim2.fromOffset(12, y)
    button.BackgroundColor3 = Color3.fromRGB(48, 57, 76)
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Font = Enum.Font.GothamSemibold
    button.Text = text
    button.TextColor3 = Color3.fromRGB(245, 247, 252)
    button.TextSize = 12
    button.Parent = frame

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = button

    button.Activated:Connect(function()
        if busy then
            return
        end
        busy = true
        button.Text = "Loading..."
        status.Text = "Resolving UGC animations..."

        local ok, result = pcall(function()
            local character = getCharacter()
            local animate = character:FindFirstChild("Animate")
            if not animate then
                error("Current character has no Animate script")
            end

            if activeBundleId == bundle.Id then
                local restored = restoreOriginal(character, animate)
                activeBundleId = nil
                if restored then
                    return "Original animations restored"
                end
                return "No saved original animations"
            end

            local resolved, found = resolveBundle(bundle)
            local changed = applyMap(character, animate, resolved)
            activeBundleId = bundle.Id

            local states = {}
            for category in pairs(found) do
                table.insert(states, category:gsub("Animation", ""))
            end
            table.sort(states)

            return string.format(
                "%s applied: %d clips (%s)",
                bundle.Name,
                changed,
                table.concat(states, ", ")
            )
        end)

        if ok then
            status.Text = result
        else
            status.Text = "ERROR: " .. tostring(result)
            warn("[UGC Final Test]", result)
        end

        button.Text = text
        busy = false
    end)

    return button
end

makeButton("1  ·  GODLY AURA", 70, BUNDLES[1])
makeButton("2  ·  HAPPY PREPPY", 114, BUNDLES[2])

-- Drag the compact panel on touch or mouse.
local dragging = false
local dragStart
local startPosition

frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = frame.Position
    end
end)

frame.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

game:GetService("UserInputService").InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

print("[UGC Final Test] Ready. Click either pack; click the same pack again to restore original IDs.")
