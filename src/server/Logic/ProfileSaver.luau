--!strict
-- ProfileSaver: decides what gets written to the progression store and tracks whether a
-- player's in-memory profile still has unsaved changes. Pure logic: the store's atomic
-- update function, the retry wait and the retry count are injected, so the tests drive it
-- with a fake store.
--
-- Guarantees:
--   * A save only reports success when the store accepted a write that includes this
--     session's changes.
--   * If someone else wrote the key since we last read it (another server, a slow leave
--     save), our write is rebased inside the atomic update: their data is the new base and
--     only this session's deltas are applied on top. Nothing is silently dropped.
--   * A profile stays dirty until a write that contained its latest revision succeeds.
--   * One write per key at a time; a save requested while one is in flight is run right after.
--   * Keys that were never tracked (failed loads) are never written.
--   * Every write is stamped with a writeId. If a write reaches the store but the call
--     reports an error, the retry recognises its own stamp and does not apply the session's
--     changes a second time (no double rewards).
--   * Pack on/off choices are rebased as changes too, so a pack another session disabled is
--     not switched back on unless this session touched it.

local ProfileSaver = {}
ProfileSaver.__index = ProfileSaver

local NUMERIC_FIELDS = { "points", "matchesCompleted", "awardsEarned" }

export type Options = {
	update: (key: string, transform: (old: any) -> any) -> any, -- atomic; may error
	wait: ((seconds: number) -> ())?,
	retries: number?,
	sessionId: string?, -- unique per server; generated if omitted
}

local function copyProfile(p: any): any
	local out = table.clone(p)
	out.unlockedPacks = table.clone(p.unlockedPacks or {})
	out.enabledPacks = table.clone(p.enabledPacks or {})
	return out
end

-- What to write, given what is in the store now (`old`), what the store held when this
-- session last read or wrote it (`base`) and the session's current profile.
-- Returns (dataToWrite, wasRebased).
function ProfileSaver.resolve(old: any, base: any, current: any): (any, boolean)
	local out = copyProfile(current)
	local oldCount = if type(old) == "table" and type(old.saveCount) == "number" then old.saveCount else 0
	local baseCount = if type(base.saveCount) == "number" then base.saveCount else 0
	local rebased = false
	if oldCount > baseCount then
		-- The store moved on without us: keep their progress, add only what we changed.
		rebased = true
		for _, field in NUMERIC_FIELDS do
			local theirs = if type(old[field]) == "number" then old[field] else 0
			local delta = (current[field] or 0) - (base[field] or 0)
			out[field] = math.max(0, theirs + delta)
		end
		if type(old.unlockedPacks) == "table" then
			for packId, owned in old.unlockedPacks do
				if owned then
					out.unlockedPacks[packId] = true
				end
			end
		end
		-- Enabled packs: start from theirs, then apply only what this session changed.
		local enabled = if type(old.enabledPacks) == "table" then table.clone(old.enabledPacks) else {}
		local baseEnabled = base.enabledPacks or {}
		local seen = {}
		for packId in current.enabledPacks or {} do
			seen[packId] = true
		end
		for packId in baseEnabled do
			seen[packId] = true
		end
		for packId in seen do
			local now = (current.enabledPacks or {})[packId] == true
			if now ~= (baseEnabled[packId] == true) then
				enabled[packId] = now or nil
			end
		end
		out.enabledPacks = enabled
	end
	out.saveCount = math.max(oldCount, baseCount) + 1
	return out, rebased
end

function ProfileSaver.new(opts: Options)
	local self = setmetatable({}, ProfileSaver)
	self.update = opts.update
	self.wait = opts.wait or function() end
	self.retries = opts.retries or 3
	self.sessionId = opts.sessionId or tostring(os.clock()) .. "-" .. tostring(math.random(1, 1e9))
	self.writeCounter = 0
	self.states = {} :: { [string]: any }
	return self
end

-- Start tracking a successfully loaded profile. `profile` is the live in-memory table.
function ProfileSaver.track(self, key: string, profile: any)
	self.states[key] = {
		base = copyProfile(profile),
		revision = 0,
		savedRevision = 0,
		saving = false,
		queued = false,
	}
