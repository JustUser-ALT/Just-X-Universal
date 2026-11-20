-- ENTITY-IDLE-POSE-PROBE-01
-- Controlled test: applies frame 1 only to the main five-bone chain.
-- Restores every original Bone.Transform after 3 seconds.
-- Required file: EntityIdle_109391882672802.jxanim

local DATA_FILE = "EntityIdle_109391882672802.jxanim"

local ok, data = pcall(readfile, DATA_FILE)
if not ok or type(data) ~= "string" then
    error("[POSE-PROBE] Animation file not found: " .. DATA_FILE)
end
if string.sub(data, 1, 8) ~= "JXIDLE01" then
    error("[POSE-PROBE] Invalid animation header")
end

local cursor = 9
local frameCount, boneCount, duration
frameCount, cursor = string.unpack("<I4", data, cursor)
boneCount, cursor = string.unpack("<I4", data, cursor)
duration, cursor = string.unpack("<f", data, cursor)

local boneNames = table.create(boneCount)
local boneIndex = {}
for i = 1, boneCount do
    local length
    length, cursor = string.unpack("<I2", data, cursor)
    local name = string.sub(data, cursor, cursor + length - 1)
    cursor += length
    boneNames[i] = name
    boneIndex[name] = i
end

local firstFrameOffset = cursor
local framePos = firstFrameOffset + 4
local frame = {}

for i, name in ipairs(boneNames) do
    local x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22

    x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22, framePos =
        string.unpack("<ffffffffffff", data, framePos)

    frame[name] = CFrame.new(
        x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22
    )
end

local expected = {
    _rootJoint = {
        parent = "HumanoidRootPart",
        position = Vector3.new(0, -15.35, 0),
    },
    root_04 = {
        parent = "_rootJoint",
        position = Vector3.new(0, 0, 0),
    },
    cog_05 = {
        parent = "root_04",
        position = Vector3.new(0, 8.46007, 0),
    },
    pelvis_06 = {
        parent = "cog_05",
        position = Vector3.new(0, -8.46007, 0),
    },
    pelvis_fore_043 = {
        parent = "pelvis_06",
        position = Vector3.new(0, 9.90681, 2.02916),
    },
}

local model = workspace:FindFirstChild("JustXEntityPreview", true)
if not model or not model:IsA("Model") then
    error("[POSE-PROBE] Workspace.JustXEntityPreview was not found")
end

local bones = {}
local originals = {}

for name, info in pairs(expected) do
    local bone = nil
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("Bone") and obj.Name == name then
            bone = obj
            break
        end
    end

    if not bone then
        error("[POSE-PROBE] Missing target Bone: " .. name)
    end
    if not frame[name] then
        error("[POSE-PROBE] Missing animation Pose: " .. name)
    end

    local parentName = bone.Parent and bone.Parent.Name or "nil"
    local positionError = (bone.CFrame.Position - info.position).Magnitude

    print(string.format(
        "[POSE-PROBE] CHECK %s | parent=%s expected=%s | bind-position-error=%.5f",
        name,
        parentName,
        info.parent,
        positionError
    ))

    if parentName ~= info.parent or positionError > 0.05 then
        error("[POSE-PROBE] Target bind hierarchy/position mismatch at " .. name .. "; no transforms changed")
    end

    bones[name] = bone
    originals[name] = bone.Transform
end

local order = {
    "_rootJoint",
    "root_04",
    "cog_05",
    "pelvis_06",
    "pelvis_fore_043",
}

print(string.format(
    "[POSE-PROBE] Applying frame 1 to %d bones only | frames=%d | duration=%.2f",
    #order,
    frameCount,
    duration
))

for _, name in ipairs(order) do
    print(string.format(
        "[POSE-PROBE] POSE %s = (%.3f, %.3f, %.3f)",
        name,
        frame[name].Position.X,
        frame[name].Position.Y,
        frame[name].Position.Z
    ))
    bones[name].Transform = frame[name]
end

task.wait(3)

for _, name in ipairs(order) do
    local bone = bones[name]
    local okWorld, worldCF = pcall(function()
        return bone.TransformedWorldCFrame
    end)

    if okWorld then
        print(string.format(
            "[POSE-PROBE] AFTER %s | transformed-world=(%.3f, %.3f, %.3f)",
            name,
            worldCF.Position.X,
            worldCF.Position.Y,
            worldCF.Position.Z
        ))
    else
        print("[POSE-PROBE] AFTER " .. name .. " | TransformedWorldCFrame unavailable")
    end
end

for name, bone in pairs(bones) do
    if bone and bone.Parent then
        bone.Transform = originals[name]
    end
end

print("[POSE-PROBE] Finished; original transforms restored")
