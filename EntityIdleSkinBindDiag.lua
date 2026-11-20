-- ENTITY-IDLE-SKIN-BIND-DIAG-01
-- Read-only: inspects whether the 235 Bone instances are under a skinned MeshPart.
-- Does not change the rig.

local model = workspace:FindFirstChild("JustXEntityPreview", true)
if not model or not model:IsA("Model") then
    error("[SKIN-DIAG] Workspace.JustXEntityPreview not found")
end

local function safeGet(obj, prop)
    local ok, value = pcall(function() return obj[prop] end)
    if ok then return tostring(value) end
    return "<unavailable>"
end

local function countBones(root)
    local n = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("Bone") then n += 1 end
    end
    return n
end

local bones = {}
local meshParts = {}
local baseParts = {}

for _, obj in ipairs(model:GetDescendants()) do
    if obj:IsA("Bone") then
        table.insert(bones, obj)
    elseif obj:IsA("MeshPart") then
        table.insert(meshParts, obj)
    elseif obj:IsA("BasePart") then
        table.insert(baseParts, obj)
    end
end

print("[SKIN-DIAG] ===== START =====")
print("[SKIN-DIAG] Model: " .. model:GetFullName())
print(string.format("[SKIN-DIAG] Bones=%d | MeshParts=%d | BaseParts=%d", #bones, #meshParts, #baseParts))

local root = model:FindFirstChild("HumanoidRootPart", true)
if root then
    print(string.format(
        "[SKIN-DIAG] HumanoidRootPart class=%s | path=%s | descendantBones=%d | MeshId=%s | Size=%s",
        root.ClassName,
        root:GetFullName(),
        countBones(root),
        safeGet(root, "MeshId"),
        safeGet(root, "Size")
    ))
else
    print("[SKIN-DIAG] HumanoidRootPart NOT FOUND")
end

print("[SKIN-DIAG] --- MESH PARTS ---")
for _, part in ipairs(meshParts) do
    local n = countBones(part)
    print(string.format(
        "[SKIN-DIAG] MeshPart=%s | bonesBelow=%d | MeshId=%s | Size=%s | Transparency=%s",
        part:GetFullName(),
        n,
        safeGet(part, "MeshId"),
        safeGet(part, "Size"),
        safeGet(part, "Transparency")
    ))
end

print("[SKIN-DIAG] --- BONE ROOT / ANCESTOR CHECK ---")
local sampleNames = {
    "_rootJoint",
    "cog_05",
    "upperArm_l_085",
    "upperArm_r_0148",
    "stolenArm_tube_01_r_070",
    "huggy_upperArm_l_0219",
}
local wanted = {}
for _, name in ipairs(sampleNames) do wanted[name] = true end

for _, bone in ipairs(bones) do
    if wanted[bone.Name] then
        local ancestors = {}
        local nearestMesh = nil
        local nearestPart = nil
        local p = bone.Parent
        while p and p ~= model do
            table.insert(ancestors, p.Name .. ":" .. p.ClassName)
            if not nearestMesh and p:IsA("MeshPart") then nearestMesh = p end
            if not nearestPart and p:IsA("BasePart") then nearestPart = p end
            p = p.Parent
        end

        print(string.format(
            "[SKIN-DIAG] Bone=%s | nearestMesh=%s | nearestBasePart=%s | ancestors=%s",
            bone.Name,
            nearestMesh and nearestMesh:GetFullName() or "NONE",
            nearestPart and (nearestPart:GetFullName() .. " (" .. nearestPart.ClassName .. ")") or "NONE",
            table.concat(ancestors, " <- ")
        ))
    end
end

print("[SKIN-DIAG] --- MODEL CHILDREN ---")
for _, child in ipairs(model:GetChildren()) do
    print(string.format(
        "[SKIN-DIAG] Child=%s | class=%s | descendantBones=%d",
        child.Name, child.ClassName, countBones(child)
    ))
end

print("[SKIN-DIAG] ===== END (READ ONLY) =====")
