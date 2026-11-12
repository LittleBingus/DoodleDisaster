--!strict
-- CustomPromptService: groundwork for future paid custom prompts. DISABLED.
--
-- Nothing here is reachable from clients yet: no RemoteEvent is wired up, no
-- MarketplaceService.ProcessReceipt callback is assigned, and no product ID exists.
-- Turning it on later requires, in order:
--   1. Create a Developer Product on the Creator Dashboard and put its real ID in
--      GameConfig.CustomPrompts.DeveloperProductId (never invent one).
--   2. Assign MarketplaceService.ProcessReceipt to CustomPromptService.processReceipt
--      (only one ProcessReceipt callback may exist per game).
--   3. Add a "SubmitCustomPrompt" remote that calls CustomPromptService.submit.
--   4. Persist granted credits and processed receipt IDs in DataStore (idempotency).
--
-- Every custom prompt is sanitised, length-checked and passed through Roblox text
-- filtering before it is stored, and must be approved before it can enter a match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local TextRules = require(Shared.TextRules)
local TextFilter = require(script.Parent.TextFilter)

local CustomPromptService = {}

export type CustomPrompt = {
	Id: string,
	Phrase: string,
	AuthorUserId: number,
	Status: string, -- "Pending" | "Approved" | "Rejected"
	Difficulty: string,
}

local queue: { CustomPrompt } = {}
local credits: { [number]: number } = {} -- userId -> purchased submissions (session only until step 4)
local processedReceipts: { [string]: boolean } = {}
local nextId = 0

function CustomPromptService.isEnabled(): boolean
	return GameConfig.CustomPrompts.Enabled == true and GameConfig.CustomPrompts.DeveloperProductId ~= nil
end

-- Validates and filters a custom prompt. Returns the queued prompt or nil + reason.
function CustomPromptService.submit(player: Player, raw: any): (CustomPrompt?, string?)
	if not CustomPromptService.isEnabled() then
		return nil, "Custom prompts aren't available yet."
	end
	if (credits[player.UserId] or 0) <= 0 then
		return nil, "No custom prompt credits."
	end
	local text, err = TextRules.sanitize(raw, GameConfig.CustomPrompts.MaxLength)
	if not text then
		return nil, err
	end
	if utf8.len(text :: string) :: number < GameConfig.CustomPrompts.MinLength then
		return nil, "Prompt is too short."
	end
	local filtered = TextFilter.forBroadcast(text :: string, player.UserId)
	if not filtered or filtered ~= text then
		-- Anything the filter changed is rejected outright rather than shown with hashes.
		return nil, "That prompt can't be used."
	end
	credits[player.UserId] -= 1
	nextId += 1
	local prompt: CustomPrompt = {
		Id = "Custom_" .. nextId,
		Phrase = filtered,
		AuthorUserId = player.UserId,
		Status = "Pending",
		Difficulty = "Medium",
	}
	table.insert(queue, prompt)
	return prompt, nil
end

-- Moderation hook (manual review or automated rules). Only Approved prompts may be used.
function CustomPromptService.setStatus(promptId: string, approved: boolean)
	for _, p in queue do
		if p.Id == promptId then
			p.Status = if approved then "Approved" else "Rejected"
		end
	end
end

function CustomPromptService.approvedPrompts(): { CustomPrompt }
	local out = {}
	for _, p in queue do
		if p.Status == "Approved" then
			table.insert(out, p)
		end
	end
	return out
end

-- Future ProcessReceipt handler. Grants a credit only for the configured product and only
-- once per receipt. Not assigned to MarketplaceService anywhere yet.
function CustomPromptService.processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local productId = GameConfig.CustomPrompts.DeveloperProductId
	if not CustomPromptService.isEnabled() or receiptInfo.ProductId ~= productId then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if processedReceipts[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- TODO(step 4): persist credits + receipt id in DataStore before returning PurchaseGranted.
	credits[receiptInfo.PlayerId] = (credits[receiptInfo.PlayerId] or 0) + 1
	processedReceipts[receiptInfo.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return CustomPromptService
