--!strict
-- PlayerDataManager: DataStore-backed persistence for Doodle Points and packs.
--
-- Safety rules:
--   * If loading fails after retries, the player plays with a temporary profile that is
--     NEVER saved, so existing data can't be overwritten with defaults.
--   * Saves use UpdateAsync and refuse to write if the stored version is newer.
--   * Clients can only *request* actions (unlock/toggle a pack); all values are computed here.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local PromptPacks = require(Shared.PromptPacks)
local Net = require(script.Parent.Net)

local PlayerDataManager = {}

export type Profile = {
	version: number,
	saveCount: number,
	points: number,
	matchesCompleted: number,
	awardsEarned: number,
	unlockedPacks: { [string]: boolean },
	enabledPacks: { [string]: boolean },
}

local SCHEMA_VERSION = 1
local MAX_RETRIES = 3

-- The only place a progression store is chosen: Studio sessions get their own store.
local STORE_NAME = if RunService:IsStudio() then GameConfig.StudioDataStoreName else GameConfig.DataStoreName
PlayerDataManager.StoreName = STORE_NAME

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore unavailable: " .. tostring(result))
	end
end

local profiles: { [Player]: Profile } = {}
local loadFailed: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local loadedSignal = Instance.new("BindableEvent")
PlayerDataManager.ProfileLoaded = loadedSignal.Event

local function defaultProfile(): Profile
	return {
		version = SCHEMA_VERSION,
		saveCount = 0,
		points = 0,
		matchesCompleted = 0,
		awardsEarned = 0,
		unlockedPacks = { [PromptPacks.FreePackId] = true },
		enabledPacks = {},
	}
end

-- Fills missing fields of stored data without discarding anything that's there.
local function reconcile(data: any): Profile
	local profile = defaultProfile()
	if type(data) ~= "table" then
		return profile
	end
	for key, value in data do
		if profile[key] ~= nil and type(value) == type(profile[key]) then
			profile[key] = value
		end
	end
	profile.unlockedPacks[PromptPacks.FreePackId] = true
	return profile
end

local function withRetries<T>(fn: () -> T): (boolean, T | string)
	local lastErr: any = nil
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(attempt * 1.5)
	end
	return false, tostring(lastErr)
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

function PlayerDataManager.publicProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local packs = {}
	for _, pack in PromptPacks.Packs do
		table.insert(packs, {
			id = pack.Id,
			name = pack.DisplayName,
			description = pack.Description,
			free = pack.Free,
			cost = pack.Cost,
			milestone = pack.MilestoneMatches,
			unlocked = profile.unlockedPacks[pack.Id] == true,
			enabled = pack.Free or profile.enabledPacks[pack.Id] == true,
			color = pack.Color,
		})
	end
	return {
		points = profile.points,
		matchesCompleted = profile.matchesCompleted,
		awardsEarned = profile.awardsEarned,
		packs = packs,
		saveDisabled = loadFailed[player] == true,
	}
end

function PlayerDataManager.push(player: Player)
	local data = PlayerDataManager.publicProfile(player)
	if data then
		Net.fire(player, "ProfileUpdated", data)
	end
end

function PlayerDataManager.get(player: Player): Profile?
	return profiles[player]
end

function PlayerDataManager.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or loadFailed[player] or not store then
		return false
	end
	local dataStore = store :: DataStore
	profile.saveCount += 1
	local snapshot = table.clone(profile)
	snapshot.unlockedPacks = table.clone(profile.unlockedPacks)
	snapshot.enabledPacks = table.clone(profile.enabledPacks)
	local ok, err = withRetries(function()
		return dataStore:UpdateAsync(keyFor(player), function(old)
			if type(old) == "table" and type(old.saveCount) == "number" and old.saveCount >= snapshot.saveCount then
				-- Stored data is newer (e.g. another server saved later). Don't clobber it.
				return nil
			end
			return snapshot
		end)
	end)
	if not ok then
		warn(string.format("[PlayerData] save failed for %s: %s", player.Name, tostring(err)))
		return false
	end
	dirty[player] = nil
	return true
end