end

function ProfileSaver.untrack(self, key: string)
	self.states[key] = nil
end

function ProfileSaver.isTracked(self, key: string): boolean
	return self.states[key] ~= nil
end

function ProfileSaver.markDirty(self, key: string)
	local st = self.states[key]
	if st then
		st.revision += 1
	end
end

function ProfileSaver.isDirty(self, key: string): boolean
	local st = self.states[key]
	return st ~= nil and st.revision ~= st.savedRevision
end

function ProfileSaver.isSaving(self, key: string): boolean
	local st = self.states[key]
	return st ~= nil and st.saving
end

-- Saves `profile` if it has unsaved changes. Returns (ok, status):
--   true,  "saved"       written as-is
--   true,  "merged"      written after rebasing onto newer stored data (profile updated)
--   true,  "clean"       nothing to save
--   false, "in progress" another save for this key is running; this one runs right after
--   false, "untracked"   profile was never loaded from the store, so it is never written
--   false, <error>       the store rejected every attempt; the profile stays dirty
function ProfileSaver.save(self, key: string, profile: any): (boolean, string)
	local st = self.states[key]
	if not st then
		return false, "untracked"
	end
	if st.saving then
		st.queued = true
		return false, "in progress"
	end
	if st.revision == st.savedRevision then
		return true, "clean"
	end
	st.saving = true
	local ok, status = false, "not attempted"
	repeat
		st.queued = false
		local revisionAtSnapshot = st.revision
		local snapshot = copyProfile(profile)
		local rebased = false
		local written: any = nil
		local lastErr: any = nil
		ok = false
		self.writeCounter += 1
		local writeId = self.sessionId .. ":" .. self.writeCounter
		for attempt = 1, self.retries do
			local success, result = pcall(self.update, key, function(old)
				local base = st.base
				local pending = st.pending
				if pending and type(old) == "table" and old.writeId == pending.id then
					-- An earlier attempt of ours did land even though the call failed: build
					-- on it instead of adding this session's changes again.
					base = pending.data
				end
				local data, wasRebased = ProfileSaver.resolve(old, base, snapshot)
				data.writeId = writeId
				rebased = wasRebased
				st.pending = { id = writeId, data = data }
				return data
			end)
			if success and type(result) == "table" then
				written = result
				ok = true
				break
			end
			lastErr = if success then "store returned no data" else result
			if attempt < self.retries then
				self.wait(attempt * 1.5)
			end
		end
		if ok then
			-- Fold what was actually written back into the live profile, keeping any changes
			-- made while the write was in flight.
			for _, field in NUMERIC_FIELDS do
				profile[field] = written[field] + ((profile[field] or 0) - (snapshot[field] or 0))
			end
			for packId, owned in written.unlockedPacks or {} do
				if owned then
					profile.unlockedPacks[packId] = true
				end
			end
			-- Pack toggles: adopt the stored value unless this session changed that pack while
			-- the write was in flight (otherwise the next rebase would read our stale local
			-- value as a fresh change and undo another session's toggle).
			local packIds = {}
			for packId in written.enabledPacks or {} do
				packIds[packId] = true
			end
			for packId in snapshot.enabledPacks or {} do
				packIds[packId] = true
			end
			for packId in packIds do
				local unchangedInFlight = (profile.enabledPacks[packId] == true) == ((snapshot.enabledPacks or {})[packId] == true)
				if unchangedInFlight then
					profile.enabledPacks[packId] = if (written.enabledPacks or {})[packId] == true then true else nil
				end
			end
			profile.saveCount = written.saveCount
			st.base = copyProfile(written)
			st.pending = nil
			st.savedRevision = revisionAtSnapshot
			status = if rebased then "merged" else "saved"
		else
			status = tostring(lastErr)
		end
	until not ok or st.revision == st.savedRevision
	st.saving = false
	st.queued = false
	return ok, status
end

return ProfileSaver
