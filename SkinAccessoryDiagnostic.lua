-- JustXUniversal Skin Accessory Diagnostic
-- Inspect one catalog asset without modifying the character or the main hub.

local ASSET_ID = 14447815815
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function log(...)
    print("[SkinAccessoryDiagnostic]", ...)
end

local function safeGet(object, property)
    local ok, value = pcall(function()
        return object[property]
    end)
    if ok then
        return tostring(value)
    end
    return "<unavailable>"
end

local function dumpTree(root, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)
    log(indent .. root.Name .. " [" .. root.ClassName .. "]")

    if root:IsA("Attachment") then
        log(indent .. "  Position:", safeGet(root, "Position"))
        log(indent .. "  Orientation:", safeGet(root, "Orientation"))
        log(indent .. "  Axis:", safeGet(root, "Axis"))
    elseif root:IsA("WrapLayer") then
        for _, property in ipairs({
            "CageMeshId", "ReferenceMeshId", "Order", "Puffiness",
            "BindOffset", "Enabled"
        }) do
            log(indent .. "  " .. property .. ":", safeGet(root, property))
        end
    elseif root:IsA("WrapTarget") then
        for _, property in ipairs({
            "CageMeshId", "Stiffness", "Enabled"
        }) do
            log(indent .. "  " .. property .. ":", safeGet(root, property))
        end
    elseif root:IsA("BasePart") then
        log(indent .. "  Size:", safeGet(root, "Size"))
        log(indent .. "  Transparency:", safeGet(root, "Transparency"))
        log(indent .. "  Massless:", safeGet(root, "Massless"))
    end

    for _, child in ipairs(root:GetChildren()) do
        dumpTree(child, depth + 1)
    end
end

local function dumpCharacterAttachments(character)
    log("========== CHARACTER ATTACHMENTS ==========")
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Attachment") then
            local parent = descendant.Parent
            log(
                "Character Attachment:",
                descendant.Name,
                "| Parent:",
                parent and parent:GetFullName() or "nil",
                "| Position:",
                safeGet(descendant, "Position")
            )
        end
    end
end

log("Starting asset inspection:", ASSET_ID)

local character = LocalPlayer and LocalPlayer.Character
if character then
    dumpCharacterAttachments(character)
else
    log("Character not found.")
end

local ok, roots = pcall(function()
    return game:GetObjects("rbxassetid://" .. ASSET_ID)
end)

if not ok then
    log("GetObjects FAILED:", roots)
    return
end

if type(roots) ~= "table" or #roots == 0 then
    log("GetObjects returned no roots.")
    return
end

log("========== ASSET TREE ==========")
for index, root in ipairs(roots) do
    log("ROOT", index)
    dumpTree(root, 0)

    local nodes = {root}
    for _, descendant in ipairs(root:GetDescendants()) do
        table.insert(nodes, descendant)
    end

    for _, node in ipairs(nodes) do
        if node:IsA("Accessory") then
            log("========== ACCESSORY DETAILS ==========")
            log("Name:", node.Name)
            log("AccessoryType:", safeGet(node, "AccessoryType"))
            log("IsLayered:", safeGet(node, "IsLayered"))
            local handle = node:FindFirstChild("Handle")
            log("Handle:", handle and handle:GetFullName() or "MISSING")
            if handle then
                for _, child in ipairs(handle:GetChildren()) do
                    if child:IsA("Attachment") then
                        log("Handle Attachment:", child.Name)
                    elseif child:IsA("WrapLayer") then
                        log("Handle has WrapLayer")
                    end
                end
            end
        end
    end
end

log("========== END ==========")
log("Send the complete output, starting from 'Starting asset inspection'.")
