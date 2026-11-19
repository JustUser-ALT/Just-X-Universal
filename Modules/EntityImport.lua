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
    local VISUAL_LIFT = 15
    local entries = {}
    local selectedEntry
    local active
    local connections = {}
    local hiddenParts = {}
    local hiddenDecals = {}
    local entityDecalTransparency = setmetatable({}, {__mode = "k"})
    local entityNameInput
    local entityDropdown
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

    local function isPlayerCharacterSource(source)
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            if character and (source == character or source:IsDescendantOf(character)) then
                return true, player.Name, character
            end
        end
        return false
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
                            -- Convert each corner into the exact orientation frame that
                            -- will be used by targetRootCFrame (facing * bodyRotation).
                            -- This keeps the floor minimum and visual center correct for
                            -- tilted/custom monster rigs instead of assuming an upright root.
                            local rootLocalPoint = root.CFrame:PointToObjectSpace(worldPoint)
                            local point = bodyRotation
                                and bodyRotation:VectorToWorldSpace(rootLocalPoint)
                                or rootLocalPoint
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

    local function createAvatarDescriptionModel(description, rigType)
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

    local AVATAR_DESCRIPTION_FIELDS = {
        "BackAccessory", "BodyTypeScale", "ClimbAnimation", "DepthScale",
        "Face", "FaceAccessory", "FallAnimation", "FrontAccessory",
        "GraphicTShirt", "HairAccessory", "HatAccessory", "Head",
        "HeadColor", "HeadScale", "HeightScale", "IdleAnimation",
        "JumpAnimation", "LeftArm", "LeftArmColor", "LeftLeg",
        "LeftLegColor", "NeckAccessory", "Pants", "ProportionScale",
        "RightArm", "RightArmColor", "RightLeg", "RightLegColor",
        "RunAnimation", "Shirt", "ShouldersAccessory", "SwimAnimation",
        "Torso", "TorsoColor", "WaistAccessory", "WalkAnimation",
        "WidthScale", "MoodAnimation", "AccessoryBlob"
    }

    local function captureAvatarDescription(description, rigType)
        local data = {RigType = rigType == Enum.HumanoidRigType.R6 and "R6" or "R15", Properties = {}}
        for _, property in ipairs(AVATAR_DESCRIPTION_FIELDS) do
            pcall(function()
                local value = description[property]
                if typeof(value) == "Color3" then
                    data.Properties[property] = {Type = "Color3", Value = {value.R, value.G, value.B}}
                elseif type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
                    data.Properties[property] = {Type = typeof(value), Value = value}
                end
            end)
        end
        return data
    end

    local function buildAvatarDescription(data)
        if type(data) ~= "table" or type(data.Properties) ~= "table" then
            return nil, "Saved avatar description is missing or damaged"
        end
        local description = Instance.new("HumanoidDescription")
        for property, packed in pairs(data.Properties) do
            if type(packed) == "table" then
                pcall(function()
                    if packed.Type == "Color3" and type(packed.Value) == "table" then
                        local value = packed.Value
                        description[property] = Color3.new(
                            tonumber(value[1]) or 1,
                            tonumber(value[2]) or 1,
                            tonumber(value[3]) or 1
                        )
                    elseif packed.Type == "string" or packed.Type == "number" or packed.Type == "boolean" then
                        description[property] = packed.Value
                    end
                end)
            end
        end
        local rigType = data.RigType == "R6" and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15
        return description, rigType
    end

    local function captureEntity(path, sourceOverride)
        local source, resolveError
        if sourceOverride then
            source = sourceOverride
        else
            source, resolveError = resolvePath(path)
        end
        if not source then return nil, resolveError end

        local isPlayerCharacter, playerName, playerCharacter = isPlayerCharacterSource(source)
        local animationSource = source
        local sourceName = source.Name

        if isPlayerCharacter then
            if playerName ~= LocalPlayer.Name then
                return nil, "Importing another player's character is disabled. You can import only your own character."
            end

            -- A custom monster skin can be applied to the local character while its
            -- real appearance remains in the live character hierarchy. HumanoidDescription
            -- cannot represent arbitrary meshes, textures, SurfaceAppearance or custom rigs,
            -- so normalize any selected descendant to the complete live character and clone it.
            animationSource = playerCharacter
            sourceName = playerCharacter.Name
            source = playerCharacter
        end

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
            Name = sourceName,
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
        for _, object in ipairs(animationSource:GetDescendants()) do
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
        until os.clock() >= sampleDeadline or not animationSource.Parent

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

    local SERIALIZABLE_CLASSES = {
        Model = true, Folder = true, Accessory = true, Tool = true,
        Attachment = true, Bone = true, SpecialMesh = true,
        Decal = true, Texture = true, SurfaceAppearance = true,
        BodyColors = true, Shirt = true, Pants = true, ShirtGraphic = true,
        CharacterMesh = true, Humanoid = true, Animator = true,
        HumanoidDescription = true,
        Animation = true, Motor6D = true, Weld = true,
        WeldConstraint = true, ManualWeld = true, Snap = true,
        HingeConstraint = true, BallSocketConstraint = true,
        RopeConstraint = true, RodConstraint = true, SpringConstraint = true,
        CylindricalConstraint = true, PrismaticConstraint = true,
        AlignPosition = true, AlignOrientation = true,
        NoCollisionConstraint = true, WrapLayer = true, WrapTarget = true
    }

    local function packVector3(value)
        return {value.X, value.Y, value.Z}
    end

    local function packColor3(value)
        return {value.R, value.G, value.B}
    end

    local function packCFrame(value)
        return {value:GetComponents()}
    end

    local function enumName(value)
        return tostring(value):match("%.([^%.]+)$")
    end

    local HUMANOID_DESCRIPTION_PROPERTIES = {
        "BackAccessory", "BodyTypeScale", "ClimbAnimation", "DepthScale",
        "Face", "FaceAccessory", "FallAnimation", "FrontAccessory",
        "GraphicTShirt", "HairAccessory", "HatAccessory", "Head",
        "HeadColor", "HeadScale", "HeightScale", "IdleAnimation",
        "JumpAnimation", "LeftArm", "LeftArmColor", "LeftLeg",
        "LeftLegColor", "NeckAccessory", "Pants", "ProportionScale",
        "RightArm", "RightArmColor", "RightLeg", "RightLegColor",
        "RunAnimation", "Shirt", "ShouldersAccessory", "SwimAnimation",
        "Torso", "TorsoColor", "WaistAccessory", "WalkAnimation",
        "WidthScale", "MoodAnimation", "AccessoryBlob", "Emotes",
        "EquippedEmotes"
    }

    local HUMANOID_PROPERTIES = {
        "RigType", "DisplayDistanceType", "HealthDisplayType",
        "Health", "MaxHealth", "HipHeight", "WalkSpeed", "JumpPower",
        "JumpHeight", "UseJumpPower", "AutoRotate", "BreakJointsOnDeath",
        "RequiresNeck", "AutomaticScalingEnabled", "EvaluateStateMachine"
    }

    local function packProperty(value)
        local valueType = typeof(value)
        if valueType == "Color3" then
            return {Type = "Color3", Value = packColor3(value)}
        elseif valueType == "EnumItem" then
            return {Type = "Enum", Value = enumName(value)}
        elseif valueType == "string" or valueType == "number" or valueType == "boolean" then
            return {Type = valueType, Value = value}
        end
        return nil
    end

    local function serializeProperties(object, propertyNames)
        local result = {}
        for _, property in ipairs(propertyNames) do
            pcall(function()
                local packed = packProperty(object[property])
                if packed then result[property] = packed end
            end)
        end
        return result
    end

    local function serializeModel(model, animations)
        local root = pickRoot(model)
        if not root then return nil, "No root part found for portable save" end

        local nodes = {}
        local indices = {}
        local unsupported = {}
        local rootFrame = root.CFrame

        local function visit(object, parentIndex)
            local isPart = object:IsA("BasePart")
            local supported = object == model or isPart or SERIALIZABLE_CLASSES[object.ClassName]
            local nextParent = parentIndex

            if supported then
                local node = {
                    Class = object.ClassName,
                    Name = object.Name,
                    Parent = parentIndex,
                    Props = {}
                }
                local props = node.Props

                if isPart then
                    props.CFrame = packCFrame(rootFrame:ToObjectSpace(object.CFrame))
                    props.Size = packVector3(object.Size)
                    props.Color = packColor3(object.Color)
                    props.Material = enumName(object.Material)
                    props.Transparency = object.Transparency
                    props.Reflectance = object.Reflectance
                    props.Anchored = object.Anchored
                    props.CanCollide = object.CanCollide
                    props.CanTouch = object.CanTouch
                    props.CanQuery = object.CanQuery
                    props.Massless = object.Massless
                    props.CastShadow = object.CastShadow
                    props.TopSurface = enumName(object.TopSurface)
                    props.BottomSurface = enumName(object.BottomSurface)
                    if object:IsA("Part") then props.Shape = enumName(object.Shape) end
                    if object:IsA("MeshPart") then
                        pcall(function() props.MeshId = object.MeshId end)
                        pcall(function() props.TextureID = object.TextureID end)
                    elseif object:IsA("UnionOperation") then
                        unsupported.UnionOperation = true
                    end
                elseif object:IsA("Attachment") then
                    props.CFrame = packCFrame(object.CFrame)
                    props.Axis = packVector3(object.Axis)
                    props.SecondaryAxis = packVector3(object.SecondaryAxis)
                elseif object:IsA("SpecialMesh") then
                    props.MeshType = enumName(object.MeshType)
                    props.MeshId = object.MeshId
                    props.TextureId = object.TextureId
                    props.Scale = packVector3(object.Scale)
                    props.Offset = packVector3(object.Offset)
                    props.VertexColor = packVector3(object.VertexColor)
                elseif object:IsA("Decal") or object:IsA("Texture") then
                    props.Texture = object.Texture
                    props.Transparency = object.Transparency
                    props.Color3 = packColor3(object.Color3)
                    props.Face = enumName(object.Face)
                    if object:IsA("Texture") then
                        props.StudsPerTileU = object.StudsPerTileU
                        props.StudsPerTileV = object.StudsPerTileV
                    end
                elseif object:IsA("Animation") then
                    props.AnimationId = object.AnimationId
                elseif object:IsA("SurfaceAppearance") then
                    pcall(function() props.ColorMap = object.ColorMap end)
                    pcall(function() props.MetalnessMap = object.MetalnessMap end)
                    pcall(function() props.NormalMap = object.NormalMap end)
                    pcall(function() props.RoughnessMap = object.RoughnessMap end)
                elseif object:IsA("BodyColors") then
                    props.HeadColor = packColor3(object.HeadColor3)
                    props.TorsoColor = packColor3(object.TorsoColor3)
                    props.LeftArmColor = packColor3(object.LeftArmColor3)
                    props.RightArmColor = packColor3(object.RightArmColor3)
                    props.LeftLegColor = packColor3(object.LeftLegColor3)
                    props.RightLegColor = packColor3(object.RightLegColor3)
                elseif object:IsA("Shirt") then
                    props.ShirtTemplate = object.ShirtTemplate
                elseif object:IsA("Pants") then
                    props.PantsTemplate = object.PantsTemplate
                elseif object:IsA("ShirtGraphic") then
                    props.Graphic = object.Graphic
                elseif object:IsA("CharacterMesh") then
                    props.BodyPart = enumName(object.BodyPart)
                    props.MeshId = object.MeshId
                    props.BaseTextureId = object.BaseTextureId
                    props.OverlayTextureId = object.OverlayTextureId
                elseif object:IsA("Humanoid") then
                    props.HumanoidProperties = serializeProperties(object, HUMANOID_PROPERTIES)
                elseif object:IsA("HumanoidDescription") then
                    props.DescriptionProperties = serializeProperties(object, HUMANOID_DESCRIPTION_PROPERTIES)
                end

                local index = #nodes + 1
                nodes[index] = node
                indices[object] = index
                nextParent = index
            else
                unsupported[object.ClassName] = true
            end

            for _, child in ipairs(object:GetChildren()) do
                visit(child, nextParent)
            end
        end

        visit(model, nil)

        for object, index in pairs(indices) do
            local node = nodes[index]
            local props = node.Props
            if object:IsA("JointInstance") then
                props.Part0 = indices[object.Part0]
                props.Part1 = indices[object.Part1]
                props.C0 = packCFrame(object.C0)
                props.C1 = packCFrame(object.C1)
            elseif object:IsA("WeldConstraint") then
                props.Part0 = indices[object.Part0]
                props.Part1 = indices[object.Part1]
            elseif object:IsA("Constraint") then
                props.Attachment0 = indices[object.Attachment0]
                props.Attachment1 = indices[object.Attachment1]
            end
        end

        local primaryIndex = indices[model.PrimaryPart] or indices[root]
        local warningNames = {}
        for className in pairs(unsupported) do warningNames[#warningNames + 1] = className end
        table.sort(warningNames)

        return {
            Version = 1,
            Name = model.Name,
            RootIndex = indices[root],
            PrimaryPartIndex = primaryIndex,
            Nodes = nodes,
            Animations = animations or {},
            Unsupported = warningNames
        }, warningNames
    end

    local function deserializeModel(data)
        if type(data) ~= "table" or data.Version ~= 1 or type(data.Nodes) ~= "table" then
            return nil, "Unsupported or damaged portable entity file"
        end

        local objects = {}
        local fallbackMeshes = {}

        for index, node in ipairs(data.Nodes) do
            local className = tostring(node.Class or "")
            local isPart = className == "Part" or className == "MeshPart"
                or className == "UnionOperation" or className == "WedgePart"
                or className == "CornerWedgePart" or className == "TrussPart"
                or className == "SpawnLocation" or className == "Seat"
                or className == "VehicleSeat"
            local createClass = className
            local okCreate, object = pcall(function() return Instance.new(createClass) end)
            if not okCreate or not object then
                if isPart then
                    object = Instance.new("Part")
                    fallbackMeshes[index] = true
                else
                    return nil, "This executor cannot recreate the '" .. className .. "' class"
                end
            end

            object.Name = tostring(node.Name or className)
            objects[index] = object
            local parentIndex = tonumber(node.Parent)
            if parentIndex and objects[parentIndex] then
                object.Parent = objects[parentIndex]
            end
        end

        local function vectorFrom(value)
            if type(value) ~= "table" then return Vector3.zero end
            return Vector3.new(tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0)
        end

        local function colorFrom(value)
            if type(value) ~= "table" then return Color3.new(1, 1, 1) end
            return Color3.new(tonumber(value[1]) or 1, tonumber(value[2]) or 1, tonumber(value[3]) or 1)
        end

        local function cframeFrom(value)
            if type(value) ~= "table" or #value < 12 then return CFrame.new() end
            return CFrame.new(table.unpack(value, 1, 12))
        end

        local function setEnum(object, property, enumType, name)
            if type(name) ~= "string" then return end
            pcall(function() object[property] = enumType[name] end)
        end

        local function restoreProperties(object, properties, enumTypes)
            if type(properties) ~= "table" then return end
            for property, packed in pairs(properties) do
                if type(packed) == "table" then
                    pcall(function()
                        if packed.Type == "Color3" then
                            object[property] = colorFrom(packed.Value)
                        elseif packed.Type == "Enum" then
                            local enumType = enumTypes[property]
                            if enumType and type(packed.Value) == "string" then
                                object[property] = enumType[packed.Value]
                            end
                        elseif packed.Type == "string" or packed.Type == "number" or packed.Type == "boolean" then
                            object[property] = packed.Value
                        end
                    end)
                end
            end
        end

        local humanoidEnumTypes = {
            RigType = Enum.HumanoidRigType,
            DisplayDistanceType = Enum.HumanoidDisplayDistanceType,
            HealthDisplayType = Enum.HumanoidHealthDisplayType
        }

        for index, node in ipairs(data.Nodes) do
            local object = objects[index]
            local props = node.Props or {}
            if object:IsA("BasePart") then
                pcall(function() object.Size = vectorFrom(props.Size) end)
                pcall(function() object.Color = colorFrom(props.Color) end)
                pcall(function() object.Transparency = tonumber(props.Transparency) or 0 end)
                pcall(function() object.Reflectance = tonumber(props.Reflectance) or 0 end)
                pcall(function() object.Anchored = true end)
                pcall(function() object.CanCollide = props.CanCollide == true end)
                pcall(function() object.CanTouch = props.CanTouch == true end)
                pcall(function() object.CanQuery = props.CanQuery ~= false end)
                pcall(function() object.Massless = props.Massless == true end)
                pcall(function() object.CastShadow = props.CastShadow ~= false end)
                setEnum(object, "Material", Enum.Material, props.Material)
                setEnum(object, "TopSurface", Enum.SurfaceType, props.TopSurface)
                setEnum(object, "BottomSurface", Enum.SurfaceType, props.BottomSurface)
                if object:IsA("Part") then setEnum(object, "Shape", Enum.PartType, props.Shape) end

                local relative = cframeFrom(props.CFrame)
                pcall(function() object.CFrame = relative end)

                if object:IsA("MeshPart") then
                    local meshOk = pcall(function()
                        object.MeshId = props.MeshId or ""
                        object.TextureID = props.TextureID or ""
                    end)
                    if not meshOk and props.MeshId and props.MeshId ~= "" then
                        fallbackMeshes[index] = true
                        local mesh = Instance.new("SpecialMesh")
                        mesh.MeshType = Enum.MeshType.FileMesh
                        mesh.MeshId = props.MeshId
                        mesh.TextureId = props.TextureID or ""
                        mesh.Parent = object
                    end
                elseif fallbackMeshes[index] and props.MeshId and props.MeshId ~= "" then
                    local mesh = Instance.new("SpecialMesh")
                    mesh.MeshType = Enum.MeshType.FileMesh
                    mesh.MeshId = props.MeshId
                    mesh.TextureId = props.TextureID or ""
                    mesh.Parent = object
                end
            elseif object:IsA("Attachment") then
                pcall(function() object.CFrame = cframeFrom(props.CFrame) end)
                pcall(function() object.Axis = vectorFrom(props.Axis) end)
                pcall(function() object.SecondaryAxis = vectorFrom(props.SecondaryAxis) end)
            elseif object:IsA("SpecialMesh") then
                setEnum(object, "MeshType", Enum.MeshType, props.MeshType)
                pcall(function() object.MeshId = props.MeshId or "" end)
                pcall(function() object.TextureId = props.TextureId or "" end)
                pcall(function() object.Scale = vectorFrom(props.Scale) end)
                pcall(function() object.Offset = vectorFrom(props.Offset) end)
                pcall(function() object.VertexColor = vectorFrom(props.VertexColor) end)
            elseif object:IsA("Decal") or object:IsA("Texture") then
                pcall(function() object.Texture = props.Texture or "" end)
                pcall(function() object.Transparency = tonumber(props.Transparency) or 0 end)
                pcall(function() object.Color3 = colorFrom(props.Color3) end)
                setEnum(object, "Face", Enum.NormalId, props.Face)
                if object:IsA("Texture") then
                    pcall(function() object.StudsPerTileU = tonumber(props.StudsPerTileU) or 1 end)
                    pcall(function() object.StudsPerTileV = tonumber(props.StudsPerTileV) or 1 end)
                end
            elseif object:IsA("Animation") then
                pcall(function() object.AnimationId = props.AnimationId or "" end)
            elseif object:IsA("SurfaceAppearance") then
                pcall(function() object.ColorMap = props.ColorMap or "" end)
                pcall(function() object.MetalnessMap = props.MetalnessMap or "" end)
                pcall(function() object.NormalMap = props.NormalMap or "" end)
                pcall(function() object.RoughnessMap = props.RoughnessMap or "" end)
            elseif object:IsA("BodyColors") then
                pcall(function() object.HeadColor3 = colorFrom(props.HeadColor) end)
                pcall(function() object.TorsoColor3 = colorFrom(props.TorsoColor) end)
                pcall(function() object.LeftArmColor3 = colorFrom(props.LeftArmColor) end)
                pcall(function() object.RightArmColor3 = colorFrom(props.RightArmColor) end)
                pcall(function() object.LeftLegColor3 = colorFrom(props.LeftLegColor) end)
                pcall(function() object.RightLegColor3 = colorFrom(props.RightLegColor) end)
            elseif object:IsA("Shirt") then
                pcall(function() object.ShirtTemplate = props.ShirtTemplate or "" end)
            elseif object:IsA("Pants") then
                pcall(function() object.PantsTemplate = props.PantsTemplate or "" end)
            elseif object:IsA("ShirtGraphic") then
                pcall(function() object.Graphic = props.Graphic or "" end)
            elseif object:IsA("CharacterMesh") then
                setEnum(object, "BodyPart", Enum.BodyPart, props.BodyPart)
                pcall(function() object.MeshId = props.MeshId or "" end)
                pcall(function() object.BaseTextureId = props.BaseTextureId or "" end)
                pcall(function() object.OverlayTextureId = props.OverlayTextureId or "" end)
            elseif object:IsA("Humanoid") then
                restoreProperties(object, props.HumanoidProperties, humanoidEnumTypes)
            elseif object:IsA("HumanoidDescription") then
                restoreProperties(object, props.DescriptionProperties, {})
            end
        end

        for index, node in ipairs(data.Nodes) do
            local object = objects[index]
            local props = node.Props or {}
            if object:IsA("JointInstance") then
                pcall(function()
                    object.Part0 = objects[props.Part0]
                    object.Part1 = objects[props.Part1]
                    object.C0 = cframeFrom(props.C0)
                    object.C1 = cframeFrom(props.C1)
                end)
            elseif object:IsA("WeldConstraint") then
                pcall(function()
                    object.Part0 = objects[props.Part0]
                    object.Part1 = objects[props.Part1]
                end)
            elseif object:IsA("Constraint") then
                pcall(function()
                    object.Attachment0 = objects[props.Attachment0]
                    object.Attachment1 = objects[props.Attachment1]
                end)
            end
        end

        -- A restored Humanoid must have an Animator. The Animator itself is
        -- serialized as a structural node when present; create one if it was absent.
        for _, object in ipairs(objects) do
            if object and object:IsA("Humanoid") and not object:FindFirstChildOfClass("Animator") then
                local animator = Instance.new("Animator")
                animator.Parent = object
            end
        end

        local model = objects[1]
        if not model or not model:IsA("Model") then
            for _, object in ipairs(objects) do
                if object and object:IsA("Model") then model = object break end
            end
        end
        if not model then
            for _, object in ipairs(objects) do if object then object:Destroy() end end
            return nil, "Portable file does not contain a Model"
        end

        local primary = objects[tonumber(data.PrimaryPartIndex)]
        if primary and primary:IsA("BasePart") then
            pcall(function() model.PrimaryPart = primary end)
        end
        return model
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
            local threshold = math.max(17, humanoid.WalkSpeed * 0.9)
            if runtime.Slots.run and speed >= threshold then
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
            if entry.Data then
                if type(entry.Data.AvatarDescription) == "table" then
                    local description, rigTypeOrError = buildAvatarDescription(entry.Data.AvatarDescription)
                    if not description then
                        notify("Entity Import", rigTypeOrError, "Error")
                        return false
                    end
                    local okGenerate, generatedOrError = pcall(function()
                        return createAvatarDescriptionModel(description, rigTypeOrError)
                    end)
                    pcall(function() description:Destroy() end)
                    if not okGenerate or not generatedOrError or not generatedOrError:IsA("Model") then
                        notify("Entity Import", "Could not rebuild avatar from saved HumanoidDescription: " .. tostring(generatedOrError), "Error")
                        return false
                    end
                    info = {
                        Template = generatedOrError,
                        Path = entry.Path or "",
                        Name = entry.Name,
                        Animations = type(entry.Data.Animations) == "table" and entry.Data.Animations or {},
                        Warnings = {},
                        PartCount = 0,
                        AccessoryCount = 0
                    }
                else
                    local restoredModel, restoreError = deserializeModel(entry.Data)
                    if not restoredModel then
                        notify("Entity Import", restoreError, "Error")
                        return false
                    end
                    info, captureError = captureEntity(entry.Path or entry.Name, restoredModel)
                    restoredModel:Destroy()
                    if info and type(entry.Data.Animations) == "table" then
                        info.Animations = entry.Data.Animations
                    end
                end
            else
                notify("Entity Import", "This is an old path-only entry. Re-import it in the original game to create a portable copy.", "Warn")
                return false
            end
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
        -- Preserve the selected root's offset from the model pivot. PivotTo moves
        -- the complete entity even when its PrimaryPart is far from its visual center.
        local rootToPivot = root.CFrame:ToObjectSpace(model:GetPivot())
        -- The clone is aligned directly to the raycast floor. Keep the
        -- player's root Y at activation as the jump/fall reference so only
        -- the local clone follows vertical movement.
        local initialPlayerRootY = playerRoot.Position.Y
        local bounds = computeBounds(model, root, bodyRotation)
        if not bounds then
            model:Destroy()
            notify("Entity Import", "Could not measure the cloned model.", "Error")
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
            Info = info
        }

        local floorRayParams = RaycastParams.new()
        floorRayParams.FilterType = Enum.RaycastFilterType.Exclude
        floorRayParams.FilterDescendantsInstances = {character, model}
        floorRayParams.IgnoreWater = true

        local function getFloorY(currentRoot)
            local rayOrigin = currentRoot.Position + Vector3.new(0, 2, 0)
            local rayLength = math.max(getPlayerFloorOffset(humanoid, currentRoot) + 32, 64)
            local result = Workspace:Raycast(
                rayOrigin,
                Vector3.new(0, -rayLength, 0),
                floorRayParams
            )
            if result then return result.Position.Y end
            return currentRoot.Position.Y - getPlayerFloorOffset(humanoid, currentRoot)
        end

        local function positionEntity()
            local currentRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
            if not currentRoot then return end

            local look = currentRoot.CFrame.LookVector
            local yaw = math.abs(look.Y) < 0.98 and math.atan2(-look.X, -look.Z) or 0
            local facing = CFrame.Angles(0, yaw, 0)
            local floorY = getFloorY(currentRoot)
            local horizontal = facing:VectorToWorldSpace(Vector3.new(bounds.Center.X, 0, bounds.Center.Z))
            -- Ground alignment is independent of the player's HipHeight.
            -- This delta moves only the clone when the real character jumps/falls.
            local verticalOffset = currentRoot.Position.Y - initialPlayerRootY
            local position = Vector3.new(
                currentRoot.Position.X - horizontal.X,
                floorY - bounds.Min.Y + verticalOffset + VISUAL_LIFT,
                currentRoot.Position.Z - horizontal.Z
            )
            local targetRootCFrame = CFrame.new(position) * facing * bodyRotation
            model:PivotTo(targetRootCFrame * rootToPivot)
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

            -- The default Roblox camera transparency controller can overwrite
            -- LocalTransparencyModifier when switching between first and third person.
            -- Reapply the local hide while this entity preview is active.
            for _, object in ipairs(character:GetDescendants()) do
                hideCharacterObject(object, character)
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
            local floorY = getFloorY(currentRoot)
            local horizontal = facing:VectorToWorldSpace(Vector3.new(runtime.Bounds.Center.X, 0, runtime.Bounds.Center.Z))
            -- Follow only the real character's vertical displacement since activation.
            local verticalOffset = currentRoot.Position.Y - initialPlayerRootY
            local position = Vector3.new(
                currentRoot.Position.X - horizontal.X,
                floorY - runtime.Bounds.Min.Y + verticalOffset + VISUAL_LIFT,
                currentRoot.Position.Z - horizontal.Z
            )
            local targetRootCFrame = CFrame.new(position) * facing * runtime.BodyRotation
            model:PivotTo(targetRootCFrame * rootToPivot)

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
            "Loaded %s | %d parts | animations: %s",
            entry.Name,
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
            if type(item) == "table" then
                local data = item.Data
                if type(item.DataFile) == "string" and isfile(item.DataFile) then
                    local dataOk, dataRaw = pcall(readfile, item.DataFile)
                    if dataOk and type(dataRaw) == "string" then
                        local decodeOk, decodedData = pcall(function() return HttpService:JSONDecode(dataRaw) end)
                        if decodeOk and type(decodedData) == "table" then data = decodedData end
                    end
                end
                if type(item.Name) == "string" then
                    entries[#entries + 1] = {
                        Id = tostring(item.Id or HttpService:GenerateGUID(false)),
                        Path = tostring(item.Path or ""),
                        Name = item.Name,
                        Data = type(data) == "table" and data or nil,
                        DataFile = item.DataFile,
                        Info = nil
                    }
                end
            end
        end
    end

    local function saveConfig()
        if type(writefile) ~= "function" then return false end
        local serializable = {}
        for _, item in ipairs(entries) do
            local saved = {
                Id = item.Id,
                Path = item.Path,
                Name = item.Name
            }
            if type(item.Data) == "table" then
                local dataFile = item.DataFile or ("JustXUniversal_Entity_" .. tostring(item.Id) .. ".json")
                local dataOk = pcall(function()
                    writefile(dataFile, HttpService:JSONEncode(item.Data))
                end)
                if dataOk then
                    item.DataFile = dataFile
                    saved.DataFile = dataFile
                else
                    saved.Data = item.Data
                end
            elseif item.DataFile then
                saved.DataFile = item.DataFile
            end
            serializable[#serializable + 1] = saved
        end
        local ok = pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(serializable))
        end)
        return ok
    end

    local function getEntryLabel(item)
        return item.Name .. "  [" .. (item.Data and "Portable" or item.Path ~= "" and item.Path or "Missing data") .. "]"
    end

    local function getEntryNames()
        local names = {}
        for _, item in ipairs(entries) do names[#names + 1] = getEntryLabel(item) end
        return names
    end

    local function findEntry(option)
        if type(option) ~= "string" then return nil end
        for _, item in ipairs(entries) do
            if option == getEntryLabel(item) then return item end
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

    entityNameInput = SkinSection:Input({
        Name = "Entity Name (Optional)",
        Placeholder = "Leave empty to use model name",
        Flag = "JXU_EntityName"
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

                local portableData, unsupportedClasses = serializeModel(info.Template, info.Animations)
                if portableData and type(info.AvatarDescription) == "table" then
                    portableData.AvatarDescription = info.AvatarDescription
                end
                if not portableData then
                    info.Template:Destroy()
                    notify("Entity Import", unsupportedClasses, "Error")
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
                    entry.Data = portableData
                    entry.Id = entry.Id or HttpService:GenerateGUID(false)
                    if customName ~= "" then entry.Name = customName end
                else
                    entry = {
                        Id = HttpService:GenerateGUID(false),
                        Path = path,
                        Name = customName ~= "" and customName or info.Name,
                        Info = info,
                        Data = portableData
                    }
                    entries[#entries + 1] = entry
                end

                selectedEntry = entry
                local savedToDisk = saveConfig()
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
                if not savedToDisk then
                    notify("Entity Import", "Portable copy is ready for this session, but file saving failed. Check executor file permissions.", "Warn")
                elseif #unsupportedClasses > 0 then
                    notify("Entity Import", "Portable copy saved. Some object classes could not be preserved: " .. table.concat(unsupportedClasses, ", "), "Warn")
                else
                    notify("Entity Import", "Portable copy saved to device storage. It can now be loaded in other games.", "Success")
                end
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
            if selectedEntry.DataFile and type(deletefile) == "function" then
                pcall(deletefile, selectedEntry.DataFile)
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
