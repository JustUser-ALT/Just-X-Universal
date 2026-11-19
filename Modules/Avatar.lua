-- Just X Universal - Avatar Module
-- Animation Bundles, Emotes, Skin Changer
-- Loaded by JustXUniversal; keep this module self-contained.

return function(Window, JL)
    if not Window or type(JL) ~= "table" then
        error("Avatar module requires Window and JustLib")
    end

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local LocalPlayer = Players.LocalPlayer

    local Avatar = Window:Tab({
        Name = "Avatar",
        Icon = "user-round",
        Type = "Grid"
    })
    
    --==================================================
    -- ANIMATION PACKS
    --==================================================
    
    local AnimationSection = Avatar:Section({Title = "Animation Bundles", Column = 1})
    local EmotesSection = Avatar:Section({Title = "Emotes", Column = 2})
    local SkinSection = Avatar:Section({Title = "Skin Changer", Column = 3})
    local AssetService = game:GetService("AssetService")
    local HttpService = game:GetService("HttpService")
    local animationPacks = {}
    local selectedAnimationPack
    local activeAnimationMap = {}
    local originalAnimationIds = setmetatable({}, {__mode = "k"})
    local managedAnimationIds = {}
    local animationApplyQueued = false
    local animationRestartRequested = false
    local ANIMATION_CONFIG = "JustXUniversal_AnimationPacks.json"
    
    local animationSlots = {
        idle = {"idle"},
        walk = {"walk"},
        run = {"run"},
        jump = {"jump"},
        fall = {"fall"},
        climb = {"climb"},
        swim = {"swim"},
        swimidle = {"swimidle"}
    }
    
    local function loadAnimationPackConfig()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        local okRead, raw = pcall(function()
            if not isfile(ANIMATION_CONFIG) then return nil end
            return readfile(ANIMATION_CONFIG)
        end)
        if not okRead or type(raw) ~= "string" or raw == "" then return end
        local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if okDecode and type(decoded) == "table" then
            for _, pack in ipairs(decoded) do
                if type(pack) == "table" and tonumber(pack.Id) then
                    table.insert(animationPacks, {
                        Id = tostring(pack.Id),
                        Name = tostring(pack.Name or ("Animation Pack " .. pack.Id))
                    })
                end
            end
        end
    end
    
    local function saveAnimationPackConfig()
        if type(writefile) ~= "function" then return false end
        local okSave = pcall(function()
            writefile(ANIMATION_CONFIG, HttpService:JSONEncode(animationPacks))
        end)
        return okSave
    end
    
    local function getAnimationPackNames()
        local names = {}
        for _, pack in ipairs(animationPacks) do
            table.insert(names, pack.Name .. "  [" .. pack.Id .. "]")
        end
        return names
    end
    
    local function findPackByOption(option)
        if type(option) ~= "string" then return nil end
        local id = option:match("%[(%d+)%]$")
            or option:match("[Rr]oblox%.com/bundles/(%d+)")
            or option:match("/bundles/(%d+)")
            or option:match("^(%d+)$")
        for _, pack in ipairs(animationPacks) do
            if pack.Id == id then return pack end
        end
    end
    
    local function syncSelectedAnimationPack()
        if animationPackDropdown and animationPackDropdown.Get then
            local ok, value = pcall(function() return animationPackDropdown:Get() end)
            if ok then
                local found
                if type(value) == "table" then
                    for option, isSelected in pairs(value) do
                        if isSelected then
                            found = findPackByOption(option)
                            if found then break end
                        end
                    end
                else
                    found = findPackByOption(value)
                end
                selectedAnimationPack = found
            end
        end
        return selectedAnimationPack
    end
    
    local function normalizeAnimationToken(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end
    
    local DESCRIPTION_TO_TARGETS = {
        IdleAnimation = {"idle1", "idle2"},
        WalkAnimation = {"walk"},
        RunAnimation = {"run"},
        JumpAnimation = {"jump"},
        FallAnimation = {"fall"},
        ClimbAnimation = {"climb"},
        SwimAnimation = {"swim", "swimidle"}
    }
    
    local resolvedAnimationCache = {}
    
    local function getBundleAnimationCategory(item)
        local candidates = {item.AssetType, item.Type, item.ItemType, item.Name}
        for _, candidate in ipairs(candidates) do
            local token = normalizeAnimationToken(candidate)
            if token:find("swimidle", 1, true) then return "SwimAnimation" end
            if token:find("idleanimation", 1, true) or token == "idle" then return "IdleAnimation" end
            if token:find("walkanimation", 1, true) or token == "walk" then return "WalkAnimation" end
            if token:find("runanimation", 1, true) or token == "run" then return "RunAnimation" end
            if token:find("jumpanimation", 1, true) or token == "jump" then return "JumpAnimation" end
            if token:find("fallanimation", 1, true) or token == "fall" then return "FallAnimation" end
            if token:find("climbanimation", 1, true) or token == "climb" then return "ClimbAnimation" end
            if token:find("swimanimation", 1, true) or token == "swim" then return "SwimAnimation" end
        end
        return nil
    end
    
    local function findGeneratedAnimation(animate, path)
        local current = animate
        for _, name in ipairs(path) do
            current = current and current:FindFirstChild(name)
            if not current then return nil end
        end
        return current
    end
    
    local function resolveAnimationPack(bundleId)
        bundleId = tostring(bundleId)
        if resolvedAnimationCache[bundleId] then
            return resolvedAnimationCache[bundleId]
        end
    
        local details = AssetService:GetBundleDetailsAsync(tonumber(bundleId))
        if type(details) ~= "table" or type(details.Items) ~= "table" then
            error("Roblox returned invalid bundle details")
        end
    
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then error("Current character Humanoid is unavailable") end
    
        local description = humanoid:GetAppliedDescription()
        local found = {}
        for _, item in ipairs(details.Items) do
            local category = getBundleAnimationCategory(item)
            local assetId = tonumber(item.Id or item.AssetId)
            if category and assetId then
                description[category] = assetId
                found[category] = assetId
            end
        end
        if not next(found) then error("No supported animation items were found in this bundle") end
    
        local temporaryModel
        local okResolve, result = pcall(function()
            temporaryModel = Players:CreateHumanoidModelFromDescription(
                description,
                Enum.HumanoidRigType.R15
            )
            if not temporaryModel then error("Roblox could not create the temporary R15 resolver model") end
    
            local generatedAnimate = temporaryModel:FindFirstChild("Animate")
            if not generatedAnimate then error("Temporary R15 model has no Animate script") end
    
            local animations = {}
            local generatedPaths = {
                idle1 = {{"idle", "Animation1"}},
                idle2 = {{"idle", "Animation2"}},
                walk = {{"walk", "WalkAnim"}},
                run = {{"run", "RunAnim"}},
                jump = {{"jump", "JumpAnim"}},
                fall = {{"fall", "FallAnim"}},
                climb = {{"climb", "ClimbAnim"}},
                swim = {{"swim", "Swim"}},
                swimidle = {{"swimidle", "SwimIdle"}}
            }
    
            for category, targets in pairs(DESCRIPTION_TO_TARGETS) do
                if found[category] then
                    for _, target in ipairs(targets) do
                        for _, targetPath in ipairs(generatedPaths[target] or {}) do
                            local animation = findGeneratedAnimation(generatedAnimate, targetPath)
                            if animation and animation:IsA("Animation") then
                                local animationId = animation.AnimationId
                                if type(animationId) == "string" and animationId ~= "" then
                                    animations[target] = animationId:gsub("^rbxassetid://", "")
                                end
                            end
                        end
                    end
                end
            end
    
            if not next(animations) then error("Roblox did not resolve any generated animation IDs") end
            return {
                Id = bundleId,
                Name = tostring(details.Name or ("Animation Pack " .. bundleId)),
                Animations = animations,
                Source = "HumanoidDescription resolver"
            }
        end)
    
        if temporaryModel then
            pcall(function() temporaryModel:Destroy() end)
        end
        if not okResolve then error(result) end
    
        resolvedAnimationCache[bundleId] = result
        return result
    end
    
    local function findAnimationTargetSlot(animationObject)
        local current = animationObject
        local names = {}
        while current and current.Name ~= "Animate" do
            table.insert(names, 1, current.Name:lower())
            current = current.Parent
        end
        local path = table.concat(names, "/")
        if path:find("swimidle", 1, true) then return "swimidle" end
        if path:find("swim", 1, true) then return "swim" end
        if path:find("animation1", 1, true) then return "idle1" end
        if path:find("animation2", 1, true) then return "idle2" end
        if path:find("idle", 1, true) then return "idle" end
        for slot in pairs(animationSlots) do
            if slot ~= "idle" and path:find(slot, 1, true) then return slot end
        end
    end
    
    local function captureOriginalAnimationIds(animate)
        for _, object in ipairs(animate:GetDescendants()) do
            if object:IsA("Animation") and originalAnimationIds[object] == nil then
                originalAnimationIds[object] = object.AnimationId
                if object.AnimationId ~= "" then
                    managedAnimationIds[object.AnimationId] = true
                end
            end
        end
    end
    
    local function restartAnimate(character, animate)
        if not character or not animate or not animate:IsA("LocalScript") then return false end
    
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local trackAnimation
                local okTrack = pcall(function() trackAnimation = track.Animation end)
                local trackId = okTrack and trackAnimation and trackAnimation.AnimationId
                if trackId and managedAnimationIds[trackId] then
                    pcall(function() track:Stop(0) end)
                    pcall(function() track:Destroy() end)
                end
            end
        end
    
        local wasDisabled = animate.Disabled
        animate.Disabled = true
        task.wait(0.1)
        if animate.Parent then animate.Disabled = wasDisabled end
        task.wait(0.2)
        return true
    end
    
    local function applyAnimationMap(restartAfterApply)
        local character = LocalPlayer.Character
        if not character then return false end
        local animate = character:FindFirstChild("Animate")
        if not animate then return false end
    
        captureOriginalAnimationIds(animate)
        local changed = false
        for _, object in ipairs(animate:GetDescendants()) do
            if object:IsA("Animation") then
                local slot = findAnimationTargetSlot(object)
                local assetId = slot and activeAnimationMap[slot]
                if not assetId and (slot == "idle1" or slot == "idle2") then
                    assetId = activeAnimationMap.idle
                end
                local originalId = originalAnimationIds[object]
                local targetId = assetId and ("rbxassetid://" .. tostring(assetId)) or originalId
    
                if assetId then managedAnimationIds[targetId] = true end
                if targetId and object.AnimationId ~= targetId then
                    object.AnimationId = targetId
                    changed = true
                end
            end
        end
    
        if changed and restartAfterApply then
            restartAnimate(character, animate)
        end
        return changed
    end
    
    local function queueAnimationReapply(restartAfterApply)
        animationRestartRequested = animationRestartRequested or restartAfterApply == true
        if animationApplyQueued then return end
        animationApplyQueued = true
    
        task.defer(function()
            local shouldRestart = animationRestartRequested
            animationRestartRequested = false
            animationApplyQueued = false
            applyAnimationMap(shouldRestart)
        end)
    end
    
    local function watchAnimationCharacter(character)
        task.spawn(function()
            local animate = character:WaitForChild("Animate", 10)
            if not animate then return end
            task.wait(0.35)
            if character ~= LocalPlayer.Character or not animate.Parent then return end
            applyAnimationMap(true)
    
            animate.DescendantAdded:Connect(function(object)
                if object:IsA("Animation") then
                    task.defer(function()
                        if character == LocalPlayer.Character then
                            captureOriginalAnimationIds(animate)
                            applyAnimationMap(false)
                        end
                    end)
                end
            end)
        end)
    end
    
    local function applySelectedAnimationPack()
        local pack = syncSelectedAnimationPack()
        if not pack then
            if JL.Notify then JL:Notify({Title = "Animation Bundles", Desc = "Select an Animation Pack first", Type = "Info", Duration = 3}) end
            return
        end
        local okResolve, resolved = pcall(resolveAnimationPack, pack.Id)
        if not okResolve then
            warn("[Just X Universal] Animation pack error:", resolved)
            if JL.Notify then JL:Notify({Title = "Animation Bundles", Desc = tostring(resolved), Type = "Error", Duration = 5}) end
            return
        end
        local character = LocalPlayer.Character
        local animate = character and character:FindFirstChild("Animate")
        if animate then captureOriginalAnimationIds(animate) end
        activeAnimationMap = resolved.Animations
        queueAnimationReapply(true)
        if JL.Notify then
            JL:Notify({Title = "Animation Bundles", Desc = "Applied " .. resolved.Name .. " (" .. resolved.Source .. ")", Type = "Success", Duration = 4}) end
    end
    
    local function resetAnimationPack()
        activeAnimationMap = {}
        local changed = applyAnimationMap(true)
        if JL.Notify then
            JL:Notify({
                Title = "Animation Bundles",
                Desc = changed and "Original character animations restored" or "Original animations are already active",
                Type = "Success",
                Duration = 4
            })
        end
    end
    
    loadAnimationPackConfig()
    
    local animationPackInput = AnimationSection:Input({
        Name = "Animation Pack ID / Link",
        Placeholder = "Paste Bundle ID or Roblox URL",
        Flag = "JXU_AnimationPackInput"
    })
    
    local animationPackNameInput = AnimationSection:Input({
        Name = "Custom Pack Name (Optional)",
        Placeholder = "Leave empty to use Roblox name",
        Flag = "JXU_AnimationPackNameInput"
    })
    
    local animationPackDropdown = AnimationSection:Dropdown({
        Name = "Saved Packs",
        Options = getAnimationPackNames,
        Search = true,
        MultiSelect = false,
        Flag = "JXU_SelectedAnimationPack",
        Callback = function(value)
            if type(value) == "table" then
                selectedAnimationPack = nil
                for option, isSelected in pairs(value) do
                    if isSelected then
                        selectedAnimationPack = findPackByOption(option)
                        if selectedAnimationPack then break end
                    end
                end
            else
                selectedAnimationPack = findPackByOption(value)
            end
        end
    })
    
    AnimationSection:Button({
        Name = "Add Animation Pack",
        Callback = function()
            local rawInput = tostring(animationPackInput:Get() or ""):match("^%s*(.-)%s*$")
            local bundleId
            if rawInput:match("^%d+$") then
                bundleId = rawInput
            else
                bundleId = rawInput:match("[Rr]oblox%.com/bundles/(%d+)")
                    or rawInput:match("/bundles/(%d+)")
            end
            if not bundleId then
                if JL.Notify then JL:Notify({Title = "Animation Bundles", Desc = "Enter a Bundle ID or a valid Roblox bundle link", Type = "Error", Duration = 3}) end
                return
            end
            for _, existing in ipairs(animationPacks) do
                if existing.Id == bundleId then
                    if JL.Notify then JL:Notify({Title = "Animation Bundles", Desc = "This pack is already saved", Type = "Info", Duration = 3}) end
                    return
                end
            end
            local okResolve, resolved = pcall(resolveAnimationPack, bundleId)
            if not okResolve then
                if JL.Notify then JL:Notify({Title = "Animation Bundles", Desc = tostring(resolved), Type = "Error", Duration = 5}) end
                return
            end
            local customName = tostring(animationPackNameInput:Get() or ""):match("^%s*(.-)%s*$")
            local savedName = customName ~= "" and customName or resolved.Name
            table.insert(animationPacks, {Id = resolved.Id, Name = savedName})
            saveAnimationPackConfig()
            if animationPackDropdown and animationPackDropdown.Refresh then
                animationPackDropdown:Refresh()
            end
            if JL.Notify then JL:Notify({Title = "Animation Bundles", Desc = "Saved: " .. resolved.Name, Type = "Success", Duration = 4}) end
        end
    })
    
    AnimationSection:Button({
        Name = "Apply Selected Pack",
        Callback = applySelectedAnimationPack
    })
    
    AnimationSection:Button({
        Name = "Reset Animation",
        Callback = resetAnimationPack
    })
    
    AnimationSection:Button({
        Name = "Remove Selected Pack",
        Callback = function()
            local packToRemove = syncSelectedAnimationPack()
            if not packToRemove then return end
            for index, pack in ipairs(animationPacks) do
                if pack.Id == packToRemove.Id then
                    table.remove(animationPacks, index)
                    break
                end
            end
            selectedAnimationPack = nil
            saveAnimationPackConfig()
            if animationPackDropdown and animationPackDropdown.Refresh then
                animationPackDropdown:Refresh()
            end
        end
    })
    
    LocalPlayer.CharacterAdded:Connect(watchAnimationCharacter)
    if LocalPlayer.Character then watchAnimationCharacter(LocalPlayer.Character) end
    
    --==================================================
    -- SKIN CHANGER
    --==================================================
    
    local TeleportService = game:GetService("TeleportService")
    local SKIN_CONFIG = "JustXUniversal_Skins.json"
    local CATALOG_AVATAR_CREATOR_PLACE_ID = 7041939546
    local skinPacks = {}
    local selectedSkin
    local skinNameInput, skinDropdown
    local originalSkinData
    local activeSkinData
    local skinLoadAnimations = false
    
    local skinDescriptionProperties = {
        "BackAccessory",
        "FaceAccessory",
        "FrontAccessory",
        "HairAccessory",
        "HatAccessory",
        "NeckAccessory",
        "ShoulderAccessory",
        "WaistAccessory",
        "Shirt",
        "Pants",
        "GraphicTShirt",
        "Face",
        "Head",
        "LeftArm",
        "LeftLeg",
        "RightArm",
        "RightLeg",
        "Torso",
        "BodyTypeScale",
        "DepthScale",
        "HeadScale",
        "HeightScale",
        "ProportionScale",
        "WidthScale",
        "HeadColor",
        "LeftArmColor",
        "LeftLegColor",
        "RightArmColor",
        "RightLegColor",
        "TorsoColor",
        "ClimbAnimation",
        "FallAnimation",
        "IdleAnimation",
        "JumpAnimation",
        "MoodAnimation",
        "RunAnimation",
        "SwimAnimation",
        "WalkAnimation"
    }
    
    local function descriptionToSkinData(description)
        if not description or not description:IsA("HumanoidDescription") then
            error("HumanoidDescription is unavailable")
        end
    
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local data = {
            RigType = humanoid and humanoid.RigType.Name or "R15",
            Properties = {},
            Accessories = {},
            AccessoryRefinements = {},
            Emotes = {},
            EquippedEmotes = {}
        }
    
        for _, property in ipairs(skinDescriptionProperties) do
            local okProperty, value = pcall(function()
                return description[property]
            end)
            if okProperty then
                if typeof(value) == "Color3" then
                    data.Properties[property] = {
                        __type = "Color3",
                        R = value.R,
                        G = value.G,
                        B = value.B
                    }
                elseif type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
                    data.Properties[property] = value
                end
            end
        end
    
        local okAccessories, accessories = pcall(function()
            return description:GetAccessories(true)
        end)
        if okAccessories and type(accessories) == "table" then
            local function mergeAccessoryRefinements(raw)
                local decoded = raw
                if type(raw) == "string" and raw ~= "" then
                    local okDecode, result = pcall(function()
                        return HttpService:JSONDecode(raw)
                    end)
                    decoded = okDecode and result or nil
                end
                if type(decoded) ~= "table" then return end
                for id, refinement in pairs(decoded) do
                    if type(refinement) == "table" then
                        local key = tostring(id)
                        data.AccessoryRefinements[key] = data.AccessoryRefinements[key] or {}
                        for property, value in pairs(refinement) do
                            if property == "Position" or property == "Rotation" or property == "Scale" then
                                data.AccessoryRefinements[key][property] = value
                            end
                        end
                    end
                end
            end
            pcall(function()
                local raw = character and character:GetAttribute("AccessoryRefinements")
                if raw then mergeAccessoryRefinements(raw) end
            end)
            pcall(function()
                local raw = description:GetAttribute("AccessoryRefinements")
                if raw then mergeAccessoryRefinements(raw) end
            end)
            for _, accessory in ipairs(accessories) do
                local accessoryType = tostring(accessory.AccessoryType or "")
                accessoryType = accessoryType:match("%.([^%.]+)$") or accessoryType
                local isLayered = accessory.IsLayered == true
                local entry = {
                    AssetId = tonumber(accessory.AssetId) or 0,
                    AccessoryType = accessoryType,
                    IsLayered = isLayered
                }
                if isLayered then
                    entry.Order = tonumber(accessory.Order) or 0
                    entry.Puffiness = tonumber(accessory.Puffiness) or 1
                end
                local position = accessory.Position
                local rotation = accessory.Rotation
                local scale = accessory.Scale
                if typeof(position) == "Vector3" and position.Magnitude > 0.0001 then
                    entry.Position = {X = position.X, Y = position.Y, Z = position.Z}
                    data.AccessoryRefinements[tostring(entry.AssetId)] = data.AccessoryRefinements[tostring(entry.AssetId)] or {}
                    data.AccessoryRefinements[tostring(entry.AssetId)].Position = entry.Position
                end
                if typeof(rotation) == "Vector3" and rotation.Magnitude > 0.0001 then
                    entry.Rotation = {X = rotation.X, Y = rotation.Y, Z = rotation.Z}
                    data.AccessoryRefinements[tostring(entry.AssetId)] = data.AccessoryRefinements[tostring(entry.AssetId)] or {}
                    data.AccessoryRefinements[tostring(entry.AssetId)].Rotation = entry.Rotation
                end
                if typeof(scale) == "Vector3" and (math.abs(scale.X - 1) > 0.0001 or math.abs(scale.Y - 1) > 0.0001 or math.abs(scale.Z - 1) > 0.0001) then
                    entry.Scale = {X = scale.X, Y = scale.Y, Z = scale.Z}
                    data.AccessoryRefinements[tostring(entry.AssetId)] = data.AccessoryRefinements[tostring(entry.AssetId)] or {}
                    data.AccessoryRefinements[tostring(entry.AssetId)].Scale = entry.Scale
                end
                table.insert(data.Accessories, entry)
            end
        end
    
        local sourceAccessories = {}
        if character then
            for _, instance in ipairs(character:GetChildren()) do
                if instance:IsA("Accessory") then
                    table.insert(sourceAccessories, instance)
                end
            end
        end
    
        local usedSourceAccessories = {}
        local attachmentNamesByType = {
            Face = {"FaceCenterAttachment", "FaceFrontAttachment", "FaceLeftAttachment", "FaceRightAttachment"},
            Front = {"BodyFrontAttachment"},
            Back = {"BodyBackAttachment"},
            Hair = {"HairAttachment"},
            Hat = {"HatAttachment"},
            Neck = {"NeckAttachment"},
            Shoulder = {"LeftShoulderAttachment", "RightShoulderAttachment"},
            Waist = {"WaistCenterAttachment", "WaistFrontAttachment", "WaistBackAttachment", "WaistLeftAttachment", "WaistRightAttachment"}
        }
    
        data.AccessoryRigData = {}
        for index, descriptionAccessory in ipairs(accessories or {}) do
            local accessoryType = tostring(descriptionAccessory.AccessoryType or "")
            accessoryType = accessoryType:match("%.([^%.]+)$") or accessoryType
            local isLayered = descriptionAccessory.IsLayered == true
            local matchedAccessory
    
            if isLayered then
                local wantedOrder = tonumber(descriptionAccessory.Order)
                for _, candidate in ipairs(sourceAccessories) do
                    if not usedSourceAccessories[candidate] then
                        local handle = candidate:FindFirstChild("Handle")
                        local wrap = handle and handle:FindFirstChildOfClass("WrapLayer")
                        if wrap and tonumber(wrap.Order) == wantedOrder then
                            matchedAccessory = candidate
                            break
                        end
                    end
                end
            else
                local allowedNames = attachmentNamesByType[accessoryType] or {}
                for _, candidate in ipairs(sourceAccessories) do
                    if not usedSourceAccessories[candidate] then
                        local handle = candidate:FindFirstChild("Handle")
                        local attachment = handle and handle:FindFirstChildOfClass("Attachment")
                        if attachment then
                            for _, allowedName in ipairs(allowedNames) do
                                if attachment.Name == allowedName then
                                    matchedAccessory = candidate
                                    break
                                end
                            end
                        end
                        if matchedAccessory then break end
                    end
                end
            end
    
            if matchedAccessory then
                usedSourceAccessories[matchedAccessory] = true
                local handle = matchedAccessory:FindFirstChild("Handle")
                local attachment = handle and handle:FindFirstChildOfClass("Attachment")
                local constraint = handle and handle:FindFirstChild("AccessoryRigidConstraint")
                if constraint and constraint:IsA("RigidConstraint") and constraint.Attachment0 then
                    attachment = constraint.Attachment0
                end
                local rigEntry = {
                    Index = index,
                    AccessoryType = accessoryType,
                    IsLayered = isLayered,
                    AttachmentName = attachment and attachment.Name or nil
                }
    
                if isLayered then
                    rigEntry.Order = tonumber(descriptionAccessory.Order)
                end
    
                if attachment then
                    local cf = attachment.CFrame
                    rigEntry.AttachmentCFrame = {cf:GetComponents()}
                end
    
                if constraint and constraint:IsA("RigidConstraint") then
                    local attachment0 = constraint.Attachment0
                    local attachment1 = constraint.Attachment1
                    if attachment0 and attachment1 then
                        rigEntry.HasRigidConstraint = true
                        rigEntry.BodyPartName = attachment1.Parent and attachment1.Parent.Name or nil
                        rigEntry.BodyAttachmentName = attachment1.Name
                    end
                end
    
                table.insert(data.AccessoryRigData, rigEntry)
            end
        end
    
        pcall(function()
            data.Emotes = description:GetEmotes()
        end)
        pcall(function()
            data.EquippedEmotes = description:GetEquippedEmotes()
        end)
    
        return data
    end
    
    local function skinDataToDescription(data)
        if type(data) ~= "table" or type(data.Properties) ~= "table" then
            error("Saved skin data is invalid")
        end
    
        local description = Instance.new("HumanoidDescription")
        local accessoryPropertyNames = {
            BackAccessory = true,
            FaceAccessory = true,
            FrontAccessory = true,
            HairAccessory = true,
            HatAccessory = true,
            NeckAccessory = true,
            ShoulderAccessory = true,
            ShouldersAccessory = true,
            WaistAccessory = true
        }
    
        for property, value in pairs(data.Properties) do
            if type(property) == "string" and not accessoryPropertyNames[property] then
                local okSet, setError = pcall(function()
                    if type(value) == "table" and value.__type == "Color3" then
                        description[property] = Color3.new(
                            tonumber(value.R) or 0,
                            tonumber(value.G) or 0,
                            tonumber(value.B) or 0
                        )
                    else
                        description[property] = value
                    end
                end)
                if not okSet then
                    pcall(function() description:Destroy() end)
                    error("Could not restore HumanoidDescription property " .. property .. ": " .. tostring(setError))
                end
            end
        end
    
        local accessories = {}
        local savedAccessories = type(data.Accessories) == "table" and data.Accessories or {}
        for _, accessory in ipairs(savedAccessories) do
            if type(accessory) == "table" then
                local accessoryType
                pcall(function()
                    accessoryType = Enum.AccessoryType[accessory.AccessoryType]
                end)
                local assetId = tonumber(accessory.AssetId)
                if accessoryType and assetId and assetId > 0 then
                    local entry = {
                        AssetId = assetId,
                        AccessoryType = accessoryType
                    }
                    local refinements = type(data.AccessoryRefinements) == "table"
                        and data.AccessoryRefinements[tostring(assetId)] or nil
                    refinements = type(refinements) == "table" and refinements or accessory
                    for _, property in ipairs({"Position", "Rotation", "Scale"}) do
                        local value = refinements[property]
                        if type(value) == "table" then
                            entry[property] = Vector3.new(
                                tonumber(value.X or value.x) or (property == "Scale" and 1 or 0),
                                tonumber(value.Y or value.y) or (property == "Scale" and 1 or 0),
                                tonumber(value.Z or value.z) or (property == "Scale" and 1 or 0)
                            )
                        end
                    end
                    if accessory.IsLayered == true then
                        entry.IsLayered = true
                        entry.Order = tonumber(accessory.Order) or 0
                        entry.Puffiness = tonumber(accessory.Puffiness) or 1
                    end
                    table.insert(accessories, entry)
                end
            end
        end
    
        if #accessories > 0 then
            local okAccessories, accessoryError = pcall(function()
                description:SetAccessories(accessories, true)
            end)
            if not okAccessories then
                pcall(function() description:Destroy() end)
                error("HumanoidDescription:SetAccessories failed: " .. tostring(accessoryError))
            end
        else
            for property in pairs(accessoryPropertyNames) do
                local value = data.Properties[property]
                if value ~= nil then
                    pcall(function() description[property] = tostring(value) end)
                end
            end
        end
        pcall(function()
            description:SetEmotes(type(data.Emotes) == "table" and data.Emotes or {})
        end)
        pcall(function()
            description:SetEquippedEmotes(type(data.EquippedEmotes) == "table" and data.EquippedEmotes or {})
        end)
    
        return description
    end
    
    local function loadSkinConfig()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        local okRead, raw = pcall(function()
            if not isfile(SKIN_CONFIG) then return nil end
            return readfile(SKIN_CONFIG)
        end)
        if not okRead or type(raw) ~= "string" or raw == "" then return end
    
        local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if not okDecode or type(decoded) ~= "table" then return end
    
        for _, skin in ipairs(decoded) do
            if type(skin) == "table" and type(skin.Data) == "table" and type(skin.Data.Properties) == "table" then
                table.insert(skinPacks, {
                    Key = tostring(skin.Key or (#skinPacks + 1)),
                    Name = tostring(skin.Name or ("Skin" .. (#skinPacks + 1))),
                    Data = skin.Data
                })
            end
        end
    end
    
    local function saveSkinConfig()
        if type(writefile) ~= "function" then return false end
        local okSave = pcall(function()
            writefile(SKIN_CONFIG, HttpService:JSONEncode(skinPacks))
        end)
        return okSave
    end
    
    local function getSkinNames()
        local names = {}
        for _, skin in ipairs(skinPacks) do
            table.insert(names, skin.Name .. "  [" .. skin.Key .. "]")
        end
        return names
    end
    
    local function findSkinByOption(option)
        if type(option) ~= "string" then return nil end
        local key = option:match("%[([^%]]+)%]$")
        for _, skin in ipairs(skinPacks) do
            if skin.Key == key then return skin end
        end
    end
    
    local function syncSelectedSkin()
        if skinDropdown and skinDropdown.Get then
            local ok, value = pcall(function()
                return skinDropdown:Get()
            end)
            if ok then
                local found
                if type(value) == "table" then
                    for option, isSelected in pairs(value) do
                        if isSelected then
                            found = findSkinByOption(option)
                            if found then break end
                        end
                    end
                else
                    found = findSkinByOption(value)
                end
                selectedSkin = found
            end
        end
        return selectedSkin
    end
    
    local function getNextSkinName()
        local highest = 0
        for _, skin in ipairs(skinPacks) do
            local number = tonumber(skin.Name:match("^Skin(%d+)$"))
            if number and number > highest then highest = number end
        end
        return "Skin" .. tostring(highest + 1)
    end
    
    local function getCurrentHumanoidDescription()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then error("Current character Humanoid is unavailable") end
        return humanoid:GetAppliedDescription()
    end
    
    local function saveCurrentSkin()
        local skinData
        if activeSkinData then
            local okCopy, copiedData = pcall(function()
                return HttpService:JSONDecode(HttpService:JSONEncode(activeSkinData))
            end)
            if not okCopy then
                if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = tostring(copiedData), Type = "Error", Duration = 5}) end
                return
            end
            skinData = copiedData
        else
            local okDescription, description = pcall(getCurrentHumanoidDescription)
            if not okDescription then
                if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = tostring(description), Type = "Error", Duration = 5}) end
                return
            end
    
            local okData, data = pcall(descriptionToSkinData, description)
            pcall(function() description:Destroy() end)
            if not okData then
                if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = tostring(data), Type = "Error", Duration = 5}) end
                return
            end
            skinData = data
        end
    
        local customName = tostring(skinNameInput:Get() or ""):match("^%s*(.-)%s*$")
        local savedName = customName ~= "" and customName or getNextSkinName()
        local key = HttpService:GenerateGUID(false)
    
        table.insert(skinPacks, {
            Key = key,
            Name = savedName,
            Data = skinData
        })
    
        if not saveSkinConfig() then
            table.remove(skinPacks, #skinPacks)
            if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Could not save the skin file. Check executor file access.", Type = "Error", Duration = 5}) end
            return
        end
    
        local refreshOk, refreshError = true, nil
        if skinDropdown and skinDropdown.Refresh then
            refreshOk, refreshError = pcall(function()
                skinDropdown:Refresh()
            end)
        end
        if JL.Notify then
            JL:Notify({Title = "Skin Changer", Desc = "Saved: " .. savedName, Type = "Success", Duration = 4})
            if not refreshOk then
                JL:Notify({Title = "Skin Changer", Desc = "Skin was saved, but the dropdown could not refresh: " .. tostring(refreshError), Type = "Warn", Duration = 6})
            end
        end
    end
    
    local function createSkinHumanoidModel(description, rigType)
        local verification
        pcall(function()
            verification = Enum.AssetTypeVerification.ClientOnly
        end)
    
        local okCreate, modelOrError = pcall(function()
            if verification then
                return Players:CreateHumanoidModelFromDescriptionAsync(description, rigType, verification)
            end
            return Players:CreateHumanoidModelFromDescriptionAsync(description, rigType)
        end)
        if okCreate and modelOrError then return modelOrError end
    
        local fallbackOk, fallbackModel = pcall(function()
            return Players:CreateHumanoidModelFromDescription(description, rigType)
        end)
        if fallbackOk and fallbackModel then return fallbackModel end
    
        error(tostring(modelOrError) .. " | Fallback: " .. tostring(fallbackModel))
    end
    
    local function resolveSkinAnimationMap(description)
        local temporaryModel
        local okResolve, result = pcall(function()
            temporaryModel = createSkinHumanoidModel(description, Enum.HumanoidRigType.R15)
            if not temporaryModel then error("Roblox could not create the temporary R15 skin resolver model") end
    
            local generatedAnimate = temporaryModel:FindFirstChild("Animate")
            if not generatedAnimate then error("Temporary R15 skin model has no Animate script") end
    
            local paths = {
                idle1 = {"idle", "Animation1"},
                idle2 = {"idle", "Animation2"},
                walk = {"walk", "WalkAnim"},
                run = {"run", "RunAnim"},
                jump = {"jump", "JumpAnim"},
                fall = {"fall", "FallAnim"},
                climb = {"climb", "ClimbAnim"},
                swim = {"swim", "Swim"},
                swimidle = {"swimidle", "SwimIdle"}
            }
            local animations = {}
            for target, path in pairs(paths) do
                local animation = findGeneratedAnimation(generatedAnimate, path)
                if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
                    animations[target] = animation.AnimationId:gsub("^rbxassetid://", "")
                end
            end
            if not next(animations) then error("No animation IDs could be resolved from this skin") end
            return animations
        end)
    
        if temporaryModel then
            pcall(function() temporaryModel:Destroy() end)
        end
        if not okResolve then error(result) end
        return result
    end
    
    local function applySkinAccessoryRefinements(model, data)
        local refinements = type(data.AccessoryRefinements) == "table" and data.AccessoryRefinements or {}
        local rigData = type(data.AccessoryRigData) == "table" and data.AccessoryRigData or {}
        local matched = 0
        local used = {}
    
        local function decodeCFrame(components)
            if type(components) ~= "table" or #components ~= 12 then return nil end
            local values = {}
            for index = 1, 12 do
                values[index] = tonumber(components[index])
                if values[index] == nil then return nil end
            end
            return CFrame.new(table.unpack(values))
        end
    
        local function findBodyAttachment(name, preferredPart)
            local preferred = preferredPart and model:FindFirstChild(preferredPart, true)
            if preferred then
                local attachment = preferred:FindFirstChild(name)
                if attachment and attachment:IsA("Attachment") then return attachment end
            end
            for _, instance in ipairs(model:GetDescendants()) do
                if instance:IsA("Attachment") and instance.Name == name then
                    return instance
                end
            end
        end
    
        for _, entry in ipairs(rigData) do
            if type(entry) == "table" then
                local targetAccessory
                if entry.IsLayered == true and tonumber(entry.Order) then
                    for _, candidate in ipairs(model:GetDescendants()) do
                        if candidate:IsA("Accessory") and not used[candidate] then
                            local handle = candidate:FindFirstChild("Handle")
                            local wrap = handle and handle:FindFirstChildOfClass("WrapLayer")
                            if wrap and tonumber(wrap.Order) == tonumber(entry.Order) then
                                targetAccessory = candidate
                                break
                            end
                        end
                    end
                else
                    for _, candidate in ipairs(model:GetDescendants()) do
                        if candidate:IsA("Accessory") and not used[candidate] then
                            local handle = candidate:FindFirstChild("Handle")
                            local attachment = handle and entry.AttachmentName and handle:FindFirstChild(entry.AttachmentName)
                            if attachment and attachment:IsA("Attachment") then
                                targetAccessory = candidate
                                break
                            end
                        end
                    end
                end
    
                if targetAccessory then
                    used[targetAccessory] = true
                    local handle = targetAccessory:FindFirstChild("Handle")
                    local attachment = handle and entry.AttachmentName and handle:FindFirstChild(entry.AttachmentName)
                    local savedCFrame = decodeCFrame(entry.AttachmentCFrame)
                    if attachment and savedCFrame then
                        attachment.CFrame = savedCFrame
                        matched = matched + 1
                    end
    
                    if entry.HasRigidConstraint == true and handle and attachment then
                        local existing = handle:FindFirstChild("AccessoryRigidConstraint")
                        if not (existing and existing:IsA("RigidConstraint")) then
                            local bodyAttachment = entry.BodyAttachmentName
                                and findBodyAttachment(entry.BodyAttachmentName, entry.BodyPartName)
                            if bodyAttachment then
                                local constraint = Instance.new("RigidConstraint")
                                constraint.Name = "AccessoryRigidConstraint"
                                constraint.Attachment0 = attachment
                                constraint.Attachment1 = bodyAttachment
                                constraint.Parent = handle
                            end
                        end
                    end
                end
            end
        end
    
        if next(refinements) then
            for _, accessory in ipairs(model:GetDescendants()) do
                if accessory:IsA("Accessory") then
                    local handle = accessory:FindFirstChild("Handle")
                    if handle then
                        local assetId
                        pcall(function() assetId = tonumber(accessory:GetAttribute("AssetId")) end)
                        if not assetId then pcall(function() assetId = tonumber(handle:GetAttribute("AssetId")) end) end
                        if not assetId then
                            local mesh = handle:FindFirstChildOfClass("SpecialMesh")
                            if mesh and mesh.MeshId then assetId = tonumber(tostring(mesh.MeshId):match("%d+")) end
                        end
                        if not assetId and handle:IsA("MeshPart") and handle.MeshId then
                            assetId = tonumber(tostring(handle.MeshId):match("%d+"))
                        end
                        local key = assetId and tostring(assetId) or accessory.Name
                        local refinement = refinements[key]
                        if type(refinement) == "table" then
                            local function readVector(value, fallback)
                                if type(value) ~= "table" then return fallback end
                                return Vector3.new(
                                    tonumber(value.X or value.x) or fallback.X,
                                    tonumber(value.Y or value.y) or fallback.Y,
                                    tonumber(value.Z or value.z) or fallback.Z
                                )
                            end
                            local position = readVector(refinement.Position, Vector3.zero)
                            local rotation = readVector(refinement.Rotation, Vector3.zero)
                            local scale = readVector(refinement.Scale, Vector3.one)
                            local offset = CFrame.new(position) * CFrame.Angles(
                                math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
                            )
                            local attachment = handle:FindFirstChildOfClass("Attachment")
                            if attachment then
                                attachment.CFrame = attachment.CFrame * offset
                            else
                                local weld = handle:FindFirstChildOfClass("Weld")
                                    or handle:FindFirstChildOfClass("ManualWeld")
                                if weld and weld:IsA("Weld") then
                                    weld.C0 = weld.C0 * offset
                                end
                            end
                            if scale ~= Vector3.one then
                                handle.Size = handle.Size * scale
                                local mesh = handle:FindFirstChildOfClass("SpecialMesh")
                                if mesh then mesh.Scale = mesh.Scale * scale end
                            end
                        end
                    end
                end
            end
        end
    
        return matched
    end
    local function getSkinFeetBottomY(model)
        if not model then return nil end
        local footNames = {"LeftFoot", "RightFoot", "Left Leg", "Right Leg"}
        local lowestY = math.huge
        local foundFoot = false
        local seen = {}
    
        for _, footName in ipairs(footNames) do
            local foot = model:FindFirstChild(footName, true)
            if foot and foot:IsA("BasePart") and not seen[foot] then
                seen[foot] = true
                foundFoot = true
                local halfSize = foot.Size / 2
                for _, x in ipairs({-halfSize.X, halfSize.X}) do
                    for _, y in ipairs({-halfSize.Y, halfSize.Y}) do
                        for _, z in ipairs({-halfSize.Z, halfSize.Z}) do
                            local worldPosition = foot.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
                            lowestY = math.min(lowestY, worldPosition.Y)
                        end
                    end
                end
            end
        end
    
        return foundFoot and lowestY or nil
    end
    
    local skinPreviewModel
    local skinPreviewCharacter
    local skinPreviewRoot
    local skinPreviewOffset = Vector3.zero
    local skinPreviewConnections = {}
    local hiddenSkinParts = {}
    local hiddenSkinDecals = {}
    local skinPreviewDecalTransparency = {}
    local skinPreviewCollisionParts = {}
    local skinPreviewBuilding = false
    local skinPreviewBuildToken = 0
    local skinAnimationSync
    local skinAnimationCleanup
    local skinPreviewHiddenInFirstPerson = false
    local previousSkinAnimationMap
    local stopEntityPreview = function() end
    
    local function disconnectSkinPreviewConnections()
        for name, connection in pairs(skinPreviewConnections) do
            if connection then
                pcall(function() connection:Disconnect() end)
            end
            skinPreviewConnections[name] = nil
        end
    end
    
    local function restoreSkinCharacter()
        for part, oldTransparency in pairs(hiddenSkinParts) do
            pcall(function()
                if part and part.Parent then part.LocalTransparencyModifier = oldTransparency end
            end)
        end
        table.clear(hiddenSkinParts)
    
        for decal, oldTransparency in pairs(hiddenSkinDecals) do
            pcall(function()
                if decal and decal.Parent then decal.Transparency = oldTransparency end
            end)
        end
        table.clear(hiddenSkinDecals)
    end
    
    local function hideSkinCharacterInstance(instance, character)
        if not instance or not character or not instance:IsDescendantOf(character) then return end
        if instance:FindFirstAncestorOfClass("Tool") then return end
    
        if instance:IsA("BasePart") then
            if hiddenSkinParts[instance] == nil then
                hiddenSkinParts[instance] = instance.LocalTransparencyModifier
            end
            instance.LocalTransparencyModifier = 1
        elseif instance:IsA("Decal") or instance:IsA("Texture") then
            if hiddenSkinDecals[instance] == nil then
                hiddenSkinDecals[instance] = instance.Transparency
            end
            instance.Transparency = 1
        end
    end
    
    local function setSkinPreviewVisibility(model, hidden)
        if not model then return end
        for _, instance in ipairs(model:GetDescendants()) do
            if instance:IsA("BasePart") then
                instance.LocalTransparencyModifier = hidden and 1 or 0
            elseif instance:IsA("Decal") or instance:IsA("Texture") then
                local okLocalTransparency = pcall(function()
                    instance.LocalTransparencyModifier = hidden and 1 or 0
                end)
                if not okLocalTransparency then
                    if hidden then
                        if skinPreviewDecalTransparency[instance] == nil then
                            skinPreviewDecalTransparency[instance] = instance.Transparency
                        end
                        instance.Transparency = 1
                    elseif skinPreviewDecalTransparency[instance] ~= nil then
                        instance.Transparency = skinPreviewDecalTransparency[instance]
                        skinPreviewDecalTransparency[instance] = nil
                    end
                end
            end
        end
    end
    
    local function disableSkinPreviewCollision(instance)
        if not instance or not instance:IsA("BasePart") then return end
        skinPreviewCollisionParts[instance] = true
        pcall(function()
            instance.CanCollide = false
            instance.CanTouch = false
            instance.CanQuery = false
            instance.Massless = true
        end)
    end
    
    local function enforceSkinPreviewNoCollision()
        for instance in pairs(skinPreviewCollisionParts) do
            if instance and instance.Parent then
                pcall(function()
                    if instance.CanCollide then instance.CanCollide = false end
                    if instance.CanTouch then instance.CanTouch = false end
                    if instance.CanQuery then instance.CanQuery = false end
                    if not instance.Massless then instance.Massless = true end
                end)
            else
                skinPreviewCollisionParts[instance] = nil
            end
        end
    end
    
    local function isSkinFirstPerson(character)
        local camera = workspace.CurrentCamera
        local head = character and character:FindFirstChild("Head", true)
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not camera or not head or not humanoid then return false end
    
        local cameraDistance = (camera.CFrame.Position - head.Position).Magnitude
        local cameraFollowsCharacter = camera.CameraSubject == humanoid
            or (camera.CameraSubject and camera.CameraSubject:IsDescendantOf(character))
        return cameraFollowsCharacter and cameraDistance <= 1.65
    end
    
    local function bindSkinAnimationSync(character, model)
        local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        local cloneHumanoid = model and model:FindFirstChildOfClass("Humanoid")
        if not playerHumanoid or not cloneHumanoid then return function() end, function() end end
    
        local playerAnimator = playerHumanoid:FindFirstChildOfClass("Animator")
        local cloneAnimator = cloneHumanoid:FindFirstChildOfClass("Animator")
        if not cloneAnimator then
            cloneAnimator = Instance.new("Animator")
            cloneAnimator.Parent = cloneHumanoid
        end
        if not playerAnimator then return function() end, function() end end
    
        local mirroredTracks = {}
    
        local function stopMirroredTrack(sourceTrack)
            local entry = mirroredTracks[sourceTrack]
            if not entry then return end
            pcall(function() entry.Track:Stop(0.08) end)
            pcall(function() entry.Track:Destroy() end)
            pcall(function() entry.Animation:Destroy() end)
            mirroredTracks[sourceTrack] = nil
        end
    
        local function cleanup()
            for sourceTrack in pairs(mirroredTracks) do
                stopMirroredTrack(sourceTrack)
            end
        end
    
        local function sync()
            if not model.Parent or not character.Parent then return end
    
            local activeSources = {}
            for _, sourceTrack in ipairs(playerAnimator:GetPlayingAnimationTracks()) do
                local sourceAnimation = sourceTrack.Animation
                local animationId = sourceAnimation and sourceAnimation.AnimationId
                if sourceTrack.IsPlaying and type(animationId) == "string" and animationId ~= "" then
                    activeSources[sourceTrack] = true
                    local entry = mirroredTracks[sourceTrack]
    
                    if not entry or entry.AnimationId ~= animationId then
                        if entry then stopMirroredTrack(sourceTrack) end
    
                        local animation = Instance.new("Animation")
                        animation.AnimationId = animationId
                        local okLoad, cloneTrack = pcall(function()
                            return cloneAnimator:LoadAnimation(animation)
                        end)
    
                        if okLoad and cloneTrack then
                            entry = {
                                Track = cloneTrack,
                                Animation = animation,
                                AnimationId = animationId
                            }
                            mirroredTracks[sourceTrack] = entry
                            pcall(function() cloneTrack.Priority = sourceTrack.Priority end)
                            pcall(function() cloneTrack.Looped = sourceTrack.Looped end)
                            pcall(function()
                                cloneTrack:Play(0, math.max(sourceTrack.WeightCurrent, 0.001), sourceTrack.Speed)
                            end)
                        else
                            pcall(function() animation:Destroy() end)
                            entry = nil
                        end
                    end
    
                    if entry then
                        local cloneTrack = entry.Track
                        pcall(function() cloneTrack.Priority = sourceTrack.Priority end)
                        pcall(function() cloneTrack.Looped = sourceTrack.Looped end)
                        pcall(function() cloneTrack:AdjustSpeed(sourceTrack.Speed) end)
                        pcall(function() cloneTrack:AdjustWeight(sourceTrack.WeightCurrent, 0) end)
    
                        if sourceTrack.Length > 0 and cloneTrack.Length > 0 then
                            local difference = math.abs(sourceTrack.TimePosition - cloneTrack.TimePosition)
                            if difference > (1 / 60) then
                                pcall(function() cloneTrack.TimePosition = sourceTrack.TimePosition end)
                            end
                        end
                    end
                end
            end
    
            for sourceTrack in pairs(mirroredTracks) do
                if not activeSources[sourceTrack] or not sourceTrack.IsPlaying then
                    stopMirroredTrack(sourceTrack)
                end
            end
        end
    
        return sync, cleanup
    end
    
    local function clearSkinPreview()
        disconnectSkinPreviewConnections()
    
        if skinAnimationCleanup then
            pcall(skinAnimationCleanup)
            skinAnimationCleanup = nil
        end
        skinAnimationSync = nil
    
        if skinPreviewModel then
            pcall(function() skinPreviewModel:Destroy() end)
            skinPreviewModel = nil
        end
    
        skinPreviewCharacter = nil
        skinPreviewRoot = nil
        skinPreviewOffset = Vector3.zero
        skinPreviewHiddenInFirstPerson = false
        table.clear(skinPreviewDecalTransparency)
        table.clear(skinPreviewCollisionParts)
        restoreSkinCharacter()
    end
    
    local function prepareSkinPreviewModel(model)
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            humanoid.RequiresNeck = false
            humanoid.AutomaticScalingEnabled = false
            pcall(function() humanoid.EvaluateStateMachine = false end)
            pcall(function()
                for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
                    if state ~= Enum.HumanoidStateType.None then
                        humanoid:SetStateEnabled(state, false)
                    end
                end
                humanoid:ChangeState(Enum.HumanoidStateType.None)
            end)
        end
    
        local root = model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
        if not root or not root:IsA("BasePart") then
            error("Generated skin model has no HumanoidRootPart")
        end
    
        model.PrimaryPart = root
        for _, instance in ipairs(model:GetDescendants()) do
            if instance:IsA("BasePart") then
                instance.Anchored = instance == root
                disableSkinPreviewCollision(instance)
                instance.LocalTransparencyModifier = 1
            elseif instance:IsA("Decal") or instance:IsA("Texture") then
                pcall(function() instance.LocalTransparencyModifier = 1 end)
            elseif instance:IsA("Script") or instance:IsA("LocalScript") then
                pcall(function() instance.Disabled = true end)
            end
        end
    
        return root
    end
    
    local function buildLocalSkinPreview(data)
        pcall(stopEntityPreview)
        if type(data) ~= "table" or type(data.Properties) ~= "table" then
            error("Saved skin data is invalid")
        end
    
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local characterRoot = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not character or not character.Parent or not humanoid or not characterRoot then
            error("Current character is unavailable")
        end
    
        skinPreviewBuildToken = skinPreviewBuildToken + 1
        local buildToken = skinPreviewBuildToken
        local description = skinDataToDescription(data)
        local rigType = humanoid.RigType
        if data.RigType == "R6" then
            rigType = Enum.HumanoidRigType.R6
        elseif data.RigType == "R15" then
            rigType = Enum.HumanoidRigType.R15
        end
    
        local okCreate, modelOrError = pcall(function()
            return createSkinHumanoidModel(description, rigType)
        end)
        pcall(function() description:Destroy() end)
        if not okCreate or not modelOrError or not modelOrError:IsA("Model") then
            error(tostring(modelOrError))
        end
    
        local model = modelOrError
        local setupOk, setupError = pcall(function()
            model.Name = "JustXSkinPreview"
            applySkinAccessoryRefinements(model, data)
            local root = prepareSkinPreviewModel(model)
            skinPreviewConnections.ModelDescendant = model.DescendantAdded:Connect(disableSkinPreviewCollision)
            skinPreviewConnections.PreSimulation = RunService.PreSimulation:Connect(enforceSkinPreviewNoCollision)
            root.CFrame = characterRoot.CFrame + Vector3.new(0, 100, 0)
            model.Parent = workspace
            enforceSkinPreviewNoCollision()
            RunService.Heartbeat:Wait()
    
            if buildToken ~= skinPreviewBuildToken or LocalPlayer.Character ~= character then
                error("Skin loading was cancelled")
            end
    
            characterRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
            if not characterRoot then error("Current character root disappeared") end
            root.CFrame = characterRoot.CFrame
            RunService.Heartbeat:Wait()
    
            local characterFeetY = getSkinFeetBottomY(character)
            local modelFeetY = getSkinFeetBottomY(model)
            local offsetY = characterFeetY and modelFeetY and (characterFeetY - modelFeetY) or 0
    
            clearSkinPreview()
            if LocalPlayer.Character ~= character or not character.Parent then
                error("Character changed while the skin was loading")
            end
    
            skinPreviewModel = model
            skinPreviewCharacter = character
            skinPreviewRoot = root
            skinPreviewOffset = Vector3.new(0, offsetY, 0)
    
            table.clear(skinPreviewCollisionParts)
            for _, instance in ipairs(model:GetDescendants()) do
                disableSkinPreviewCollision(instance)
            end
            skinPreviewConnections.ModelDescendant = model.DescendantAdded:Connect(disableSkinPreviewCollision)
            skinPreviewConnections.PreSimulation = RunService.PreSimulation:Connect(enforceSkinPreviewNoCollision)
            enforceSkinPreviewNoCollision()
    
            for _, instance in ipairs(character:GetDescendants()) do
                hideSkinCharacterInstance(instance, character)
            end
    
            skinPreviewConnections.Descendant = character.DescendantAdded:Connect(function(instance)
                hideSkinCharacterInstance(instance, character)
            end)
    
            skinAnimationSync, skinAnimationCleanup = bindSkinAnimationSync(character, model)
            skinPreviewHiddenInFirstPerson = isSkinFirstPerson(character)
            setSkinPreviewVisibility(model, skinPreviewHiddenInFirstPerson)
    
            skinPreviewConnections.Render = RunService.RenderStepped:Connect(function()
                if skinPreviewModel ~= model then return end
                if not model.Parent or LocalPlayer.Character ~= character or not character.Parent then
                    clearSkinPreview()
                    return
                end
    
                local currentCharacterRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
                if not currentCharacterRoot or not skinPreviewRoot or not skinPreviewRoot.Parent then
                    clearSkinPreview()
                    return
                end
    
                skinPreviewRoot.CFrame = currentCharacterRoot.CFrame + skinPreviewOffset
                if skinAnimationSync then
                    pcall(skinAnimationSync)
                end
    
                local hiddenInFirstPerson = isSkinFirstPerson(character)
                if hiddenInFirstPerson ~= skinPreviewHiddenInFirstPerson then
                    skinPreviewHiddenInFirstPerson = hiddenInFirstPerson
                    setSkinPreviewVisibility(model, hiddenInFirstPerson)
                end
            end)
        end)
    
        if not setupOk then
            if skinPreviewModel == model then clearSkinPreview() end
            pcall(function() model:Destroy() end)
            error(setupError)
        end
    
        return true
    end
    
    local function applySkinData(data, loadAnimations)
        local nextAnimationMap
        if loadAnimations then
            local okDescription, description = pcall(skinDataToDescription, data)
            if okDescription then
                local okAnimations, result = pcall(resolveSkinAnimationMap, description)
                pcall(function() description:Destroy() end)
                if okAnimations then
                    nextAnimationMap = result
                elseif JL.Notify then
                    JL:Notify({Title = "Skin Changer", Desc = "Skin will load, but its animations could not be resolved: " .. tostring(result), Type = "Warn", Duration = 5})
                end
            end
        end
    
        if skinPreviewBuilding then
            if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "A skin is already loading", Type = "Info", Duration = 3}) end
            return false
        end
    
        skinPreviewBuilding = true
        local okApply, applyResult = pcall(buildLocalSkinPreview, data)
        skinPreviewBuilding = false
        if not okApply or not applyResult then
            if JL.Notify then
                JL:Notify({Title = "Skin Changer", Desc = tostring(okApply and "Could not create the local skin model" or applyResult), Type = "Error", Duration = 6})
            end
            return false
        end
    
        if not activeSkinData and previousSkinAnimationMap == nil then
            previousSkinAnimationMap = table.clone(activeAnimationMap)
        end
        activeSkinData = data
    
        if loadAnimations and nextAnimationMap then
            activeAnimationMap = nextAnimationMap
            queueAnimationReapply(true)
        end
    
        return true
    end
    
    local function loadSelectedSkin()
        local skin = syncSelectedSkin()
        if not skin then
            if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Select a saved skin first", Type = "Info", Duration = 3}) end
            return
        end
    
        if not originalSkinData then
            local okOriginal, description = pcall(getCurrentHumanoidDescription)
            if okOriginal then
                local okData, data = pcall(descriptionToSkinData, description)
                pcall(function() description:Destroy() end)
                if okData then originalSkinData = data end
            end
        end
    
        if applySkinData(skin.Data, skinLoadAnimations) then
            if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Loaded: " .. skin.Name, Type = "Success", Duration = 4}) end
        end
    end
    
    local function deleteSelectedSkin()
        local skin = syncSelectedSkin()
        if not skin then
            if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Select a saved skin first", Type = "Info", Duration = 3}) end
            return
        end
    
        for index, savedSkin in ipairs(skinPacks) do
            if savedSkin.Key == skin.Key then
                table.remove(skinPacks, index)
                break
            end
        end
        selectedSkin = nil
        saveSkinConfig()
        if skinDropdown and skinDropdown.Refresh then
            skinDropdown:Refresh()
        end
        if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Deleted: " .. skin.Name, Type = "Success", Duration = 3}) end
    end
    
    local function resetSkin()
        pcall(stopEntityPreview)
        if not originalSkinData then
            local okOriginal, description = pcall(getCurrentHumanoidDescription)
            if okOriginal then
                local okData, data = pcall(descriptionToSkinData, description)
                pcall(function() description:Destroy() end)
                if okData then originalSkinData = data end
            end
        end
    
        if not originalSkinData then
            if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Original character appearance could not be captured", Type = "Error", Duration = 4}) end
            return
        end
    
        skinPreviewBuildToken = skinPreviewBuildToken + 1
        clearSkinPreview()
        activeSkinData = nil
    
        if previousSkinAnimationMap ~= nil then
            activeAnimationMap = previousSkinAnimationMap
            previousSkinAnimationMap = nil
            queueAnimationReapply(true)
        end
    
        if JL.Notify then JL:Notify({Title = "Skin Changer", Desc = "Original skin restored", Type = "Success", Duration = 4}) end
    end
    
    loadSkinConfig()
    
    local initialDescriptionOk, initialDescription = pcall(getCurrentHumanoidDescription)
    if initialDescriptionOk then
        local initialDataOk, initialData = pcall(descriptionToSkinData, initialDescription)
        pcall(function() initialDescription:Destroy() end)
        if initialDataOk then originalSkinData = initialData end
    end
    
    skinNameInput = SkinSection:Input({
        Name = "Skin Name (Optional)",
        Placeholder = "Leave empty for Skin1",
        Flag = "JXU_SkinNameInput"
    })
    
    SkinSection:Button({
        Name = "Save Current Skin",
        Callback = function()
            if game.PlaceId ~= CATALOG_AVATAR_CREATOR_PLACE_ID then
                local shouldTeleport = JL:Confirm({
                    Title = "Skin Editor Not Detected",
                    Desc = "It looks like you're not in any skin editor place. Would you like to be teleported to the Catalog Avatar Creator to create and save skins? If not, your current skin will be saved to the list.",
                    ConfirmText = "Yes",
                    CancelText = "No"
                })
                if shouldTeleport then
                    pcall(function()
                        TeleportService:Teleport(CATALOG_AVATAR_CREATOR_PLACE_ID, LocalPlayer)
                    end)
                    return
                end
            end
            saveCurrentSkin()
        end
    })
    
    SkinSection:Divider()
    
    skinDropdown = SkinSection:Dropdown({
        Name = "Saved Skins",
        Options = getSkinNames,
        Search = true,
        MultiSelect = false,
        Flag = "JXU_SelectedSkin",
        Settings = {
            {
                Type = "Toggle",
                Name = "Load Animations",
                Default = false,
                Flag = "JXU_SkinLoadAnimations",
                Callback = function(value)
                    skinLoadAnimations = value == true
                end
            }
        },
        Callback = function(value)
            if type(value) == "table" then
                selectedSkin = nil
                for option, isSelected in pairs(value) do
                    if isSelected then
                        selectedSkin = findSkinByOption(option)
                        if selectedSkin then break end
                    end
                end
            else
                selectedSkin = findSkinByOption(value)
            end
        end
    })
    
    SkinSection:Button({
        Name = "Load Skin",
        Callback = loadSelectedSkin
    })
    
    SkinSection:Button({
        Name = "Delete Skin",
        Callback = deleteSelectedSkin
    })
    
    SkinSection:Divider()
    
    SkinSection:Button({
        Name = "Reset Skin",
        Callback = resetSkin
    })

    local function prepareForEntityPreview()
        activeSkinData = nil
        if previousSkinAnimationMap ~= nil then
            activeAnimationMap = previousSkinAnimationMap
            previousSkinAnimationMap = nil
            queueAnimationReapply(true)
        end
    end

    local ENTITY_IMPORT_MODULE_URL = "https://raw.githubusercontent.com/JustUser-ALT/Just-X-Universal/main/Modules/EntityImport.lua?v=9717ae30"
    local entityModuleOk, EntityImportModule = pcall(function()
        local source = game:HttpGet(ENTITY_IMPORT_MODULE_URL)
        local chunk = loadstring(source)
        if type(chunk) ~= "function" then
            error("Entity Import module did not compile")
        end
        return chunk()
    end)

    if entityModuleOk and type(EntityImportModule) == "function" then
        local setupOk, stopFunction = pcall(EntityImportModule, SkinSection, JL, clearSkinPreview, prepareForEntityPreview)
        if setupOk and type(stopFunction) == "function" then
            stopEntityPreview = stopFunction
        elseif not setupOk then
            warn("[Just X Universal] Entity Import setup failed:", stopFunction)
        end
    else
        warn("[Just X Universal] Could not load Entity Import module:", EntityImportModule)
    end
    
    LocalPlayer.CharacterAdded:Connect(function(character)
        clearSkinPreview()
        task.spawn(function()
            local humanoid = character:WaitForChild("Humanoid", 10)
            if not humanoid then return end
            task.wait(0.5)
    
            if not activeSkinData then
                local okDescription, description = pcall(function()
                    return humanoid:GetAppliedDescription()
                end)
                if okDescription then
                    local okData, data = pcall(descriptionToSkinData, description)
                    pcall(function() description:Destroy() end)
                    if okData then originalSkinData = data end
                end
            elseif LocalPlayer.Character == character then
                applySkinData(activeSkinData, skinLoadAnimations)
            end
        end)
    end)

end
