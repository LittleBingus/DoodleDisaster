--!strict
-- GuessFallback: what to do when Roblox's text filter leaves nothing usable of a guess.
-- Pure logic (rng injected).
--
-- The filter replaces blocked text with '#'. A guess that comes back fully or mostly
-- censored would become the next player's drawing prompt ("####"), which breaks the chain.
-- Instead the server swaps in a developer-written phrase. The original text is never used,
-- stored or reconstructed here: the only inputs are the already-filtered result and whether
-- the filter changed anything.

local GuessFallback = {}

-- Letters, digits and any non-ASCII byte (so non-English guesses count as text).
local function wordChars(text: string): number
	local _, count = text:gsub("[%w\128-\255]", "")
	return count
end

-- `filtered` is the filter's output (nil when filtering failed). `original` is only compared
-- for equality, to tell a '#' the player typed ("#1 dad") from one the filter inserted.
function GuessFallback.isUsable(original: string, filtered: string?): boolean
	if type(filtered) ~= "string" then
		return false
	end
	if wordChars(filtered) == 0 then
		return false
	end
	if filtered == original then
		return true -- nothing was censored
	end
	local _, hashes = filtered:gsub("#", "")
	if hashes == 0 then
		return true -- changed, but not censored (e.g. whitespace)
	end
	-- Partly censored: keep it only if real words clearly survive.
	local words = wordChars(filtered)
	return words >= 3 and words > hashes
end

-- Picks a phrase that has not been used yet this match (falls back to any phrase once all
-- have been used). `used` is updated in place.
function GuessFallback.pick(phrases: { string }, used: { [string]: boolean }, rng: () -> number): string
	assert(#phrases > 0, "no fallback phrases configured")
	local fresh = {}
	for _, phrase in phrases do
		if not used[phrase] then
			table.insert(fresh, phrase)
		end
	end
	local pool = if #fresh > 0 then fresh else phrases
	local choice = pool[math.clamp(math.floor(rng() * #pool) + 1, 1, #pool)]
	used[choice] = true
	return choice
end

return GuessFallback
