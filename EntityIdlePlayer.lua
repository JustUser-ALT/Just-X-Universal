-- ENTITY-IDLE-PLAYER-01
-- Plays the extracted original Entity Idle on the best-matching copied Entity rig.
-- Converts absolute keyframe Pose.CFrame values into Bone.Transform offsets using each bone's bind CFrame.
-- Required data file: EntityIdle_109391882672802.jxanim

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local ENV = getgenv and getgenv() or _G

if ENV.ENTITY_IDLE_PLAYER_STOP then
    pcall(ENV.ENTITY_IDLE_PLAYER_STOP)
end

local DATA_FILE = "EntityIdle_109391882672802.jxanim"
local ok, data = pcall(readfile, DATA_FILE)
if not ok or type(data) ~= "string" then
    error("[ENTITY-IDLE] Data file not found: " .. DATA_FILE)
end

if string.sub(data, 1, 8) ~= "JXIDLE01" then
    error("[ENTITY-IDLE] Invalid data file header")
end

local cursor = 9
local frameCount, boneCount, duration
frameCount, cursor = string.unpack("<I4", data, cursor)
boneCount, cursor = string.unpack("<I4", data, cursor)
duration, cursor = string.unpack("<f", data, cursor)

if frameCount ~= 541 or boneCount ~= 235 or duration <= 0 then
    error("[ENTITY-IDLE] Unexpected animation data dimensions")
end

local boneNames = table.create(boneCount)
for i = 1, boneCount do
    local length
    length, cursor = string.unpack("<I2", data, cursor)
    boneNames[i] = string.sub(data, cursor, cursor + length - 1)
    cursor += length
end

local animationBoneSet = {}
for _, name in ipairs(boneNames) do
    animationBoneSet[name] = true
end

local firstFrameOffset = cursor
local frameStride = 4 + boneCount * 48
local expectedSize = firstFrameOffset - 1 + frameCount * frameStride
if #data ~= expectedSize then
    error(string.format("[ENTITY-IDLE] Data size mismatch: expected %d, got %d", expectedSize, #data))
end

-- Prefer the known copied preview model when it exists.
-- Otherwise scan Workspace and choose the deepest Model with the best bone-name match.
local function collectBones(root)
    local map = {}
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("Bone") and animationBoneSet[obj.Name] and not map[obj.Name] then
            map[obj.Name] = obj
        end
    end
    return map
end

local model
local boneMap
local preferred = workspace:FindFirstChild("JustXEntityPreview")

if preferred and preferred:IsA("Model") then
    local preferredMap = collectBones(preferred)
    local count = 0
    for _ in pairs(preferredMap) do
        count += 1
    end
    if count > 0 then
        model = preferred
        boneMap = preferredMap
    end
end

if not model then
    local candidateScores = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Bone") and animationBoneSet[obj.Name] then
            local ancestor = obj.Parent
            while ancestor and ancestor ~= workspace do
                if ancestor:IsA("Model") then
                    local entry = candidateScores[ancestor]
                    if not entry then
                        entry = { score = 0, bones = {} }
                        candidateScores[ancestor] = entry
                    end
                    if not entry.bones[obj.Name] then
                        entry.bones[obj.Name] = obj
                        entry.score += 1
                    end
                end
                ancestor = ancestor.Parent
            end
        end
    end

    local bestScore = -1
    local bestDepth = -1
    for candidate, entry in pairs(candidateScores) do
        local depth = 0
        local parent = candidate.Parent
        while parent and parent ~= workspace do
            depth += 1
            parent = parent.Parent
        end

        if entry.score > bestScore or (entry.score == bestScore and depth > bestDepth) then
            model = candidate
            boneMap = entry.bones
            bestScore = entry.score
            bestDepth = depth
        end
    end
end

if not model or not boneMap then
    error("[ENTITY-IDLE] No Workspace Model contains any matching Entity animation bones")
end

local bones = table.create(boneCount)
local originals = table.create(boneCount)
local missing = {}
local matched = 0
for i, name in ipairs(boneNames) do
    local bone = boneMap[name]
    if bone then
        bones[i] = bone
        originals[i] = bone.Transform
        matched += 1
    else
        missing[#missing + 1] = name
    end
end

print(string.format("[ENTITY-IDLE] Bone map: %d/%d | target: %s", matched, boneCount, model:GetFullName()))

if #missing > 0 then
    error(string.format("[ENTITY-IDLE] Rig mismatch: %d/%d bones missing. First missing: %s", #missing, boneCount, table.concat(missing, ", ", 1, math.min(8, #missing))))
end

local function loadFrame(index)
    local frameOffset = firstFrameOffset + (index - 1) * frameStride
    local _, pos = string.unpack("<f", data, frameOffset)
    local transforms = table.create(boneCount)

    for i = 1, boneCount do
        local x, y, z,
            r00, r01, r02,
            r10, r11, r12,
            r20, r21, r22
        x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, pos = string.unpack("<ffffffffffff", data, pos)

        transforms[i] = CFrame.new(
            x, y, z,
            r00, r01, r02,
            r10, r11, r12,
            r20, r21, r22
        )
    end

    return transforms
end

local frameAIndex = -1
local frameBIndex = -1
local frameA
local frameB
local startTime = os.clock()
local stopped = false
local connection

local function stop()
    if stopped then
        return
    end
    stopped = true

    if connection then
        connection:Disconnect()
        connection = nil
    end

    for i, bone in ipairs(bones) do
        if bone and bone.Parent then
            bone.Transform = originals[i]
        end
    end

    if ENV.ENTITY_IDLE_PLAYER_STOP then
        ENV.ENTITY_IDLE_PLAYER_STOP = nil
    end

    print("[ENTITY-IDLE] Stopped; original Bone.Transform values restored")
end

ENV.ENTITY_IDLE_PLAYER_STOP = stop

local step = duration / (frameCount - 1)
connection = RunService.RenderStepped:Connect(function()
    if stopped or not model.Parent then
        stop()
        return
    end

    local t = (os.clock() - startTime) % duration
    local indexA = math.floor(t / step) + 1
    if indexA >= frameCount then
        indexA = frameCount - 1
    end
    local indexB = indexA + 1
    local alpha = math.clamp((t - (indexA - 1) * step) / step, 0, 1)

    if indexA ~= frameAIndex then
        frameA = loadFrame(indexA)
        frameAIndex = indexA
    end
    if indexB ~= frameBIndex then
        frameB = loadFrame(indexB)
        frameBIndex = indexB
    end

    for i, bone in ipairs(bones) do
        -- The exported keyframes contain the animated local Pose.CFrame, not a ready-to-use
        -- Bone.Transform offset. Convert from the bone's bind pose to its animation delta.
        local animatedLocalCFrame = frameA[i]:Lerp(frameB[i], alpha)
        bone.Transform = bone.CFrame:ToObjectSpace(animatedLocalCFrame)
    end
end)

print(string.format("[ENTITY-IDLE] Playing original Idle | %d frames | %d bones | %.2f sec | target: %s", frameCount, boneCount, duration, model:GetFullName()))
print("[ENTITY-IDLE] Stop with: getgenv().ENTITY_IDLE_PLAYER_STOP()")