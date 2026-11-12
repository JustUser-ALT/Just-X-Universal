-- JustXUniversal: Purple Void Sword hand-grip preview
-- Temporary visual test only. Run again to remove the preview.
-- Does not modify Skin Changer or save anything.

local ASSET_ID = 14447815815
local PREVIEW_NAME = "JX_SwordGripPreview"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player and player.Character
if not character then
    warn("[SwordGripPreview] Character not found.")
    return
end

local old = character:FindFirstChild(PREVIEW_NAME)
if old then
    old:Destroy()
    print("[SwordGripPreview] Preview removed.")
    return
end

local rightHand = character:FindFirstChild("RightHand")
local grip = rightHand and rightHand:FindFirstChild("RightGripAttachment")
if not rightHand or not grip then
    warn("[SwordGripPreview] RightHand or RightGripAttachment missing.")
    return
end

local ok, roots = pcall(function()
    return game:GetObjects("rbxassetid://" .. ASSET_ID)
end)
if not ok or type(roots) ~= "table" or not roots[1] then
    warn("[SwordGripPreview] Asset load failed:", roots)
    return
end

local source = roots[1]
local accessory = source:IsA("Accessory") and source or source:FindFirstChildWhichIsA("Accessory", true)
if not accessory then
    for _, root in ipairs(roots) do
        root:Destroy()
    end
    warn("[SwordGripPreview] Accessory object not found in asset.")
    return
end

local clone = accessory:Clone()
clone.Name = PREVIEW_NAME
local handle = clone:FindFirstChild("Handle")
local handleAttachment = handle and handle:FindFirstChild("BodyFrontAttachment")
if not handle or not handleAttachment then
    clone:Destroy()
    for _, root in ipairs(roots) do
        root:Destroy()
    end
    warn("[SwordGripPreview] Handle or BodyFrontAttachment missing.")
    return
end

for _, root in ipairs(roots) do
    root:Destroy()
end

local wrapLayer = handle:FindFirstChildWhichIsA("WrapLayer")
if wrapLayer then
    wrapLayer.Enabled = false
end

handle.Anchored = false
handle.CanCollide = false
handle.CanTouch = false
handle.CanQuery = false
handle.Massless = true
handle.CFrame = grip.WorldCFrame * handleAttachment.CFrame:Inverse()

clone.Parent = character

local weld = Instance.new("WeldConstraint")
weld.Name = "JX_SwordGripWeld"
weld.Part0 = rightHand
weld.Part1 = handle
weld.Parent = handle

print("[SwordGripPreview] Preview attached to RightHand.RightGripAttachment.")
print("[SwordGripPreview] Run this script again to remove it.")
