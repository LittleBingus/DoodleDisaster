local D = require(script.Parent.Parent.Deps)
local ReportLog = D.ReportLog

local LIMITS = { PerMatch = 2, PerSession = 3 }
local function drawingBy(author: number)
	return { author = author, auto = false, blank = false }
end

return function(t)
	t.test("a valid report is accepted once and blocks that author for the reporter only", function()
		local log = ReportLog.new(LIMITS)
		t.truthy((log:submit(1, 5, "d000001", drawingBy(2))))
		t.truthy(log:isBlocked(1, 2))
		t.falsy(log:isBlocked(2, 1), "blocking is one-way")
		t.falsy(log:isBlocked(3, 2), "other viewers are unaffected")
		t.falsy(log:isBlocked(1, nil))
		local ok, reason = log:submit(1, 5, "d000001", drawingBy(2))
		t.falsy(ok)
		t.eq(reason, "already reported")
	end)

	t.test("unknown ids, own drawings and empty pages are rejected", function()
		local log = ReportLog.new(LIMITS)
		t.eq(select(2, log:submit(1, 5, "d000009", nil)), "unknown drawing")
		t.eq(select(2, log:submit(1, 5, 123, drawingBy(2))), "unknown drawing")
		t.eq(select(2, log:submit(1, 5, { "x" }, drawingBy(2))), "unknown drawing")
		t.eq(select(2, log:submit(1, 5, "d000001", drawingBy(1))), "own drawing")
		t.eq(select(2, log:submit(1, 5, "d000002", { author = 2, auto = true, blank = true })), "nothing to report")
		t.eq(select(2, log:submit(1, 5, "d000003", { author = 2, auto = false, blank = true })), "nothing to report")
		t.falsy(log:isBlocked(1, 2), "rejected reports change nothing")
		t.eq(log:reporterCount(2), 0)
	end)

	t.test("per-match and per-session caps stop report spam", function()
		local log = ReportLog.new(LIMITS)
		t.truthy((log:submit(1, 5, "a", drawingBy(2))))
		t.truthy((log:submit(1, 5, "b", drawingBy(3))))
		t.eq(select(2, log:submit(1, 5, "c", drawingBy(4))), "too many reports")
		t.truthy((log:submit(1, 6, "a", drawingBy(2))), "new match, same id string is a different drawing")
		t.eq(select(2, log:submit(1, 7, "a", drawingBy(2))), "too many reports")
		t.truthy((log:submit(9, 5, "c", drawingBy(4))), "other players have their own allowance")
	end)

	t.test("distinct reporters are counted per author", function()
		local log = ReportLog.new({ PerMatch = 5, PerSession = 5 })
		log:submit(1, 5, "a", drawingBy(2))
		log:submit(1, 5, "b", drawingBy(2))
		log:submit(3, 5, "a", drawingBy(2))
		t.eq(log:reporterCount(2), 2)
		t.eq(log:reporterCount(7), 0)
	end)
end
