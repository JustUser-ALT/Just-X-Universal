-- UGC Rig Structure Diagnostic V15
-- Inspects character rig joints, Bones, animation controllers and relevant descendants.
-- Does not play animations, modify the character, or change Animate.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local function log(message)
    print("[UGC V15] " .. tostring(message))
end

local character = localPlayer.Character
if not character or not character.Parent then
    log("ERROR: Character missing.")
    return
end

local counts = {
    Motor6D = 0,
    Bone = 0,
    Weld = 0,
    WeldConstraint = 0,
    AnimationController = 0,
    Humanoid = 0,
    BasePart = 0,
    Attachment = 0,
}

local examples = {
    Motor6D = {},
    Bone = {},
    Weld = {},
    WeldConstraint = {},
    AnimationController = {},
    BasePart = {},
}

local function addExample(kind, object)
    local list = examples[kind]
    if list and #list < 30 then
        list[#list + 1] = object:GetFullName()
    end
end

log("========== UGC Rig Structure Diagnostic V15 ==========")
log("Character: " .. character:GetFullName())
log("Class: " .. character.ClassName)

local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
    log("Humanoid: " .. humanoid:GetFullName())
    log("RigType: " .. tostring(humanoid.RigType))
    log("Humanoid state: " .. tostring(humanoid:GetState()))
else
    log("Humanoid: MISSING")
end

for _, object in ipairs(character:GetDescendants()) do
    if object:IsA("Motor6D") then
        counts.Motor6D += 1
        addExample("Motor6D", object)
    elseif object:IsA("Bone") then
        counts.Bone += 1
        addExample("Bone", object)
    elseif object:IsA("Weld") then
        counts.Weld += 1
        addExample("Weld", object)
    elseif object:IsA("WeldConstraint") then
        counts.WeldConstraint += 1
        addExample("WeldConstraint", object)
    elseif object:IsA("AnimationController") then
        counts.AnimationController += 1
        addExample("AnimationController", object)
    elseif object:IsA("Humanoid") then
        counts.Humanoid += 1
    elseif object:IsA("BasePart") then
        counts.BasePart += 1
        addExample("BasePart", object)
    elseif object:IsA("Attachment") then
        counts.Attachment += 1
    end
end

log("----- Object counts -----")
for name, count in pairs(counts) do
    log(name .. ": " .. tostring(count))
end

for kind, list in pairs(examples) do
    if #list > 0 then
        log("----- " .. kind .. " examples -----")
        for _, path in ipairs(list) do
            log(path)
        end
    end
end

log("----- Character direct children -----")
for _, child in ipairs(character:GetChildren()) do
    log(child.Name .. " | " .. child.ClassName)
end

log("----- Standard R15 body parts -----")
local partNames = {
    "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
for _, name in ipairs(partNames) do
    local part = character:FindFirstChild(name, true)
    log(name .. ": " .. (part and part.ClassName .. " | " .. part:GetFullName() or "MISSING"))
end

log("----- Animation-related descendants -----")
local animationCount = 0
for _, object in ipairs(character:GetDescendants()) do
    if object:IsA("Animation") then
        animationCount += 1
        if animationCount <= 50 then
            log("Animation: " .. object:GetFullName() .. " | " .. object.AnimationId)
        end
    elseif object:IsA("Animator") then
        log("Animator: " .. object:GetFullName())
    elseif object:IsA("Script") or object:IsA("LocalScript") then
        local lower = string.lower(object.Name)
        if string.find(lower, "anim") or string.find(lower, "character") or string.find(lower, "rig") then
            log("Script: " .. object:GetFullName() .. " | " .. object.ClassName)
        end
    end
end
log("Animation instance count: " .. tostring(animationCount))

log("RESULT: Read-only inspection completed. No character changes made.")
log("========== END V15 ==========")
