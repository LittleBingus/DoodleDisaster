--!strict
-- PromptSelector: weighted prompt picking. Pure logic (rng is injected).
--
-- select(prompts, weights, count, rng, recentIds?) picks `count` distinct prompts.
--   * difficulty is rolled per prompt using weights (e.g. Easy 40 / Medium 40 / Hard 20)
--   * prompts never repeat within one selection
--   * prompts in recentIds (previous matches) are avoided while alternatives exist
--   * if a difficulty bucket runs dry its weight is redistributed to the others

local PromptSelector = {}

local DIFFICULTIES = { "Easy", "Medium", "Hard" }

type Prompt = { Id: string, Difficulty: string, Enabled: boolean, [string]: any }

local function rollDifficulty(weights: { [string]: number }, buckets: { [string]: { Prompt } }, rng: () -> number): string?
	local total = 0
	for _, d in DIFFICULTIES do
		if #buckets[d] > 0 then
			total += math.max(0, weights[d] or 0)
		end
	end
	if total <= 0 then
		-- every weighted bucket is empty: fall back to any non-empty bucket
		for _, d in DIFFICULTIES do
			if #buckets[d] > 0 then
				return d
			end
		end
		return nil
	end
	local roll = rng() * total
	local acc = 0
	local last: string? = nil
	for _, d in DIFFICULTIES do
		if #buckets[d] > 0 then
			local w = math.max(0, weights[d] or 0)
			if w > 0 then
				acc += w
				last = d
				if roll < acc then
					return d
				end
			end
		end
	end
	return last
end

local function takeRandom(list: { Prompt }, rng: () -> number): Prompt
	local i = math.clamp(math.floor(rng() * #list) + 1, 1, #list)
	local p = list[i]
	list[i] = list[#list]
	list[#list] = nil
	return p
end

function PromptSelector.select(
	prompts: { Prompt },
	weights: { [string]: number },
	count: number,
	rng: () -> number,
	recentIds: { [string]: boolean }?
): { Prompt }
	local recent = recentIds or {}
	local fresh: { [string]: { Prompt } } = { Easy = {}, Medium = {}, Hard = {} }
	local stale: { [string]: { Prompt } } = { Easy = {}, Medium = {}, Hard = {} }
	local seen: { [string]: boolean } = {}
	for _, p in prompts do
		if p.Enabled and fresh[p.Difficulty] and not seen[p.Id] then
			seen[p.Id] = true
			if recent[p.Id] then
				table.insert(stale[p.Difficulty], p)
			else
				table.insert(fresh[p.Difficulty], p)
			end
		end
	end

	local picked: { Prompt } = {}
	for _ = 1, count do
		local d = rollDifficulty(weights, fresh, rng)
		local bucket = if d then fresh[d] else nil
		if not bucket then
			-- out of fresh prompts: allow repeats from earlier matches (never within this one)
			d = rollDifficulty(weights, stale, rng)
			bucket = if d then stale[d] else nil
		end
		if not bucket then
			break -- library exhausted
		end
		table.insert(picked, takeRandom(bucket, rng))
	end
	return picked
end

return PromptSelector
