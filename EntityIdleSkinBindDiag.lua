-- ENTITY-SKIN-BIND-DIAG-02
-- Read-only inspection of InitialPoses and MeshPart skinning-related metadata.
-- Does not modify the model, bones, parts, or animation state.

local TARGET_NAME = "JustXEntityPreview"
local MAX_POSE_NODES = 100
local function log(s) print("[SKIN-BIND-DIAG] " .. tostring(s)) end
local function read(obj, key)
    local ok, value = pcall(function() return obj[key] end)
    if not ok then return "<unavailable>" end
    if typeof(value) == "Instance" then return value.ClassName .. ":" .. value.Name end
    return tostring(value)
end
local function valueText(v)
    if typeof(v) == "Instance" then return v.ClassName .. ":" .. v.Name end
    local s = tostring(v)
    if #s > 180 then s = string.sub(s, 1, 180) .. "..." end
    return s
end

local model = workspace:FindFirstChild(TARGET_NAME, true)
if not model or not model:IsA("Model") then
    error("[SKIN-BIND-DIAG] Model not found: " .. TARGET_NAME)
end
log("========== START (READ ONLY) ==========")
log("Model: " .. model:GetFullName())

local poses = model:FindFirstChild("InitialPoses", true)
if poses then
    log("--- INITIAL POSES: " .. poses:GetFullName() .. " [" .. poses.ClassName .. "] ---")
    local count = 0
    local function walk(parent, depth)
        if depth > 5 or count >= MAX_POSE_NODES then return end
        for _, child in ipairs(parent:GetChildren()) do
            if count >= MAX_POSE_NODES then break end
            count += 1
            local line = string.rep("  ", depth) .. child.Name .. " [" .. child.ClassName .. "]"
            if child:IsA("ValueBase") then line ..= " Value=" .. valueText(child.Value) end
            if child:IsA("Bone") then line ..= " CFrame=" .. tostring(child.CFrame) end
            log(line)
            if #child:GetChildren() > 0 then walk(child, depth + 1) end
        end
    end
    walk(poses, 0)
    log("InitialPoses nodes listed=" .. count)
else
    log("InitialPoses: NOT FOUND")
end

local meshes, bones = {}, {}
for _, obj in ipairs(model:GetDescendants()) do
    if obj:IsA("MeshPart") then meshes[#meshes + 1] = obj end
    if obj:IsA("Bone") then bones[#bones + 1] = obj end
end
log("--- COUNTS: MeshParts=" .. #meshes .. " | Bones=" .. #bones .. " ---")

local props = {
    "MeshId", "MeshContent", "TextureID", "TextureContent",
    "RenderFidelity", "CollisionFidelity", "DoubleSided",
    "Size", "Transparency", "LocalTransparencyModifier",
    "VertexColor", "RootPriority", "Archivable"
}
for i, part in ipairs(meshes) do
    log("--- MESHPART " .. i .. "/" .. #meshes .. ": " .. part:GetFullName() .. " ---")
    for _, key in ipairs(props) do log(key .. "=" .. read(part, key)) end

    local classCounts, boneCount = {}, 0
    for _, d in ipairs(part:GetDescendants()) do
        classCounts[d.ClassName] = (classCounts[d.ClassName] or 0) + 1
        if d:IsA("Bone") then boneCount += 1 end
    end
    local classes = {}
    for className, n in pairs(classCounts) do classes[#classes + 1] = className .. "=" .. n end
    table.sort(classes)
    log("Descendants=" .. #part:GetDescendants() .. " | BonesBelow=" .. boneCount .. " | Classes=" .. (#classes > 0 and table.concat(classes, ", ") or "none"))

    local children = part:GetChildren()
    log("DirectChildren=" .. #children)
    for j = 1, math.min(#children, 24) do
        local child = children[j]
        log("  Child " .. j .. ": " .. child.Name .. " [" .. child.ClassName .. "]")
    end
    if #children > 24 then log("  ... " .. (#children - 24) .. " more") end

    local ok, attrs = pcall(function() return part:GetAttributes() end)
    if ok then
        local keys = {}
        for key in pairs(attrs) do keys[#keys + 1] = key end
        table.sort(keys)
        log("Attributes=" .. #keys)
        for _, key in ipairs(keys) do log("  Attribute " .. key .. "=" .. valueText(attrs[key])) end
    else
        log("Attributes=<unavailable>")
    end
end

log("--- BONE ROOTS ---")
local roots = {}
for _, bone in ipairs(bones) do
    if not bone.Parent or not bone.Parent:IsA("Bone") then roots[#roots + 1] = bone end
end
log("BoneRoots=" .. #roots)
for i, bone in ipairs(roots) do
    log("Root " .. i .. ": " .. bone:GetFullName() .. " | parent=" .. (bone.Parent and bone.Parent.ClassName or "nil"))
end
log("========== END (NO CHANGES MADE) ==========")
