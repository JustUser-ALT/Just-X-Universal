--[[
    ENTITY-IDLE-BONE-DIAG

    Read-only diagnostic for the copied Entity rig.
    Does not play animations or modify Bone.CFrame / Bone.Transform.

    Run in the game containing Workspace.JustXEntityPreview.
]]

local Players = game:GetService("Players")
local TARGET_NAME = "JustXEntityPreview"

local PREFIX = "[ENTITY-BONE-DIAG] "

local function log(...)
    print(PREFIX .. table.concat({...}, " "))
end

local function pathOf(instance)
    local parts = {}
    local current = instance
    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return table.concat(parts, ".")
end

local function cfToString(cf)
    local c = {cf:GetComponents()}
    local out = {}
    for i, value in ipairs(c) do
        out[i] = string.format("%.5f", value)
    end
    return table.concat(out, ", ")
end

local function findTarget()
    local exact = workspace:FindFirstChild(TARGET_NAME, true)
    if exact and exact:IsA("Model") then
        return exact
    end

    local bestModel, bestCount = nil, 0
    local counts = {}
    for _, item in ipairs(workspace:GetDescendants()) do
        if item:IsA("Bone") then
            local parent = item.Parent
            while parent and parent ~= workspace do
                if parent:IsA("Model") then
                    counts[parent] = (counts[parent] or 0) + 1
                end
                parent = parent.Parent
            end
        end
    end
    for model, count in pairs(counts) do
        if count > bestCount then
            bestModel, bestCount = model, count
        end
    end
    return bestModel
end

local target = findTarget()
if not target then
    warn(PREFIX .. "No Model containing Bones found in Workspace")
    return
end

local allBones = {}
local byName = {}
for _, item in ipairs(target:GetDescendants()) do
    if item:IsA("Bone") then
        table.insert(allBones, item)
        byName[item.Name] = byName[item.Name] or {}
        table.insert(byName[item.Name], item)
    end
end

log("========== START ==========")
log("Target:", pathOf(target))
log("Bone count:", tostring(#allBones))

local important = {
    "_rootJoint",
    "root_04",
    "cog_05",
    "pelvis_06",
    "pelvis_fore_043",
    "wrist",
    "wrist_01",
    "hand",
    "hand_01",
}

local printed = {}
for _, name in ipairs(important) do
    local matches = byName[name]
    if matches then
        for _, bone in ipairs(matches) do
            printed[bone] = true
        end
    end
end

-- Include likely wrist/hand bones even when their exact suffix differs.
for _, bone in ipairs(allBones) do
    local lower = string.lower(bone.Name)
    if string.find(lower, "wrist", 1, true)
        or string.find(lower, "hand", 1, true) then
        printed[bone] = true
    end
end

for _, bone in ipairs(allBones) do
    if printed[bone] then
        local parentBone = bone.Parent
        while parentBone and not parentBone:IsA("Bone") do
            parentBone = parentBone.Parent
        end

        log("--------------------------------")
        log("Bone:", bone.Name)
        log("Path:", pathOf(bone))
        log("Parent Bone:", parentBone and parentBone.Name or "none")
        log("CFrame:", cfToString(bone.CFrame))
        log("Transform:", cfToString(bone.Transform))
        log("WorldCFrame:", cfToString(bone.WorldCFrame))
        if parentBone then
            log("Parent CFrame:", cfToString(parentBone.CFrame))
            log("Parent Transform:", cfToString(parentBone.Transform))
        end
    end
end

log("========== ALL BONE NAMES ==========")
for _, bone in ipairs(allBones) do
    log(bone.Name)
end
log("========== END ==========")
