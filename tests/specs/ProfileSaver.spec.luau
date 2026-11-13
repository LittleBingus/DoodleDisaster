local D = require(script.Parent.Parent.Deps)
local ProfileSaver = D.ProfileSaver

local function profile(points: number?, saveCount: number?)
	return {
		version = 1,
		saveCount = saveCount or 0,
		points = points or 0,
		matchesCompleted = 0,
		awardsEarned = 0,
		unlockedPacks = { StarterChaos = true },
		enabledPacks = {},
	}
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- In-memory stand-in for a DataStore with UpdateAsync semantics.
local function fakeStore()
	local store = { data = {}, calls = 0, failNext = 0, beforeTransform = nil :: any }
	function store.update(key: string, transform: (any) -> any)
		store.calls += 1
		if store.failNext > 0 then
			store.failNext -= 1
			error("simulated DataStore outage")
		end
		if store.beforeTransform then
			local hook = store.beforeTransform
			store.beforeTransform = nil
			hook()
		end
		local result = transform(deepCopy(store.data[key]))
		if result == nil then
			return nil
		end
		store.data[key] = deepCopy(result)
		return deepCopy(result)
	end
	return store
end

return function(t)
	t.test("successful save writes, bumps saveCount and clears dirty", function()
		local store = fakeStore()
		local saver = ProfileSaver.new({ update = store.update })
		local p = profile()
		saver:track("k", p)
		t.falsy(saver:isDirty("k"))
		p.points += 20
		saver:markDirty("k")
		t.truthy(saver:isDirty("k"))
		local ok, status = saver:save("k", p)
		t.truthy(ok)
		t.eq(status, "saved")
		t.eq(store.data.k.points, 20)
		t.eq(store.data.k.saveCount, 1)
		t.eq(p.saveCount, 1)
		t.falsy(saver:isDirty("k"))
	end)

	t.test("duplicate save of a clean profile does not touch the store", function()
		local store = fakeStore()
		local saver = ProfileSaver.new({ update = store.update })
		local p = profile()
		saver:track("k", p)
		p.points = 5
		saver:markDirty("k")
		saver:save("k", p)
		local callsAfterFirst = store.calls
		local ok, status = saver:save("k", p)
		t.truthy(ok)
		t.eq(status, "clean")
		t.eq(store.calls, callsAfterFirst)
		t.eq(store.data.k.saveCount, 1)
	end)

	t.test("failed save is reported as failed and keeps the data dirty", function()
		local store = fakeStore()
		local saver = ProfileSaver.new({ update = store.update, retries = 3 })
		local p = profile()
		saver:track("k", p)
		p.points = 20
		saver:markDirty("k")
		store.failNext = 3
		local ok, status = saver:save("k", p)
		t.falsy(ok, "must not report success")
		t.truthy(string.find(status, "outage", 1, true), "returns the store error")
		t.eq(store.calls, 3, "retried")
		t.truthy(saver:isDirty("k"), "still dirty")
		t.eq(store.data.k, nil, "nothing written")
		t.eq(p.points, 20, "in-memory progress kept")
		-- the next attempt succeeds and nothing was lost
		local ok2 = saver:save("k", p)
		t.truthy(ok2)
		t.eq(store.data.k.points, 20)
		t.falsy(saver:isDirty("k"))
	end)

	t.test("a transient failure is retried within one save", function()
		local store = fakeStore()
		local saver = ProfileSaver.new({ update = store.update, retries = 3 })
		local p = profile()
		saver:track("k", p)
		p.points = 7
		saver:markDirty("k")
		store.failNext = 2
		local ok, status = saver:save("k", p)
		t.truthy(ok)
		t.eq(status, "saved")
		t.eq(store.data.k.points, 7)
	end)

	t.test("stale write is rebased onto newer stored data, not dropped and not clobbering", function()
		local store = fakeStore()
		store.data.k = profile(100, 5)
		local saver = ProfileSaver.new({ update = store.update })
		local p = profile(100, 5) -- this server loaded saveCount 5
		saver:track("k", p)
		-- another server saves afterwards: +40 points, a pack, saveCount 6
		store.data.k.points = 140
		store.data.k.matchesCompleted = 2
		store.data.k.unlockedPacks.Brainrot = true
		store.data.k.saveCount = 6
		-- this session earns 25 and completes a match
		p.points += 25
		p.matchesCompleted += 1
		saver:markDirty("k")
		local ok, status = saver:save("k", p)
		t.truthy(ok)
		t.eq(status, "merged", "a rebased write is reported as such")
		t.eq(store.data.k.points, 165, "their 140 plus our 25")
		t.eq(store.data.k.matchesCompleted, 3)
		t.eq(store.data.k.unlockedPacks.Brainrot, true, "their unlock survives")
		t.eq(store.data.k.saveCount, 7)
		t.eq(p.points, 165, "live profile adopts the merged value")
		t.eq(p.unlockedPacks.Brainrot, true)
		t.falsy(saver:isDirty("k"))
	end)

	t.test("a concurrent write landing mid-save is still merged atomically", function()
		local store = fakeStore()
		store.data.k = profile(50, 2)
		local saver = ProfileSaver.new({ update = store.update })
		local p = profile(50, 2)
		saver:track("k", p)
		p.points -= 30 -- spent on something
		saver:markDirty("k")
		store.beforeTransform = function()
			store.data.k.points = 70 -- the other server added 20 just before our transform ran
			store.data.k.saveCount = 3
		end
		local ok, status = saver:save("k", p)
		t.truthy(ok)
		t.eq(status, "merged")
		t.eq(store.data.k.points, 40, "70 minus the 30 we spent")
		t.eq(store.data.k.saveCount, 4)
	end)

	t.test("rebased points never go negative", function()
		local a, rebased = ProfileSaver.resolve(profile(10, 9), profile(100, 5), profile(40, 5))
		t.truthy(rebased)
		t.eq(a.points, 0)
		t.eq(a.saveCount, 10)
	end)

	t.test("overlapping save is refused while one is in flight, then runs with the newer data", function()
		local store = fakeStore()
		local saver = ProfileSaver.new({ update = store.update })
		local p = profile()
		saver:track("k", p)
		p.points = 20
		saver:markDirty("k")
		local nestedOk, nestedStatus
		store.beforeTransform = function()
			-- while the first write is in flight the player earns more and another save is requested
			p.points += 5
			saver:markDirty("k")
			nestedOk, nestedStatus = saver:save("k", p)
		end
		local ok = saver:save("k", p)
		t.falsy(nestedOk, "overlapping save must not claim success")
		t.eq(nestedStatus, "in progress")
		t.truthy(ok)
		t.eq(store.calls, 2, "one write for the first snapshot, one follow-up for the change made in flight")
		t.eq(store.data.k.points, 25)
		t.eq(p.points, 25)
		t.eq(store.data.k.saveCount, 2)
		t.falsy(saver:isDirty("k"))
		t.falsy(saver:isSaving("k"))
	end)

	t.test("a profile that failed to load is never written", function()
		local store = fakeStore()
		store.data.k = profile(500, 9)
		local saver = ProfileSaver.new({ update = store.update })
		local temp = profile() -- defaults handed out after a failed load; never tracked
		temp.points = 20
		saver:markDirty("k")
		local ok, status = saver:save("k", temp)
		t.falsy(ok)
		t.eq(status, "untracked")
		t.eq(store.calls, 0)
		t.eq(store.data.k.points, 500, "existing progress untouched")
	end)

	t.test("first ever save for a new player", function()
		local data, rebased = ProfileSaver.resolve(nil, profile(), profile(20))
		t.falsy(rebased)
		t.eq(data.points, 20)
		t.eq(data.saveCount, 1)
	end)
end
