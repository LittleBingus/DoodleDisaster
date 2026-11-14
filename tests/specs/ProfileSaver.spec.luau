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

	t.test("a write that lands but reports failure is not applied twice on retry", function()
		local store = fakeStore()
		store.data.k = profile(100, 5)
		local saver = ProfileSaver.new({ update = store.update, retries = 3 })
		local p = profile(100, 5)
		saver:track("k", p)
		p.points += 20 -- match reward
		p.matchesCompleted += 1
		saver:markDirty("k")
		-- first call: the transform runs and the data is stored, then the call errors (timeout)
		local realUpdate = store.update
		local first = true
		saver.update = function(key, transform)
			if first then
				first = false
				realUpdate(key, transform)
				error("simulated timeout after commit")
			end
			return realUpdate(key, transform)
		end
		local ok = saver:save("k", p)
		t.truthy(ok)
		t.eq(store.data.k.points, 120, "reward counted exactly once")
		t.eq(store.data.k.matchesCompleted, 1)
		t.eq(p.points, 120)
		t.falsy(saver:isDirty("k"))
	end)

	t.test("a landed-but-failed write is recognised even by a later save call", function()
		local store = fakeStore()
		store.data.k = profile(100, 5)
		local saver = ProfileSaver.new({ update = store.update, retries = 1 })
		local p = profile(100, 5)
		saver:track("k", p)
		p.points += 20
		saver:markDirty("k")
		local realUpdate = store.update
		saver.update = function(key, transform)
			realUpdate(key, transform)
			error("simulated timeout after commit")
		end
		t.falsy(saver:save("k", p), "reported as failed")
		t.truthy(saver:isDirty("k"))
		t.eq(store.data.k.points, 120, "but it did land")
		saver.update = realUpdate
		p.points += 5 -- more progress before the next save
		saver:markDirty("k")
		t.truthy(saver:save("k", p))
		t.eq(store.data.k.points, 125, "20 once, plus the new 5")
		t.eq(p.points, 125)
	end)

	t.test("two sessions granting rewards both keep theirs, each exactly once", function()
		local store = fakeStore()
		store.data.k = profile(0, 1)
		local a = ProfileSaver.new({ update = store.update, sessionId = "A" })
		local b = ProfileSaver.new({ update = store.update, sessionId = "B" })
		local pa, pb = profile(0, 1), profile(0, 1)
		a:track("k", pa)
		b:track("k", pb)
		pa.points += 20
		a:markDirty("k")
		pb.points += 25
		b:markDirty("k")
		t.truthy(a:save("k", pa))
		t.truthy(b:save("k", pb))
		t.eq(store.data.k.points, 45)
		-- saving again from either side changes nothing
		a:markDirty("k")
		t.truthy(a:save("k", pa))
		t.eq(store.data.k.points, 45, "A re-saving after B must not re-add A's 20")
		t.eq(pa.points, 45)
		b:markDirty("k")
		t.truthy(b:save("k", pb))
		t.eq(store.data.k.points, 45)
	end)

	t.test("rebasing does not switch a pack back on that another session disabled", function()
		local base = profile(0, 3)
		base.unlockedPacks.Brainrot = true
		base.unlockedPacks.EverydayDisasters = true
		base.enabledPacks = { Brainrot = true, EverydayDisasters = true }
		local theirs = deepCopy(base)
		theirs.saveCount = 4
		theirs.enabledPacks.Brainrot = nil -- other session turned Brainrot off
		local ours = deepCopy(base)
		ours.enabledPacks.EverydayDisasters = nil -- we turned Everyday Disasters off
		local out, rebased = ProfileSaver.resolve(theirs, base, ours)
		t.truthy(rebased)
		t.eq(out.enabledPacks.Brainrot, nil, "their change is kept")
		t.eq(out.enabledPacks.EverydayDisasters, nil, "our change is applied")
		t.eq(out.unlockedPacks.Brainrot, true, "ownership is never lost")
	end)

	t.test("after a merged save the live profile matches the store, so the next save cannot undo the other session's pack toggle", function()
		local store = fakeStore()
		local start = profile(100, 3)
		start.unlockedPacks.Brainrot = true
		start.enabledPacks = { Brainrot = true }
		store.data.k = deepCopy(start)
		local saver = ProfileSaver.new({ update = store.update, sessionId = "A" })
		local p = deepCopy(start)
		saver:track("k", p)
		store.data.k.enabledPacks = {}
		store.data.k.saveCount = 4
		p.points += 20
		saver:markDirty("k")
		t.eq(select(2, saver:save("k", p)), "merged")
		t.eq(store.data.k.enabledPacks.Brainrot, nil)
		t.eq(p.enabledPacks.Brainrot, nil, "live profile adopted the stored toggle")
		store.data.k.saveCount += 1
		store.data.k.points += 1
		p.points += 5
		saver:markDirty("k")
		t.truthy(saver:save("k", p))
		t.eq(store.data.k.enabledPacks.Brainrot, nil, "Brainrot is still off")
		t.eq(store.data.k.points, 126)
	end)

	t.test("a toggle made while a write is in flight is kept", function()
		local store = fakeStore()
		local saver = ProfileSaver.new({ update = store.update })
		local p = profile(0, 0)
		p.unlockedPacks.Brainrot = true
		saver:track("k", p)
		p.points = 5
		saver:markDirty("k")
		store.beforeTransform = function()
			p.enabledPacks.Brainrot = true
			saver:markDirty("k")
		end
		t.truthy(saver:save("k", p))
		t.eq(p.enabledPacks.Brainrot, true)
		t.eq(store.data.k.enabledPacks.Brainrot, true, "follow-up write stored it")
	end)

	t.test("first ever save for a new player", function()
		local data, rebased = ProfileSaver.resolve(nil, profile(), profile(20))
		t.falsy(rebased)
		t.eq(data.points, 20)
		t.eq(data.saveCount, 1)
	end)
end
