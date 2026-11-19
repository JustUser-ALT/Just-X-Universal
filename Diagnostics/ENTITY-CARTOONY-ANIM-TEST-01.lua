--[[
    ENTITY-CARTOONY-ANIM-TEST-01

    Diagnoses the currently applied Animation Bundle against JustXEntityPreview.
    - Reads animation IDs from the player's current Animate script.
    - Checks asset delivery with PreloadAsync.
    - Tests those same clips on the Entity preview Animator.
    - Compares Bone / Motor6D names between the player and entity rigs.
    - Does not change the player's Animate script or character transforms.

    Run AFTER applying Cartoony Animation Pack and loading the Entity preview.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local MODEL_NAME = "JustXEntityPreview"
local LOAD_TIMEOUT = 6
local PLAY_TEST_TIME = 2.5

local function log(...)
    print("[ENTITY-CARTOONY-TEST]", ...)
end

local function pathOf(object, stopAt)
    local names = {}
    local current = object
    while current and current ~= stopAt do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return table.concat(names, "/")
end

local function findPreview()
    local model = Workspace:FindFirstChild(MODEL_NAME)
    if model then return model end
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") and object.Name == MODEL_NAME then
            return object
        end
    end
end

local function getRigObjects(model)
    local bones, motors = {}, {}
    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("Bone") then
            bones[#bones + 1] = object
        elseif object:IsA("Motor6D") then
            motors[#motors + 1] = object
        end
    end
    return bones, motors
end

local function getRigNames(model)
    local names = {}
    local bones, motors = getRigObjects(model)
    for _, object in ipairs(bones) do
        names[string.lower(object.Name)] = true
    end
    for _, object in ipairs(motors) do
        names[string.lower(object.Name)] = true
    end
    return names, bones, motors
end

local function getAnimationId(animation)
    local id = tostring(animation.AnimationId or "")
    local digits = id:match("(%d+)")
    if not digits or digits == "0" then return nil end
    return "rbxassetid://" .. digits
end

local function slotFromPath(path)
    local p = string.lower(path)
    if p:find("swimidle", 1, true) then return "swimidle" end
    if p:find("swim", 1, true) then return "swim" end
    if p:find("animation1", 1, true) or p:find("animation2", 1, true) or p:find("idle", 1, true) then return "idle" end
    if p:find("walk", 1, true) then return "walk" end
    if p:find("run", 1, true) then return "run" end
    if p:find("jump", 1, true) then return "jump" end
    if p:find("fall", 1, true) then return "fall" end
    if p:find("climb", 1, true) then return "climb" end
    return "other"
end

local character = LocalPlayer.Character
if not character then
    warn("[ENTITY-CARTOONY-TEST] LocalPlayer.Character is unavailable.")
    return
end

local animate = character:FindFirstChild("Animate")
if not animate then
    warn("[ENTITY-CARTOONY-TEST] Character.Animate not found. Apply the animation pack, then rerun.")
    return
end

local preview = findPreview()
if not preview then
    warn("[ENTITY-CARTOONY-TEST] JustXEntityPreview not found. Load the Entity first.")
    return
end

local entityController = preview:FindFirstChildOfClass("Humanoid")
    or preview:FindFirstChildOfClass("AnimationController")
local entityAnimator = entityController and entityController:FindFirstChildOfClass("Animator")
if not entityController or not entityAnimator then
    warn("[ENTITY-CARTOONY-TEST] Entity preview has no Humanoid/AnimationController Animator.")
    return
end

local playerController = character:FindFirstChildOfClass("Humanoid")
local playerAnimator = playerController and playerController:FindFirstChildOfClass("Animator")

log("========== START ==========")
log("PlaceId:", game.PlaceId, "GameId:", game.GameId)
log("Player character:", character:GetFullName())
log("Animate:", animate:GetFullName())
log("Entity:", preview:GetFullName())
log("Entity controller:", entityController.ClassName, entityController:GetFullName())

local animationsById = {}
local orderedAnimations = {}

for _, object in ipairs(animate:GetDescendants()) do
    if object:IsA("Animation") then
        local id = getAnimationId(object)
        if id then
            local path = pathOf(object, animate)
            local slot = slotFromPath(path)
            if not animationsById[id] then
                local entry = {
                    Id = id,
                    Slot = slot,
                    Paths = {},
                }
                animationsById[id] = entry
                orderedAnimations[#orderedAnimations + 1] = entry
            end
            table.insert(animationsById[id].Paths, path)
            if slot ~= "other" then animationsById[id].Slot = slot end
        end
    end
end

log("Player Animate Animation instances:", #orderedAnimations, "(unique IDs)")
for _, entry in ipairs(orderedAnimations) do
    log("PLAYER CLIP |", entry.Slot, "|", entry.Id, "| paths:", table.concat(entry.Paths, ", "))
end

if #orderedAnimations == 0 then
    warn("[ENTITY-CARTOONY-TEST] No usable AnimationIds found under Character.Animate.")
    return
end

local playerNames, playerBones, playerMotors = getRigNames(character)
local entityNames, entityBones, entityMotors = getRigNames(preview)

local sharedNames, playerOnlyNames, entityOnlyNames = {}, {}, {}
for name in pairs(playerNames) do
    if entityNames[name] then
        sharedNames[#sharedNames + 1] = name
    else
        playerOnlyNames[#playerOnlyNames + 1] = name
    end
end
for name in pairs(entityNames) do
    if not playerNames[name] then
        entityOnlyNames[#entityOnlyNames + 1] = name
    end
end
table.sort(sharedNames)
table.sort(playerOnlyNames)
table.sort(entityOnlyNames)

log("RIG NAME OVERLAP | Player Bone:", #playerBones, "Motor6D:", #playerMotors,
    "| Entity Bone:", #entityBones, "Motor6D:", #entityMotors)
log("Shared exact names:", #sharedNames,
    "| Player-only names:", #playerOnlyNames,
    "| Entity-only names:", #entityOnlyNames)
log("SHARED NAMES:", #sharedNames > 0 and table.concat(sharedNames, ", ") or "(none)")
log("PLAYER-ONLY NAMES:", #playerOnlyNames > 0 and table.concat(playerOnlyNames, ", ") or "(none)")
log("ENTITY-ONLY NAMES:", #entityOnlyNames > 0 and table.concat(entityOnlyNames, ", ") or "(none)")

log("--- ENTITY RIG INVENTORY ---")
for _, bone in ipairs(entityBones) do
    log("ENTITY BONE |", pathOf(bone, preview), "| Parent:", bone.Parent and bone.Parent.Name or "nil")
end
for _, motor in ipairs(entityMotors) do
    log("ENTITY MOTOR |", pathOf(motor, preview),
        "| Part0:", motor.Part0 and motor.Part0.Name or "nil",
        "| Part1:", motor.Part1 and motor.Part1.Name or "nil")
end

log("--- PLAYER RIG INVENTORY ---")
for _, bone in ipairs(playerBones) do
    log("PLAYER BONE |", pathOf(bone, character))
end
for _, motor in ipairs(playerMotors) do
    log("PLAYER MOTOR |", pathOf(motor, character),
        "| Part0:", motor.Part0 and motor.Part0.Name or "nil",
        "| Part1:", motor.Part1 and motor.Part1.Name or "nil")
end

local function snapshot()
    local values = {}
    for _, bone in ipairs(entityBones) do
        if bone.Parent then values[bone] = bone.Transform end
    end
    for _, motor in ipairs(entityMotors) do
        if motor.Parent then values[motor] = motor.Transform end
    end
    return values
end

local function countChanged(before)
    local changedBones, changedMotors = 0, 0
    local maxPosition, maxAngle = 0, 0
    for object, oldTransform in pairs(before) do
        if object.Parent then
            local delta = oldTransform:ToObjectSpace(object.Transform)
            local _, angle = delta:ToAxisAngle()
            local position = delta.Position.Magnitude
            local degrees = math.deg(angle)
            if position > 0.0001 or degrees > 0.01 then
                if object:IsA("Bone") then
                    changedBones += 1
                else
                    changedMotors += 1
                end
                maxPosition = math.max(maxPosition, position)
                maxAngle = math.max(maxAngle, degrees)
            end
        end
    end
    return changedBones, changedMotors, maxPosition, maxAngle
end

for index, entry in ipairs(orderedAnimations) do
    log(string.format("--- CLIP TEST %d/%d | %s | %s ---", index, #orderedAnimations, entry.Slot, entry.Id))

    local animation = Instance.new("Animation")
    animation.Name = "JX_Cartoony_Diagnostic_" .. index
    animation.AnimationId = entry.Id

    local preloadStatus = "NO CALLBACK"
    local preloadOk, preloadError = pcall(function()
        ContentProvider:PreloadAsync({animation}, function(assetId, status)
            preloadStatus = tostring(status)
            log("PRELOAD CALLBACK |", assetId, preloadStatus)
        end)
    end)
    log("PRELOAD RESULT |", preloadOk and "CALL OK" or "CALL ERROR",
        "| Status:", preloadStatus,
        "| Error:", preloadOk and "none" or tostring(preloadError))

    local track
    local loadOk, loadResult = pcall(function()
        return entityAnimator:LoadAnimation(animation)
    end)
    if loadOk then
        track = loadResult
    end
    log("ENTITY LoadAnimation:", loadOk and "OK" or "FAILED", loadOk and "" or tostring(loadResult))

    if track then
        local length = 0
        local waited = 0
        while waited < LOAD_TIMEOUT do
            task.wait(0.2)
            waited += 0.2
            pcall(function() length = track.Length end)
            if length > 0 then break end
        end
        log("ENTITY Track.Length:", length, "| Waited:", waited)

        local before = snapshot()
        local playOk, playError = pcall(function()
            track:Play(0.1, 1, 1)
        end)
        log("ENTITY Play:", playOk and "OK" or "ERROR", playOk and "" or tostring(playError))
        task.wait(PLAY_TEST_TIME)

        local changedBones, changedMotors, maxPosition, maxAngle = countChanged(before)
        log(string.format(
            "ENTITY RESPONSE | Bones %d/%d | Motor6D %d/%d | Max position %.5f | Max angle %.3f deg",
            changedBones, #entityBones, changedMotors, #entityMotors, maxPosition, maxAngle
        ))

        pcall(function() track:Stop(0.1) end)
        pcall(function() track:Destroy() end)
    end

    animation:Destroy()
    task.wait(0.2)
end

if playerAnimator then
    local playing = {}
    pcall(function()
        for _, track in ipairs(playerAnimator:GetPlayingAnimationTracks()) do
            local anim = track.Animation
            local id = anim and getAnimationId(anim)
            if id then
                playing[#playing + 1] = id .. " (Length " .. tostring(track.Length) .. ")"
            end
        end
    end)
    log("PLAYER CURRENTLY PLAYING TRACKS:", #playing,
        #playing > 0 and table.concat(playing, " | ") or "(none)")
end

log("========== FINISHED ==========")
log("Interpretation: Preload Success + Track.Length > 0 confirms delivery;")
log("zero Entity transforms means the loaded clip did not drive this rig's joints/bones.")
log("Name overlap is only a clue, not proof of a valid bone mapping.")
