local D = require(script.Parent.Parent.Deps)
local Rewards, GameConfig, Phases, TextRules, RateLimiter = D.Rewards, D.GameConfig, D.Phases, D.TextRules, D.RateLimiter

return function(t)
	local cfg = GameConfig.Rewards

	t.test("participation and award rewards", function()
		local grants = Rewards.compute({
			{ userId = 1, stillPresent = true, activeSubmissions = 4, totalTasks = 4 },
			{ userId = 2, stillPresent = true, activeSubmissions = 2, totalTasks = 4 },
			{ userId = 3, stillPresent = false, activeSubmissions = 4, totalTasks = 4 },
			{ userId = 4, stillPresent = true, activeSubmissions = 1, totalTasks = 4 },
		}, { [1] = 2, [3] = 1 }, cfg)
		t.eq(grants[1].points, cfg.MatchCompletion + 2 * cfg.AwardBonus)
		t.eq(grants[1].awards, 2)
		t.eq(grants[2].points, cfg.MatchCompletion, "exactly at the ratio threshold")
		t.eq(grants[3], nil, "left before the end")
		t.eq(grants[4], nil, "mostly AFK")
		t.eq(cfg.MatchCompletion, 20)
		t.eq(cfg.AwardBonus, 5)
	end)

	t.test("full phase loop is allowed and returns to the lobby", function()
		local path = { "WaitingForPlayers", "Countdown", "StartingMatch", "Drawing", "CollectingSubmissions", "Guessing",
			"CollectingSubmissions", "Drawing", "CollectingSubmissions", "Reveal", "AwardVoting", "Results",
			"ReturningToLobby", "WaitingForPlayers" }
		for i = 1, #path - 1 do
			t.truthy(Phases.canTransition(path[i], path[i + 1]), path[i] .. " -> " .. path[i + 1])
		end
	end)

	t.test("illegal phase jumps are rejected", function()
		t.falsy(Phases.canTransition("WaitingForPlayers", "Reveal"))
		t.falsy(Phases.canTransition("Drawing", "Guessing"), "must collect submissions first")
		t.falsy(Phases.canTransition("Results", "Drawing"))
		t.falsy(Phases.canTransition("Countdown", "AwardVoting"))
		t.falsy(Phases.canTransition("Bogus", "Drawing"))
	end)

	t.test("every in-match phase can abort to the lobby", function()
		for phase in Phases.InMatch do
			if phase ~= "Results" then
				t.truthy(Phases.canTransition(phase, "ReturningToLobby"), phase)
			end
		end
	end)

	t.test("guess text sanitising", function()
		t.eq(TextRules.sanitize("  a   flying\n\tcow  ", 60), "a flying cow")
		t.eq((TextRules.sanitize("", 60)), nil)
		t.eq((TextRules.sanitize("   ", 60)), nil)
		t.eq((TextRules.sanitize(string.rep("a", 61), 60)), nil)
		t.eq(TextRules.sanitize(string.rep("a", 60), 60), string.rep("a", 60))
		t.eq((TextRules.sanitize(42, 60)), nil)
		t.eq((TextRules.sanitize("\255\254", 60)), nil, "invalid utf8")
	end)

	t.test("rate limiter allows bursts up to the limit then recovers", function()
		local now = 0
		local limiter = RateLimiter.new(3, 5, function()
			return now
		end)
		t.truthy(limiter:allow("p"))
		t.truthy(limiter:allow("p"))
		t.truthy(limiter:allow("p"))
		t.falsy(limiter:allow("p"))
		t.truthy(limiter:allow("q"), "per key")
		now = 6
		t.truthy(limiter:allow("p"))
	end)
end
