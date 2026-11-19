--[[
    ENTITY-ANIMATOR-TEST-01

    Standalone diagnostic for the currently active Just X Entity preview.
    Does not modify EntityImport.lua or the player's character.

    Run only AFTER loading the Entity preview.
    Output is written to the executor console.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")

local MODEL_NAME = "JustXEntityPreview"
local TEST_ANIMATIONS = {
    "rbxassetid://109391882672802",
    "rbxassetid://115889468727927",
    "rbxassetid://85459989322843",
    "rbxassetid://105786754679189"
}

local function log(...)
    print("[ENTITY-ANIM-TEST]", ...)
end

local function findPreview()
    local model = Workspace:FindFirstChild(MODEL_NAME)
    if model then return model end

    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") and object.Name == MODEL_NAME then
            return object
        end
    end
    return nil
end

local model = findPreview()
if not model then
    warn("[ENTITY-ANIM-TEST] JustXEntityPreview not found. Load the Entity first.")
    return
end

local controller = model:FindFirstChildOfClass("Humanoid")
    or model:FindFirstChildOfClass("AnimationController")
local animator = controller and controller:FindFirstChildOfClass("Animator")

if not controller then
    warn("[ENTITY-ANIM-TEST] No Humanoid or AnimationController inside preview.")
    return
end

if not animator then
    warn("[ENTITY-ANIM-TEST] Controller exists but Animator is missing.")
    return
end

local bones = {}
local motors = {}
for _, object in ipairs(model:GetDescendants()) do
    if object:IsA("Bone") then
        bones[#bones + 1] = object
    elseif object:IsA("Motor6D") then
        motors[#motors + 1] = object
    end
end

log("========== START ==========")
log("PlaceId:", game.PlaceId, "GameId:", game.GameId)
log("Model:", model:GetFullName())
log("Controller:", controller.ClassName, controller:GetFullName())
log("Animator:", animator:GetFullName())
log("Rig counts | Bones:", #bones, "| Motor6D:", #motors)
log("Testing", #TEST_ANIMATIONS, "source animation IDs.")

local function snapshot()
    local values = {}
    for _, bone in ipairs(bones) do
        if bone.Parent then
            values[bone] = bone.Transform
        end
    end
    for _, motor in ipairs(motors) do
        if motor.Parent then
            values[motor] = motor.Transform
        end
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
            if position > 0.0001 or math.deg(angle) > 0.01 then
                if object:IsA("Bone") then
                    changedBones += 1
                else
                    changedMotors += 1
                end
                maxPosition = math.max(maxPosition, position)
                maxAngle = math.max(maxAngle, math.deg(angle))
            end
        end
    end

    return changedBones, changedMotors, maxPosition, maxAngle
end

for index, animationId in ipairs(TEST_ANIMATIONS) do
    log(string.format("--- TEST %d/%d | %s ---", index, #TEST_ANIMATIONS, animationId))

    local animation = Instance.new("Animation")
    animation.Name = "JX_AnimatorDiagnostic_" .. index
    animation.AnimationId = animationId

    local preloadStatus = "NO CALLBACK"
    local preloadOk, preloadError = pcall(function()
        ContentProvider:PreloadAsync({animation}, function(assetId, status)
            preloadStatus = tostring(status)
            log("Preload callback:", assetId, preloadStatus)
        end)
    end)

    log("Preload call:", preloadOk and "OK" or "ERROR", preloadOk and "" or tostring(preloadError))
    log("Preload status:", preloadStatus)

    local loadOk, trackOrError = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not loadOk or not trackOrError then
        log("LoadAnimation: FAILED", tostring(trackOrError))
        animation:Destroy()
        task.wait(0.25)
        continue
    end

    local track = trackOrError
    log("LoadAnimation: OK", "Priority:", tostring(track.Priority), "Looped:", track.Looped)

    local length = 0
    for _ = 1, 20 do
        task.wait(0.1)
        pcall(function() length = track.Length end)
        if length > 0 then break end
    end
    log("Track Length:", length)

    local before = snapshot()
    local playOk, playError = pcall(function()
        track:Play(0.1, 1, 1)
    end)
    log("Play:", playOk and "OK" or "ERROR", playOk and "" or tostring(playError))

    task.wait(2)

    local changedBones, changedMotors, maxPosition, maxAngle = countChanged(before)
    log(string.format(
        "TRANSFORM RESULT | Changed Bones: %d/%d | Changed Motor6D: %d/%d | Max position delta: %.5f | Max angle delta: %.3f deg",
        changedBones, #bones, changedMotors, #motors, maxPosition, maxAngle
    ))

    pcall(function() track:Stop(0.1) end)
    pcall(function() track:Destroy() end)
    animation:Destroy()
    task.wait(0.25)
end

log("========== FINISHED ==========")
log("Note: a successful LoadAnimation call alone does not prove the asset finished loading.")
log("Use the Preload status, Track Length, and transform results together.")
