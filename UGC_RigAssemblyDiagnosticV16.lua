-- UGC Rig Assembly Diagnostic V16
-- Read-only diagnostic. Does not modify character, joints, constraints, or Animate.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function log(...)
    print("[UGC V16]", ...)
end

local function fullName(instance)
    local ok, result = pcall(function()
        return instance:GetFullName()
    end)
    return ok and result or tostring(instance)
end

local function safeRead(callback)
    local ok, result = pcall(callback)
    if ok then
        return tostring(result)
    end
    return "<ERROR: " .. tostring(result) .. ">"
end

local function shortList(items, limit)
    local output = {}
    for index, item in ipairs(items) do
        if index > limit then
            table.insert(output, "...")
            break
        end
        table.insert(output, fullName(item))
    end
    return #output > 0 and table.concat(output, ", ") or "<none>"
end

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")
local root = character:FindFirstChild("HumanoidRootPart")

log("========== UGC Rig Assembly Diagnostic V16 ==========")
log("Character:", fullName(character))
log("RigType:", humanoid and tostring(humanoid.RigType) or "<no Humanoid>")
log("HumanoidState:", humanoid and safeRead(function() return humanoid:GetState() end) or "<none>")
log("HumanoidRootPart:", root and fullName(root) or "<missing>")
if root then
    log("Root Anchored:", safeRead(function() return root.Anchored end))
    log("Root AssemblyRootPart:", safeRead(function()
        return root.AssemblyRootPart and fullName(root.AssemblyRootPart) or "nil"
    end))
    log("Root AssemblyMass:", safeRead(function() return root.AssemblyMass end))
    log("Root AssemblyLinearVelocity:", safeRead(function() return root.AssemblyLinearVelocity end))
    log("Root AssemblyAngularVelocity:", safeRead(function() return root.AssemblyAngularVelocity end))
end

local descendants = character:GetDescendants()
local parts = {}
local jointInstances = {}
local constraints = {}
local attachments = {}
local scripts = {}

for _, instance in ipairs(descendants) do
    if instance:IsA("BasePart") then
        table.insert(parts, instance)
    end
    if instance:IsA("JointInstance") then
        table.insert(jointInstances, instance)
    end
    if instance:IsA("Constraint") then
        table.insert(constraints, instance)
    end
    if instance:IsA("Attachment") then
        table.insert(attachments, instance)
    end
    if instance:IsA("BaseScript") then
        table.insert(scripts, instance)
    end
end

log("Descendants:", #descendants)
log("BaseParts:", #parts)
log("JointInstances:", #jointInstances)
log("Constraints:", #constraints)
log("Attachments:", #attachments)
log("BaseScripts:", #scripts)

for _, joint in ipairs(jointInstances) do
    log("JOINT", fullName(joint),
        "Class:", joint.ClassName,
        "Part0:", safeRead(function() return joint.Part0 and fullName(joint.Part0) or "nil" end),
        "Part1:", safeRead(function() return joint.Part1 and fullName(joint.Part1) or "nil" end),
        "Enabled:", safeRead(function() return joint.Enabled end))
end

for _, constraint in ipairs(constraints) do
    log("CONSTRAINT", fullName(constraint),
        "Class:", constraint.ClassName,
        "Enabled:", safeRead(function() return constraint.Enabled end),
        "Attachment0:", safeRead(function()
            local value = constraint.Attachment0
            return value and fullName(value) or "nil"
        end),
        "Attachment1:", safeRead(function()
            local value = constraint.Attachment1
            return value and fullName(value) or "nil"
        end))
end

for _, part in ipairs(parts) do
    local connected = {}
    local connectedResult = safeRead(function()
        connected = part:GetConnectedParts(true)
        return #connected
    end)

    local joints = {}
    local jointsResult = safeRead(function()
        joints = part:GetJoints()
        return #joints
    end)

    log("PART", fullName(part),
        "| Anchored:", safeRead(function() return part.Anchored end),
        "| AssemblyRoot:", safeRead(function()
            return part.AssemblyRootPart and fullName(part.AssemblyRootPart) or "nil"
        end),
        "| AssemblyMass:", safeRead(function() return part.AssemblyMass end),
        "| ConnectedParts:", connectedResult,
        "| ConnectedList:", shortList(connected, 12),
        "| GetJoints:", jointsResult,
        "| JointList:", shortList(joints, 8),
        "| LinearVelocity:", safeRead(function() return part.AssemblyLinearVelocity end),
        "| AngularVelocity:", safeRead(function() return part.AssemblyAngularVelocity end))
end

for _, scriptObject in ipairs(scripts) do
    log("SCRIPT", fullName(scriptObject),
        "Class:", scriptObject.ClassName,
        "Enabled:", safeRead(function() return scriptObject.Enabled end),
        "Disabled:", safeRead(function() return scriptObject.Disabled end))

    if scriptObject.Name == "BindToPlatform" then
        local sourceOk, source = pcall(function()
            return scriptObject.Source
        end)
        if sourceOk then
            log("BindToPlatform.Source accessible; length:", #source)
            log("BindToPlatform.Source BEGIN")
            print(source)
            log("BindToPlatform.Source END")
        else
            log("BindToPlatform.Source inaccessible:", tostring(source))
        end
    end
end

log("========== V16 COMPLETE ==========")