local function checkMilestones(player: Player, profile: Profile)
	for _, pack in PromptPacks.Packs do
		if not pack.Free and not profile.unlockedPacks[pack.Id] and pack.MilestoneMatches
			and profile.matchesCompleted >= pack.MilestoneMatches then
			profile.unlockedPacks[pack.Id] = true
			Net.notify(player, string.format("Milestone! %s pack unlocked for free.", pack.DisplayName), "success")
		end
	end
end

-- Applies a reward grant computed by RewardManager.
function PlayerDataManager.applyGrant(player: Player, grant: { points: number, matchCompleted: boolean, awards: number })
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.points += grant.points
	if grant.matchCompleted then
		profile.matchesCompleted += 1
	end
	profile.awardsEarned += grant.awards
	checkMilestones(player, profile)
	dirty[player] = true
	PlayerDataManager.push(player)
	task.spawn(PlayerDataManager.save, player)
end

function PlayerDataManager.unlockPack(player: Player, packId: any): (boolean, string)
	local profile = profiles[player]
	if not profile then
		return false, "Your profile is still loading."
	end
	if type(packId) ~= "string" then
		return false, "Unknown pack."
	end
	local pack = PromptPacks.getPack(packId)
	if not pack then
		return false, "Unknown pack."
	end
	if profile.unlockedPacks[pack.Id] then
		return false, "You already own that pack."
	end
	local cost = pack.Cost
	if not cost then
		return false, "That pack can't be bought with points."
	end
	if profile.points < cost then
		return false, string.format("You need %d Doodle Points.", cost)
	end
	profile.points -= cost
	profile.unlockedPacks[pack.Id] = true
	profile.enabledPacks[pack.Id] = true
	dirty[player] = true
	PlayerDataManager.push(player)
	task.spawn(PlayerDataManager.save, player)
	return true, string.format("Unlocked %s!", pack.DisplayName)
end

function PlayerDataManager.setPackEnabled(player: Player, packId: any, enabled: any)
	local profile = profiles[player]
	if not profile or type(packId) ~= "string" or type(enabled) ~= "boolean" then
		return
	end
	if not profile.unlockedPacks[packId] or packId == PromptPacks.FreePackId then
		return
	end
	profile.enabledPacks[packId] = enabled or nil
	dirty[player] = true
	PlayerDataManager.push(player)
end

-- Pack ids enabled by this player (always includes the free pack).
function PlayerDataManager.enabledPacks(player: Player): { [string]: boolean }
	local out = { [PromptPacks.FreePackId] = true }
	local profile = profiles[player]
	if profile then
		for packId, on in profile.enabledPacks do
			if on and profile.unlockedPacks[packId] then
				out[packId] = true
			end
		end
	end
	return out
end

local function onPlayerAdded(player: Player)
	local profile: Profile
	if store then
		local dataStore = store :: DataStore
		local ok, result = withRetries(function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			profile = reconcile(result)
		else
			warn(string.format("[PlayerData] load failed for %s: %s", player.Name, tostring(result)))
			loadFailed[player] = true
			profile = defaultProfile()
		end
	else
		loadFailed[player] = true
		profile = defaultProfile()
	end
	if player.Parent ~= Players then
		return
	end
	profiles[player] = profile
	if loadFailed[player] then
		Net.notify(player, "Couldn't load your Doodle Points. Progress won't save this session.", "warning")
	end
	PlayerDataManager.push(player)
	loadedSignal:Fire(player)
end

function PlayerDataManager.init()
	print("[PlayerData] using DataStore " .. STORE_NAME)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		if dirty[player] then
			PlayerDataManager.save(player)
		end
		profiles[player] = nil
		loadFailed[player] = nil
		dirty[player] = nil
	end)
	game:BindToClose(function()
		local threads = 0
		for player in profiles do
			if dirty[player] then
				threads += 1
				task.spawn(function()
					PlayerDataManager.save(player)
					threads -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while threads > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for player in profiles do
				if dirty[player] then
					task.spawn(PlayerDataManager.save, player)
				end
			end
		end
	end)
end

return PlayerDataManager
