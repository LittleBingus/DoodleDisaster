--!strict
-- Rotation: deterministic sketchbook rotation. Pure logic, no Roblox APIs.
--
-- Players are indexed 1..n in match order. Sketchbook b is started by player b.
-- At step s (0-based) player p works on sketchbook ((p - 1 - s) mod n) + 1, i.e.
-- sketchbooks pass one seat to the right after every step. Over n steps every
-- player touches every sketchbook exactly once and every sketchbook gets n entries.
--
-- Entry kinds alternate Draw, Guess, Draw, ... starting with the owner drawing the
-- original prompt. So the final entry (step n-1) is a Draw for odd n, a Guess for even n.

local Rotation = {}

function Rotation.bookForPlayer(playerIndex: number, step: number, n: number): number
	return ((playerIndex - 1 - step) % n) + 1
end

function Rotation.playerForBook(bookIndex: number, step: number, n: number): number
	return ((bookIndex - 1 + step) % n) + 1
end

function Rotation.kindForStep(step: number): string
	return if step % 2 == 0 then "Draw" else "Guess"
end

function Rotation.totalSteps(n: number): number
	return n
end

-- Full schedule: schedule[step + 1][playerIndex] = bookIndex
function Rotation.buildSchedule(n: number): { { number } }
	assert(n >= 1, "need at least one player")
	local schedule = {}
	for step = 0, n - 1 do
		local row = {}
		for p = 1, n do
			row[p] = Rotation.bookForPlayer(p, step, n)
		end
		schedule[step + 1] = row
	end
	return schedule
end

-- Returns true, nil if the schedule satisfies every rotation rule; otherwise false, reason.
function Rotation.validateSchedule(schedule: { { number } }, n: number): (boolean, string?)
	if #schedule ~= n then
		return false, "expected " .. n .. " steps, got " .. #schedule
	end
	local seen: { [number]: { [number]: boolean } } = {}
	for p = 1, n do
		seen[p] = {}
	end
	for step, row in schedule do
		local booksThisStep: { [number]: boolean } = {}
		for p = 1, n do
			local b = row[p]
			if type(b) ~= "number" or b < 1 or b > n then
				return false, "invalid book at step " .. step
			end
			if booksThisStep[b] then
				return false, "book " .. b .. " assigned twice at step " .. step
			end
			booksThisStep[b] = true
			if seen[p][b] then
				return false, "player " .. p .. " received book " .. b .. " twice"
			end
			seen[p][b] = true
		end
		if step == 1 then
			for p = 1, n do
				if row[p] ~= p then
					return false, "player " .. p .. " does not start their own book"
				end
			end
		end
	end
	for p = 1, n do
		for b = 1, n do
			if not seen[p][b] then
				return false, "player " .. p .. " never received book " .. b
			end
		end
	end
	return true, nil
end

return Rotation
