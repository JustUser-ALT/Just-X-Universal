-- ENTITY-IDLE-FRAME-PROBE-02
-- Applies one non-neutral animation frame to every matching Bone.
-- Automatically restores all original Bone.Transform values after 5 seconds.
-- Required: EntityIdle_109391882672802.jxanim

local DATA_FILE = "EntityIdle_109391882672802.jxanim"
local FRAME_INDEX = 29
local HOLD_SECONDS = 5

local ok, data = pcall(readfile, DATA_FILE)
if not ok or type(data) ~= "string" then
    error("[FRAME-PROBE] Missing data file: " .. DATA_FILE)
end
if data:sub(1, 8) ~= "JXIDLE01" then
    error("[FRAME-PROBE] Invalid JXIDLE01 header")
end

local cursor = 9
local frameCount, boneCount, duration
frameCount, cursor = string.unpack("<I4", data, cursor)
boneCount, cursor = string.unpack("<I4", data, cursor)
duration, cursor = string.unpack("<f", data, cursor)

if FRAME_INDEX < 1 or FRAME_INDEX > frameCount then
    error("[FRAME-PROBE] Frame index outside animation")
end

local names = table.create(boneCount)
local indices = {}
for i = 1, boneCount do
    local length
    length, cursor = string.unpack("<I2", data, cursor)
    local name = data:sub(cursor, cursor + length - 1)
    cursor += length
    names[i] = name
    indices[name] = i
end

local frameStride = 4 + boneCount * 48
local frameOffset = cursor + (FRAME_INDEX - 1) * frameStride
local timestamp = string.unpack("<f", data, frameOffset)
local poseOffset = frameOffset + 4

local model = workspace:FindFirstChild("JustXEntityPreview", true)
if not model or not model:IsA("Model") then
    error("[FRAME-PROBE] Workspace.JustXEntityPreview not found")
end

local targetBones = {}
for _, obj in ipairs(model:GetDescendants()) do
    if obj:IsA("Bone") and indices[obj.Name] then
        targetBones[obj.Name] = obj
    end
end

local matched = 0
for _ in pairs(targetBones) do matched += 1 end
if matched ~= boneCount then
    error(string.format("[FRAME-PROBE] Matched %d/%d bones; refusing partial test", matched, boneCount))
end

local poses = {}
for i, name in ipairs(names) do
    local x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22

    x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22 =
        string.unpack("<ffffffffffff", data, poseOffset + (i - 1) * 48)

    poses[name] = CFrame.new(
        x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22
    )
end

local originals = {}
for name, bone in pairs(targetBones) do
    originals[name] = bone.Transform
end

local restoreDone = false
local function restore()
    if restoreDone then return end
    restoreDone = true
    for name, bone in pairs(targetBones) do
        if bone and bone.Parent then
            pcall(function()
                bone.Transform = originals[name]
            end)
        end
    end
end

local success, err = xpcall(function()
    print(string.format(
        "[FRAME-PROBE] Applying frame %d/%d | time=%.3fs | bones=%d | hold=%.1fs",
        FRAME_INDEX, frameCount, timestamp, matched, HOLD_SECONDS
    ))

    for name, bone in pairs(targetBones) do
        bone.Transform = poses[name]
    end

    for _, name in ipairs({
        "cog_05",
        "spine_01_074",
        "upperArm_l_085",
        "upperArm_r_0148",
        "stolenArm_tube_01_r_070",
        "huggy_upperArm_l_0219",
    }) do
        local bone = targetBones[name]
        if bone then
            local p = bone.TransformedWorldCFrame.Position
            print(string.format(
                "[FRAME-PROBE] WORLD %s = (%.3f, %.3f, %.3f)",
                name, p.X, p.Y, p.Z
            ))
        end
    end

    task.wait(HOLD_SECONDS)
end, debug.traceback)

restore()
print("[FRAME-PROBE] Original Bone.Transform values restored")

if not success then
    error("[FRAME-PROBE] " .. tostring(err))
end
