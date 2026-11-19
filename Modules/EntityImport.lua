-- Just X Universal - Entity Import
-- Imports arbitrary in-game Models/BaseParts into the existing Skin Changer section.
-- Local visual replacement only; it does not modify the server character.

return function(SkinSection, JL, clearSkinPreview, onEntityStart)
    if not SkinSection then error("Entity Import requires the existing Skin Changer section") end

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local HttpService = game:GetService("HttpService")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    local CONFIG_FILE = "JustXUniversal_Entities.json"
    local RESOLVE_TIMEOUT = 3
    local SAMPLE_TIME = 2
    local DEFAULTS = {
        ScaleMode = "Fit",
        MovementMode = "Auto",
        RunThreshold = 0.75
    }

    local entries = {}
    local selectedEntry
    local active
    local connections = {}
    local hiddenParts = {}
    local hiddenDecals = {}
    local entityDecalTransparency = setmetatable({}, {__mode = "k"})
    local entityPathInput
    local entityNameInput
    local entityDropdown
    local scaleMode = DEFAULTS.ScaleMode
    local movementMode = DEFAULTS.MovementMode
    local busy = false

    local function notify(title, desc, kind)
        if JL and JL.Notify then
            pcall(function()
                JL:Notify({
                    Title = title or "Entity Import",
                    Desc = tostring(desc or ""),
                    Type = kind or "Info",
                    Duration = 5
                })
            end)
        end
    end

    local function trim(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function ensureFolder()
        if type(makefolder) ~= "function" then return end
        pcall(function()
            if type(isfolder) == "function" then
                if not isfolder("JustXUniversal") then makefolder("JustXUniversal") end
            else
                makefolder("JustXUniversal")
            end
        end)
    end

    local function normalizeAnimationId(value)
        local id = tostring(value or "")
        local digits = id:match("rbxassetid://(%d+)") or id:match("^(%d+)$")
        return digits and ("rbxassetid://" .. digits) or nil
    end

    local function parsePath(path)
        path = trim(path)
        if path == "" then return nil, "Path is empty" end

        path = path:gsub("/", ".")
        path = path:gsub("game:GetService%(%s*['\"]([^'\"]+)['\"]%s*%)", "%1")
        path = path:gsub(":WaitForChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
        path = path:gsub(":FindFirstChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
        path = path:gsub("%[%s*['\"]([^'\"]+)['\"]%s*%]", ".%1")
        path = path:gsub("^%.+", ""):gsub("%.+$", "")

        local tokens = {}
        for token in path:gmatch("[^%.]+") do
            token = trim(token)
            if token ~= "" then tokens[#tokens + 1] = token end
        end
        if #tokens == 0 then return nil, "No path segments found" end
        return tokens
    end

    local function findChild(parent, name)
        local direct = parent:FindFirstChild(name)
        if direct then return direct end

        local base, index = name:match("^(.-)#(%d+)$")
        if base then
            local count = 0
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == base then
                    count += 1
                    if count == tonumber(index) then return child end
                end
            end
        end

        return parent:WaitForChild(name, RESOLVE_TIMEOUT)
    end

    local function resolvePath(path)
        local tokens, parseError = parsePath(path)
        if not tokens then return nil, parseError end

        local current
        local first = tokens[1]
        if first:lower() == "game" then
            current = game
        elseif first:lower() == "workspace" then
            current = Workspace
        else
            local ok, service = pcall(function() return game:GetService(first) end)
            current = ok and service or game:FindFirstChild(first)
            if not current then return nil, "Unknown root: " .. first end
        end

        for index = 2, #tokens do
            local name = tokens[index]
            local nextObject
            if current == game then
                local ok, service = pcall(function() return game:GetService(name) end)
                nextObject = ok and service or game:FindFirstChild(name)
            else
                nextObject = findChild(current, name)
            end
            if not nextObject then
                local parentName = "unknown parent"
                pcall(function() parentName = current:GetFullName() end)
                return nil, "'" .. name .. "' was not found under " .. parentName
                    .. ". Check the path or move closer if StreamingEnabled is active."
            end
            current = nextObject
        end

        return current
    end

    local function pickRoot(model)
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
            return model.PrimaryPart, "PrimaryPart"
        end

        for _, name in ipairs({"HumanoidRootPart", "RootPart", "Root", "Torso", "UpperTorso", "Body", "Main"}) do
            local part = model:FindFirstChild(name, true)
            if part and part:IsA("BasePart") then return part, name end
        end

        local best, bestVolume
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then
                local size = object.Size
                local volume = size.X * size.Y * size.Z
                if not bestVolume or volume > bestVolume then
                    best, bestVolume = object, volume
                end
            end
        end

        return best, best and "Largest BasePart fallback" or "No BaseParts"
    end

    local function getBodyRotation(rootCFrame)
        local look = rootCFrame.LookVector
        local yaw = 0
        if math.abs(look.Y) < 0.98 then yaw = math.atan2(-look.X, -look.Z) end
        return CFrame.Angles(0, -yaw, 0) * rootCFrame.Rotation
    end

    local function computeBounds(model, root, bodyRotation)
        local function newBounds()
            return {
                Min = Vector3.new(math.huge, math.huge, math.huge),
                Max = Vector3.new(-math.huge, -math.huge, -math.huge),
                Count = 0
            }
        end

        local visible = newBounds()
        local complete = newBounds()

        local function addPoint(bounds, point)
            bounds.Min = Vector3.new(
                math.min(bounds.Min.X, point.X),
                math.min(bounds.Min.Y, point.Y),
                math.min(bounds.Min.Z, point.Z)
            )
            bounds.Max = Vector3.new(
                math.max(bounds.Max.X, point.X),
                math.max(bounds.Max.Y, point.Y),
                math.max(bounds.Max.Z, point.Z)
            )
        end

        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                local half = part.Size / 2
                for _, x in ipairs({-1, 1}) do
                    for _, y in ipairs({-1, 1}) do
                        for _, z in ipairs({-1, 1}) do
                            local worldPoint = (part.CFrame * CFrame.new(x * half.X, y * half.Y, z * half.Z)).Position
                            local point = bodyRotation:VectorToWorldSpace(root.CFrame:PointToObjectSpace(worldPoint))
                            addPoint(complete, point)
                            if part.Transparency < 0.98 then
                                addPoint(visible, point)
                            end
                        end
                    end
                end
                complete.Count += 1
                if part.Transparency < 0.98 then visible.Count += 1 end
            end
        end

        local used = visible.Count > 0 and visible or complete
        if used.Count == 0 then return nil end
        return {
            Min = used.Min,
            Max = used.Max,
            Size = used.Max - used.Min,
            Center = (used.Min + used.Max) / 2
        }
    end
    local function classifyAnimation(name, group)
        local n = tostring(name or ""):lower():gsub("[^%w]", "")
        local g = tostring(group or ""):lower():gsub("[^%w]", "")
        local combined = g .. " " .. n

        if combined:find("swimidle", 1, true) then return "swimidle" end
        if combined:find("swim", 1, true) then return "swim" end
        if combined:find("climb", 1, true) or combined:find("ladder", 1, true) then return "climb" end
        if combined:find("sit", 1, true) or combined:find("seat", 1, true) then return "sit" end
        if combined:find("jump", 1, true) or combined:find("leap", 1, true) then return "jump" end
        if combined:find("fall", 1, true) then return "fall" end
        if combined:find("run", 1, true) or combined:find("sprint", 1, true) or combined:find("chase", 1, true) then return "run" end
        if combined:find("walk", 1, true) or combined:find("move", 1, true) or combined:find("crawl", 1, true) then return "walk" end
        if n == "animation2" and g:find("idle", 1, true) then return "idle2" end
        if n == "animation1" and g:find("idle", 1, true) then return "idle1" end
        if combined:find("idle", 1, true) or combined:find("stand", 1, true) or combined:find("breath", 1, true) then return "idle" end
        return nil
    end

    local function addAnimation(list, seen, id, name, group, priority)
        local normalized = normalizeAnimationId(id)
        if not normalized or seen[normalized] then return end
        seen[normalized] = true
        list[#list + 1] = {
            Id = normalized,
            Name = tostring(name or "Animation"),
            Group = tostring(group or ""),
            Priority = priority and tostring(priority):match("([^%.]+)$") or nil
        }
    end

    local function captureEntity(path)
        local source, resolveError = resolvePath(path)
        if not source then return nil, resolveError end
        local sourceIsPart = source:IsA("BasePart")
        local sourceIsContainer = source:IsA("Folder") or source:IsA("Accessory") or source:IsA("Tool")
        if not source:IsA("Model") and not sourceIsPart and not sourceIsContainer then
            return nil, source:GetFullName() .. " is a " .. source.ClassName .. "; expected a Model, Folder, Accessory, Tool, or BasePart"
        end

        local unlocked = {}
        local function unlock(object)
            if not object.Archivable then
                unlocked[#unlocked + 1] = object
                pcall(function() object.Archivable = true end)
            end
        end

        unlock(source)
        for _, object in ipairs(source:GetDescendants()) do unlock(object) end

        local okClone, clone = pcall(function() return source:Clone() end)
        for _, object in ipairs(unlocked) do pcall(function() object.Archivable = false end) end
        if not okClone or not clone then
            return nil, "Clone() failed: " .. tostring(clone)
        end

        if sourceIsPart or sourceIsContainer then
            local wrapper = Instance.new("Model")
            wrapper.Name = clone.Name
            clone.Parent = wrapper
            if sourceIsPart then wrapper.PrimaryPart = clone end
            clone = wrapper
        end

        local info = {
            Template = clone,
            Path = path,
            Name = source.Name,
            Animations = {},
            Warnings = {},
            PartCount = 0,
            AccessoryCount = 0
        }

        local seenAnimations = {}
        for _, object in ipairs(clone:GetDescendants()) do
            if object:IsA("Animation") then
                local parentName = object.Parent and object.Parent.Name or ""
                addAnimation(info.Animations, seenAnimations, object.AnimationId, object.Name, parentName)
            end
        end

        local sourceAnimators = {}
        for _, object in ipairs(source:GetDescendants()) do
            if object:IsA("Animator") then sourceAnimators[#sourceAnimators + 1] = object end
        end

        -- Sample animations already running on the original entity before its scripts are stripped.
        local sampleDeadline = os.clock() + SAMPLE_TIME
        repeat
            for _, animator in ipairs(sourceAnimators) do
                local okTracks, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
                if okTracks and tracks then
                    for _, track in ipairs(tracks) do
                        local animation = track.Animation
                        if animation then
                            addAnimation(
                                info.Animations,
                                seenAnimations,
                                animation.AnimationId,
                                track.Name ~= "" and track.Name or animation.Name,
                                track.Name,
                                track.Priority
                            )
                        end
                    end
                end
            end
            task.wait(0.15)
        until os.clock() >= sampleDeadline or not source.Parent

        local toDestroy = {}
        for _, object in ipairs(clone:GetDescendants()) do
            if object:IsA("Script") or object:IsA("LocalScript") then
                toDestroy[#toDestroy + 1] = object
            elseif object:IsA("JointInstance") or object:IsA("WeldConstraint") then
                local p0, p1 = object.Part0, object.Part1
                if (p0 and not p0:IsDescendantOf(clone)) or (p1 and not p1:IsDescendantOf(clone)) then
                    toDestroy[#toDestroy + 1] = object
                end
            elseif object:IsA("Constraint") then
                local a0, a1 = object.Attachment0, object.Attachment1
                if (a0 and not a0:IsDescendantOf(clone)) or (a1 and not a1:IsDescendantOf(clone)) then
                    toDestroy[#toDestroy + 1] = object
                end
            elseif object:IsA("Sound") then
                pcall(function() object:SetAttribute("JXEntityWasPlaying", object.Playing) object.Playing = false end)
            end
        end
        for _, object in ipairs(toDestroy) do pcall(function() object:Destroy() end) end

        local partCount = 0
        for _, object in ipairs(clone:GetDescendants()) do
            if object:IsA("BasePart") then partCount += 1 end
            if object:IsA("Accessory") then info.AccessoryCount += 1 end
        end
        info.PartCount = partCount

        local root, rootMethod = pickRoot(clone)
        if not root then
            clone:Destroy()
            return nil, "The model contains no BaseParts"
        end

        local bodyRotation = getBodyRotation(root.CFrame)
        local bounds = computeBounds(clone, root, bodyRotation)
        if not bounds then
            clone:Destroy()
            return nil, "Could not measure the entity bounds"
        end

        info.RootName = root.Name
        info.RootMethod = rootMethod
        info.BodyRotation = bodyRotation
        info.Bounds = bounds
        if #unlocked > 0 then
            info.Warnings[#info.Warnings + 1] = tostring(#unlocked) .. " non-Archivable instances were temporarily unlocked"
        end
        if #info.Animations == 0 then
            info.Warnings[#info.Warnings + 1] = "No Animation objects or active animation tracks were found"
        end

        return info
    end

    local function disablePart(part)
        if not part:IsA("BasePart") then return end
        pcall(function()
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Massless = true
        end)
    end

    local function weldDetachedParts(model, root)
        local parent = {}
        local parts = {}
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then
                parent[object] = object
                parts[#parts + 1] = object
            end
        end

        local function find(part)
            while parent[part] ~= part do
                parent[part] = parent[parent[part]]
                part = parent[part]
            end
            return part
        end

        local function union(a, b)
            a, b = find(a), find(b)
            if a ~= b then parent[a] = b end
        end

        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("JointInstance") or object:IsA("WeldConstraint") then
                local p0, p1 = object.Part0, object.Part1
                local enabled = true
                pcall(function() enabled = object.Enabled end)
                if enabled and p0 and p1 and parent[p0] and parent[p1] then
                    union(p0, p1)
                end
            elseif object:IsA("Constraint") then
                local a0, a1 = object.Attachment0, object.Attachment1
                local p0 = a0 and a0.Parent
                local p1 = a1 and a1.Parent
                if p0 and p1 and parent[p0] and parent[p1] then
                    union(p0, p1)
                end
            end
        end

        local count = 0
        for _, part in ipairs(parts) do
            if find(part) ~= find(root) then
                local weld = Instance.new("WeldConstraint")
                weld.Name = "JXEntityWeld"
                weld.Part0 = root
                weld.Part1 = part
                weld.Parent = part
                union(part, root)
                count += 1
            end
        end
        return count
    end

    local function restoreCharacter()
        for part, old in pairs(hiddenParts) do
            if part and part.Parent then pcall(function() part.LocalTransparencyModifier = old end) end
        end
        table.clear(hiddenParts)

        for decal, old in pairs(hiddenDecals) do
            if decal and decal.Parent then pcall(function() decal.Transparency = old end) end
        end
        table.clear(hiddenDecals)
    end

    local function hideCharacterObject(object, character)
        if not object or not character or not object:IsDescendantOf(character) then return end
        if object:FindFirstAncestorOfClass("Tool") then return end

        if object:IsA("BasePart") then
            if hiddenParts[object] == nil then hiddenParts[object] = object.LocalTransparencyModifier end
            object.LocalTransparencyModifier = 1
        elseif object:IsA("Decal") or object:IsA("Texture") then
            if hiddenDecals[object] == nil then hiddenDecals[object] = object.Transparency end
            object.Transparency = 1
        end
    end

    local function disconnectAll()
        for key, connection in pairs(connections) do
            if connection then pcall(function() connection:Disconnect() end) end
            connections[key] = nil
        end
    end

    local function stopEntity()
        disconnectAll()
        if active then
            for _, track in pairs(active.Tracks or {}) do
                if track then pcall(function() track:Stop(0) end) end
            end
            for _, animation in ipairs(active.AnimationObjects or {}) do
                pcall(function() animation:Destroy() end)
            end
            if active.Model then pcall(function() active.Model:Destroy() end) end
        end
        active = nil
        restoreCharacter()
    end

    local function buildSlots(animations)
        local slots = {}
        for _, animation in ipairs(animations or {}) do
            local slot = classifyAnimation(animation.Name, animation.Group)
            if slot then
                slots[slot] = slots[slot] or animation
            end
        end
        if not slots.idle then slots.idle = slots.idle1 or slots.idle2 end
        return slots
    end

    local function getAnimationPriority(slot, saved)
        if saved and Enum.AnimationPriority[saved] then return Enum.AnimationPriority[saved] end
        if slot == "idle" or slot == "idle1" or slot == "idle2" then return Enum.AnimationPriority.Idle end
        if slot == "jump" or slot == "fall" or slot == "sit" then return Enum.AnimationPriority.Action end
        return Enum.AnimationPriority.Movement
    end

    local function loadEntityTrack(runtime, slot)
        if runtime.Tracks[slot] ~= nil then return runtime.Tracks[slot] or nil end
        local source = runtime.Slots[slot]
        if not source then runtime.Tracks[slot] = false return nil end

        local animationObject = Instance.new("Animation")
        animationObject.AnimationId = source.Id
        runtime.AnimationObjects[#runtime.AnimationObjects + 1] = animationObject

        local okLoad, trackOrError = pcall(function()
            local track = runtime.Animator:LoadAnimation(animationObject)
            track.Priority = getAnimationPriority(slot, source.Priority)
            track.Looped = slot == "idle" or slot == "idle1" or slot == "idle2"
                or slot == "walk" or slot == "run" or slot == "climb" or slot == "swim" or slot == "swimidle"
            return track
        end)

        if not okLoad or not trackOrError then
            runtime.Tracks[slot] = false
            runtime.Errors[#runtime.Errors + 1] = slot .. ": " .. tostring(trackOrError)
            return nil
        end

        runtime.Tracks[slot] = trackOrError
        return trackOrError
    end

    local function chooseSlot(runtime, humanoid, speed, state)
        local wanted
        if humanoid.Sit or state == Enum.HumanoidStateType.Seated then
            wanted = "sit"
        elseif state == Enum.HumanoidStateType.Climbing then
            wanted = "climb"
        elseif state == Enum.HumanoidStateType.Swimming then
            wanted = speed > 1 and "swim" or "swimidle"
        elseif state == Enum.HumanoidStateType.Jumping then
            wanted = "jump"
        elseif state == Enum.HumanoidStateType.Freefall then
            wanted = "fall"
        elseif speed > 0.5 then
            local threshold = math.max(10, humanoid.WalkSpeed * DEFAULTS.RunThreshold)
            if movementMode == "Auto" and runtime.Slots.run and speed >= threshold then
                wanted = "run"
            else
                wanted = "walk"
            end
        else
            if runtime.Slots.idle1 and runtime.Slots.idle2 then
                wanted = runtime.IdleVariant == 1 and "idle1" or "idle2"
            else
                wanted = "idle"
            end
        end

        local fallbacks = {
            idle = {"idle", "idle1", "idle2"},
            idle1 = {"idle1", "idle", "idle2"},
            idle2 = {"idle2", "idle", "idle1"},
            walk = {"walk", "run", "idle"},
            run = {"run", "walk", "idle"},
            jump = {"jump", "fall", "idle"},
            fall = {"fall", "jump", "idle"},
            climb = {"climb", "walk", "idle"},
            swim = {"swim", "walk", "idle"},
            swimidle = {"swimidle", "idle"},
            sit = {"sit", "idle"}
        }

        for _, candidate in ipairs(fallbacks[wanted] or {"idle"}) do
            if runtime.Slots[candidate] then return candidate end
        end
        return nil
    end

    local function isFirstPerson(character)
        local camera = Workspace.CurrentCamera
        local head = character and character:FindFirstChild("Head", true)
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not camera or not head or not humanoid then return false end
        local distance = (camera.CFrame.Position - head.Position).Magnitude
        local follows = camera.CameraSubject == humanoid
            or (camera.CameraSubject and camera.CameraSubject:IsDescendantOf(character))
        return follows and distance <= 1.65
    end

    local function setEntityVisibility(model, hidden)
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then
                object.LocalTransparencyModifier = hidden and 1 or 0
            elseif object:IsA("Decal") or object:IsA("Texture") then
                local okLocalTransparency = pcall(function()
                    object.LocalTransparencyModifier = hidden and 1 or 0
                end)
                if not okLocalTransparency then
                    if hidden then
                        if entityDecalTransparency[object] == nil then
                            entityDecalTransparency[object] = object.Transparency
                        end
                        object.Transparency = 1
                    elseif entityDecalTransparency[object] ~= nil then
                        object.Transparency = entityDecalTransparency[object]
                        entityDecalTransparency[object] = nil
                    end
                end
            end
        end
    end

    local function getPlayerFloorOffset(humanoid, root)
        local below = humanoid.HipHeight + root.Size.Y / 2
        if humanoid.RigType == Enum.HumanoidRigType.R6 then
            local leg = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Left Leg")
            below += leg and leg.Size.Y or 2
        end
        return below
    end

    local function applyEntity(entry)
        stopEntity()
        if type(clearSkinPreview) == "function" then
            pcall(clearSkinPreview)
        end
        if type(onEntityStart) == "function" then
            pcall(onEntityStart)
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local playerRoot = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not character or not humanoid or not playerRoot then
            notify("Entity Import", "Your character is not ready yet.", "Error")
            return false
        end

        local info = entry.Info
        if not info or not info.Template or not info.Template:IsA("Model") then
            local captureError
            info, captureError = captureEntity(entry.Path)
            if not info then
                notify("Entity Import", captureError, "Error")
                return false
            end
            entry.Info = info
        end

        local model = info.Template:Clone()
        model.Name = "JustXEntityPreview"

        local cloneHumanoid = model:FindFirstChildOfClass("Humanoid")
        if cloneHumanoid then
            pcall(function()
                cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                cloneHumanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                cloneHumanoid.RequiresNeck = false
                cloneHumanoid.AutomaticScalingEnabled = false
                cloneHumanoid.EvaluateStateMachine = false
                for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
                    if state ~= Enum.HumanoidStateType.None then cloneHumanoid:SetStateEnabled(state, false) end
                end
                cloneHumanoid:ChangeState(Enum.HumanoidStateType.None)
            end)
        end

        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then
                object.Anchored = false
                disablePart(object)
                object.LocalTransparencyModifier = 0
            elseif object:IsA("BillboardGui") or object:IsA("ProximityPrompt") then
                pcall(function() object.Enabled = false end)
            elseif object:IsA("ClickDetector") then
                pcall(function() object.MaxActivationDistance = 0 end)
            elseif object:IsA("Seat") or object:IsA("VehicleSeat") then
                pcall(function() object.Disabled = true end)
            elseif object:IsA("Sound") then
                pcall(function() object.Playing = false end)
            end
        end

        local playerHeight = 5
        pcall(function() playerHeight = character:GetExtentsSize().Y end)
        local entityHeight = math.max(info.Bounds.Size.Y, 0.01)
        local scale = scaleMode == "Fit" and math.clamp(playerHeight / entityHeight, 0.05, 100) or 1
        if math.abs(scale - 1) > 0.0001 then
            local okScale = pcall(function() model:ScaleTo(model:GetScale() * scale) end)
            if not okScale then scale = 1 end
        end

        local root = pickRoot(model)
        if not root then
            model:Destroy()
            notify("Entity Import", "The cloned model has no usable root part.", "Error")
            return false
        end

        weldDetachedParts(model, root)
        root.Anchored = true
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then disablePart(object) end
        end

        local controller = model:FindFirstChildWhichIsA("Humanoid", true)
            or model:FindFirstChildWhichIsA("AnimationController", true)
        if not controller then
            controller = Instance.new("AnimationController")
            controller.Name = "JXEntityAnimationController"
            controller.Parent = model
        end
        local animator = controller:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = controller
        end

        local slots = buildSlots(info.Animations)
        local bodyRotation = getBodyRotation(root.CFrame)
        local bounds = computeBounds(model, root, bodyRotation)
        if not bounds then
            model:Destroy()
            notify("Entity Import", "Could not measure the cloned model after scaling.", "Error")
            return false
        end

        local entityParts = {}
        for _, object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then entityParts[#entityParts + 1] = object end
        end

        local runtime = {
            Model = model,
            BodyRotation = bodyRotation,
            Bounds = bounds,
            Parts = entityParts,
            Root = root,
            Character = character,
            Humanoid = humanoid,
            PlayerRoot = playerRoot,
            Animator = animator,
            Slots = slots,
            Tracks = {},
            AnimationObjects = {},
            Errors = {},
            Slot = nil,
            IdleVariant = math.random(1, 2),
            Scale = scale,
            Info = info
        }

        local function positionEntity()
            local currentRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
            if not currentRoot then return end

            local look = currentRoot.CFrame.LookVector
            local yaw = math.abs(look.Y) < 0.98 and math.atan2(-look.X, -look.Z) or 0
            local facing = CFrame.Angles(0, yaw, 0)
            local floorBelow = getPlayerFloorOffset(humanoid, currentRoot)
            local offsetY = -floorBelow - bounds.Min.Y
            local horizontal = facing:VectorToWorldSpace(Vector3.new(bounds.Center.X, 0, bounds.Center.Z))
            local position = Vector3.new(
                currentRoot.Position.X - horizontal.X,
                currentRoot.Position.Y + offsetY,
                currentRoot.Position.Z - horizontal.Z
            )
            root.CFrame = CFrame.new(position) * facing * bodyRotation
        end

        positionEntity()
        model.Parent = Workspace
        RunService.Heartbeat:Wait()
        if not model:IsDescendantOf(Workspace) or not root.Parent then
            model:Destroy()
            notify("Entity Import", "The experience removed the local clone from Workspace.", "Error")
            return false
        end

        active = runtime
        for _, object in ipairs(character:GetDescendants()) do
            hideCharacterObject(object, character)
        end
        connections.CharacterAdded = character.DescendantAdded:Connect(function(object)
            hideCharacterObject(object, character)
        end)

        local visibleInFirstPerson = false
        local function update()
            if active ~= runtime then return end
            if LocalPlayer.Character ~= character or not character.Parent then
                stopEntity()
                return
            end
            if not model.Parent or not root.Parent then
                stopEntity()
                notify("Entity Import", "The game removed the local entity clone; your original character was restored.", "Warn")
                return
            end

            local currentRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
            if not currentRoot then return end

            local look = currentRoot.CFrame.LookVector
            local yaw = math.abs(look.Y) < 0.98 and math.atan2(-look.X, -look.Z) or 0
            local facing = CFrame.Angles(0, yaw, 0)
            local floorBelow = getPlayerFloorOffset(humanoid, currentRoot)
            local offsetY = -floorBelow - runtime.Bounds.Min.Y
            local horizontal = facing:VectorToWorldSpace(Vector3.new(runtime.Bounds.Center.X, 0, runtime.Bounds.Center.Z))
            local position = Vector3.new(
                currentRoot.Position.X - horizontal.X,
                currentRoot.Position.Y + offsetY,
                currentRoot.Position.Z - horizontal.Z
            )
            root.CFrame = CFrame.new(position) * facing * runtime.BodyRotation

            local cameraHidden = isFirstPerson(character)
            if cameraHidden ~= visibleInFirstPerson then
                visibleInFirstPerson = cameraHidden
                setEntityVisibility(model, cameraHidden)
            end

            local velocity = currentRoot.AssemblyLinearVelocity
            local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
            local state = humanoid:GetState()
            local wanted = chooseSlot(runtime, humanoid, speed, state)
            if wanted == "idle" and slots.idle1 and slots.idle2 then
                wanted = runtime.IdleVariant == 1 and "idle1" or "idle2"
            end
            if wanted ~= runtime.Slot then
                local old = runtime.Slot and runtime.Tracks[runtime.Slot]
                if old then pcall(function() old:Stop(0.15) end) end

                if wanted == "idle1" or wanted == "idle2" then
                    runtime.IdleVariant = wanted == "idle1" and 2 or 1
                end

                local track = wanted and loadEntityTrack(runtime, wanted)
                if track then
                    local okPlay, playError = pcall(function() track:Play(0.15, 1, 1) end)
                    if not okPlay then runtime.Errors[#runtime.Errors + 1] = tostring(playError) end
                end
                runtime.Slot = wanted
            end

            if runtime.Slot == "climb" then
                local track = runtime.Tracks.climb
                if track then pcall(function() track:AdjustSpeed(math.abs(velocity.Y) < 0.1 and 0 or 1) end) end
            end
        end

        connections.Render = RunService.RenderStepped:Connect(update)
        connections.PreSimulation = RunService.PreSimulation:Connect(function()
            if active ~= runtime then return end
            for _, part in ipairs(runtime.Parts) do
                if part and part.Parent then disablePart(part) end
            end
        end)

        update()
        local animationNames = {}
        for slot in pairs(slots) do animationNames[#animationNames + 1] = slot end
        table.sort(animationNames)

        local summary = string.format(
            "Loaded %s | %.2fx scale | %d parts | animations: %s",
            entry.Name,
            scale,
            info.PartCount,
            #animationNames > 0 and table.concat(animationNames, ", ") or "none"
        )
        if #runtime.Errors > 0 then
            summary ..= " | animation errors: " .. table.concat(runtime.Errors, " / ")
        end
        notify("Entity Import", summary, #runtime.Errors > 0 and "Warn" or "Success")
        return true
    end

    local function loadConfig()
        entries = {}
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        local ok, raw = pcall(function()
            if not isfile(CONFIG_FILE) then return nil end
            return readfile(CONFIG_FILE)
        end)
        if not ok or type(raw) ~= "string" or raw == "" then return end

        local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
        if not decodedOk or type(decoded) ~= "table" then return end
        for _, item in ipairs(decoded) do
            if type(item) == "table" and type(item.Path) == "string" and item.Path ~= "" then
                entries[#entries + 1] = {
                    Path = item.Path,
                    Name = tostring(item.Name or item.Path),
                    Info = nil
                }
            end
        end
    end

    local function saveConfig()
        if type(writefile) ~= "function" then return false end
        ensureFolder()
        local serializable = {}
        for _, item in ipairs(entries) do
            serializable[#serializable + 1] = {Path = item.Path, Name = item.Name}
        end
        return pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(serializable))
        end)
    end

    local function getEntryNames()
        local names = {}
        for _, item in ipairs(entries) do
            names[#names + 1] = item.Name .. "  [" .. item.Path .. "]"
        end
        return names
    end

    local function findEntry(option)
        if type(option) ~= "string" then return nil end
        for _, item in ipairs(entries) do
            if option == item.Name .. "  [" .. item.Path .. "]" then return item end
        end
        return nil
    end

    local function refreshDropdown()
        if entityDropdown and entityDropdown.Refresh then
            pcall(function() entityDropdown:Refresh() end)
        end
    end

    loadConfig()

    SkinSection:Divider()

    local pathInput = SkinSection:Input({
        Name = "Entity Model Path",
        Placeholder = "workspace.Monsters.Mimic",
        Flag = "JXU_EntityPath"
    })
    entityPathInput = pathInput

    entityNameInput = SkinSection:Input({
        Name = "Entity Name (Optional)",
        Placeholder = "Leave empty to use model name",
        Flag = "JXU_EntityName"
    })

    SkinSection:Dropdown({
        Name = "Entity Scale",
        Options = {"Auto Fit", "Native"},
        Search = false,
        MultiSelect = false,
        Flag = "JXU_EntityScale",
        Callback = function(value)
            scaleMode = value == "Native" and "Native" or "Fit"
        end
    })

    SkinSection:Dropdown({
        Name = "Movement Animations",
        Options = {"Auto (Walk + Run)", "Walk Only"},
        Search = false,
        MultiSelect = false,
        Flag = "JXU_EntityMovementMode",
        Callback = function(value)
            movementMode = value == "Walk Only" and "Walk Only" or "Auto"
        end
    })

    SkinSection:Button({
        Name = "Import / Update Entity",
        Callback = function()
            if busy then return end
            local path = trim(pathInput:Get())
            if path == "" then
                notify("Entity Import", "Enter a Model path first.", "Info")
                return
            end

            busy = true
            task.spawn(function()
                local info, captureError = captureEntity(path)
                busy = false
                if not info then
                    notify("Entity Import", captureError, "Error")
                    return
                end

                local customName = trim(entityNameInput:Get())
                local entry = nil
                for _, saved in ipairs(entries) do
                    if saved.Path:lower() == path:lower() then entry = saved break end
                end

                if entry then
                    if active and active.Info == entry.Info then stopEntity() end
                    if entry.Info and entry.Info.Template then
                        pcall(function() entry.Info.Template:Destroy() end)
                    end
                    entry.Info = info
                    if customName ~= "" then entry.Name = customName end
                else
                    entry = {
                        Path = path,
                        Name = customName ~= "" and customName or info.Name,
                        Info = info
                    }
                    entries[#entries + 1] = entry
                end

                selectedEntry = entry
                saveConfig()
                refreshDropdown()
                local found = {}
                for _, animation in ipairs(info.Animations) do
                    local slot = classifyAnimation(animation.Name, animation.Group)
                    if slot then found[slot] = true end
                end
                local names = {}
                for slot in pairs(found) do names[#names + 1] = slot end
                table.sort(names)
                notify(
                    "Entity Import",
                    string.format("%s imported: %d parts, %d accessories, animations: %s",
                        entry.Name, info.PartCount, info.AccessoryCount,
                        #names > 0 and table.concat(names, ", ") or "none detected"),
                    #names > 0 and "Success" or "Warn"
                )
            end)
        end
    })

    entityDropdown = SkinSection:Dropdown({
        Name = "Saved Entities",
        Options = getEntryNames,
        Search = true,
        MultiSelect = false,
        Flag = "JXU_SavedEntities",
        Callback = function(value)
            if type(value) == "table" then
                selectedEntry = nil
                for option, selected in pairs(value) do
                    if selected then selectedEntry = findEntry(option) break end
                end
            else
                selectedEntry = findEntry(value)
            end
        end
    })

    SkinSection:Button({
        Name = "Load Entity",
        Callback = function()
            if not selectedEntry then
                notify("Entity Import", "Select a saved entity first.", "Info")
                return
            end
            applyEntity(selectedEntry)
        end
    })

    SkinSection:Button({
        Name = "Delete Entity",
        Callback = function()
            if not selectedEntry then
                notify("Entity Import", "Select a saved entity first.", "Info")
                return
            end
            if active and active.Info == selectedEntry.Info then stopEntity() end
            for index = #entries, 1, -1 do
                if entries[index] == selectedEntry then table.remove(entries, index) end
            end
            if selectedEntry.Info and selectedEntry.Info.Template then
                pcall(function() selectedEntry.Info.Template:Destroy() end)
            end
            local deletedName = selectedEntry.Name
            selectedEntry = nil
            saveConfig()
            refreshDropdown()
            notify("Entity Import", "Deleted " .. deletedName, "Success")
        end
    })

    SkinSection:Button({
        Name = "Stop Entity Preview",
        Callback = stopEntity
    })

    LocalPlayer.CharacterAdded:Connect(function()
        stopEntity()
    end)

    return stopEntity
end
