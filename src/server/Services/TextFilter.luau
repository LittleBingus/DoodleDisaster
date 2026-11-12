--!strict
-- TextFilter: wraps Roblox text filtering for guesses that every player will see.
-- On any failure the original text is NEVER returned; callers get nil and use a placeholder.

local TextService = game:GetService("TextService")

local TextFilter = {}

-- Filters text written by `fromUserId` for display to everyone in the server
-- (broadcast context, like a sign or a shared reveal screen).
function TextFilter.forBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	if not ok then
		warn("[TextFilter] filtering failed: " .. tostring(result))
	end
	return nil
end

return TextFilter
