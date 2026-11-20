-- ENTITY-MOTOR6D-DIAG-01
-- Read-only inspection of the Entity's Motor6D rig connections.
local TARGET_NAME = "JustXEntityPreview"
local function log(s) print("[ENTITY-MOTOR6D-DIAG-01] " .. tostring(s)) end
local function safe(obj, key)
    local ok, v = pcall(function() return obj[key] end)
    if not ok then return "<unavailable>" end
    if typeof(v) == "Instance" then return v:GetFullName() end
    return tostring(v)
end
local model = workspace:FindFirstChild(TARGET_NAME, true)
if not model or not model:IsA("Model") then error("[ENTITY-MOTOR6D-DIAG-01] Model not found") end
log("========== START (READ ONLY) ==========")
log("Model=" .. model:GetFullName())
local motors = {}
for _, obj in ipairs(model:GetDescendants()) do
    if obj:IsA("Motor6D") then motors[#motors + 1] = obj end
end
log("Motor6D count=" .. #motors)
for i, motor in ipairs(motors) do
    log("--- MOTOR " .. i .. "/" .. #motors .. " ---")
    log("Path=" .. motor:GetFullName())
    log("Part0=" .. safe(motor, "Part0"))
    log("Part1=" .. safe(motor, "Part1"))
    log("C0=" .. safe(motor, "C0"))
    log("C1=" .. safe(motor, "C1"))
    log("Transform=" .. safe(motor, "Transform"))
    log("Enabled=" .. safe(motor, "Enabled"))
end
log("--- BASEPARTS ---")
local parts = {}
for _, obj in ipairs(model:GetDescendants()) do
    if obj:IsA("BasePart") then parts[#parts + 1] = obj end
end
log("BasePart count=" .. #parts)
for i, part in ipairs(parts) do
    log("PART " .. i .. ": " .. part:GetFullName() .. " | Anchored=" .. tostring(part.Anchored) .. " | AssemblyRootPart=" .. safe(part, "AssemblyRootPart"))
end
log("========== END (NO CHANGES MADE) ==========")
