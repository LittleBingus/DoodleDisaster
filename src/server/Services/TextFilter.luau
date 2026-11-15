--!strict
-- TextFilter: wraps Roblox text filtering for guesses that every player will see.
-- On any failure the original text is NEVER returned; callers get nil and use a placeholder.

local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local TextFilter = {}

-- Studio never censors text, so the censored-guess path can't be reached there. A Studio
-- test may pass { simulateFilter = true } as test args: the word "censorme" is then replaced
-- by '#' the way the real filter would. Unreachable on live servers (IsStudio check).
local simulate = false
if RunService:IsStudio() then
	local ok, args = pcall(function()
		return game:GetService("StudioTestService"):GetTestArgs()
	end)
	simulate = ok and type(args) == "table" and args.simulateFilter == true
end

-- Filters text written by `fromUserId` for display to everyone in the server
-- (broadcast context, like a sign or a shared reveal screen).
function TextFilter.forBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" and result ~= "" then
		if simulate then
			result = result:gsub("censorme", "########")
		end
		return result
	end
	if not ok then
		warn("[TextFilter] filtering failed: " .. tostring(result))
	end
	return nil
end

return TextFilter
