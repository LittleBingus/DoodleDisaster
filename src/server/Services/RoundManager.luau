--!strict
-- RoundManager: runs one match from StartingMatch to ReturningToLobby.
-- Wraps the pure MatchCore with real timers, remotes, text filtering and seating.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)
local Rotation = require(Shared.Rotation)
local DrawingTypes = require(Shared.DrawingTypes)
local TextRules = require(Shared.TextRules)

local Logic = script.Parent.Parent.Logic
local MatchCore = require(Logic.MatchCore)
local SkipVote = require(Logic.SkipVote)

local GameState = require(script.Parent.GameState)
local Net = require(script.Parent.Net)
local PromptManager = require(script.Parent.PromptManager)
local StationManager = require(script.Parent.StationManager)
local VotingManager = require(script.Parent.VotingManager)
local RewardManager = require(script.Parent.RewardManager)
local TextFilter = require(script.Parent.TextFilter)

local RoundManager = {}

local core: any = nil
local pendingGuess: { [number]: boolean } = {}
local revealHistory: { any } = {} -- events of the current sketchbook, for late syncs
local lastResults: any = nil
local skipStatus: () -> any -- defined with the reveal code below

local function participantsPresent(): { Player }
	local out = {}
	for userId in GameState.participants do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

function RoundManager.sendTask(player: Player)
	if not core or not Phases.Seated[GameState.phase] then
		return
	end
	if GameState.phase ~= Phases.Drawing and GameState.phase ~= Phases.Guessing then
		return
	end
	local t = core:getTask(player.UserId)
	if t then
		t.endsAt = GameState.endsAt
		t.station = GameState.stations[player.UserId]
		t.matchId = GameState.matchId -- lets clients tell step N of this match from step N of the last one
		Net.fire(player, "TaskAssigned", t)
	end
end

function RoundManager.syncPlayer(player: Player)
	RoundManager.sendTask(player)
	if GameState.phase == Phases.Reveal then
		for _, ev in revealHistory do
			Net.fire(player, "RevealEvent", ev)
		end
		Net.fire(player, "RevealSkipStatus", skipStatus())
	elseif GameState.phase == Phases.AwardVoting then
		VotingManager.sendBallot(player)
	elseif GameState.phase == Phases.Results and lastResults then
		Net.fire(player, "VotingClosed", lastResults)
	end
end

local function minToContinue(): number
	return if GameState.devMode then 1 else 2
end

local function tooFewLeft(): boolean
	return core:connectedCount() < minToContinue()
end

-- Waits until everyone submitted, the deadline (+grace) passes, or the match must abort.
local function waitForSubmissions(duration: number): boolean
	local deadline = os.clock() + duration + GameConfig.Timers.SubmissionGrace
	while os.clock() < deadline do
		if tooFewLeft() then
			return false
		end
		if core:allSubmitted() and next(pendingGuess) == nil then
			break
		end
		task.wait(0.2)
	end
	return true
end

local function broadcastReveal(ev: any)
	table.insert(revealHistory, ev)
	Net.fireAll("RevealEvent", ev)
end

-- Fast-forward voting ----------------------------------------------------------------------
local skipVotes: any = nil
local entrySeq, bookSeq = 0, 0

-- Participants who are still connected. Spectators and leavers never count.
local function revealVoters(): { number }
	local out = {}
	if core then
		for _, userId in core.userIds do
			if not core.left[userId] and Players:GetPlayerByUserId(userId) then
				table.insert(out, userId)
			end
		end
	end
	return out
end

function skipStatus()
	local voters = revealVoters()
	return {
		entry = if skipVotes then skipVotes:count("Entry", voters) else 0,
		book = if skipVotes then skipVotes:count("Book", voters) else 0,
		needed = SkipVote.needed(#voters),
		entrySeq = entrySeq,
		bookSeq = bookSeq,
	}
end

local function broadcastSkipStatus()
	Net.fireAll("RevealSkipStatus", skipStatus())
end

-- Waits for `duration`, or less if a majority votes to skip (never less than RevealMinRead).
-- Returns true when the rest of the current sketchbook should be skipped.
local function revealWait(duration: number): boolean
	entrySeq += 1
	skipVotes:reset("Entry")
	broadcastSkipStatus()
	local started = os.clock()
	local minRead = math.min(duration, GameConfig.Timers.RevealMinRead)
	while true do
		local elapsed = os.clock() - started
		if elapsed >= duration then
			return false
		end
		if elapsed >= minRead then
			local voters = revealVoters()
			if skipVotes:passed("Book", voters) then
				return true
			end
			if skipVotes:passed("Entry", voters) then
				return false
			end
		end
		task.wait(0.1)
	end
end

local function runReveal()
	local books = core:getRevealBooks()
	local n = #books
	local entryTime = GameConfig.Timers.RevealEntry
	local perBook = GameConfig.Timers.RevealIntro + n * entryTime + GameConfig.Timers.RevealBookOutro
	skipVotes = SkipVote.new()
	GameState.setPhase(Phases.Reveal, perBook * n)
	for b, book in books do
		revealHistory = {}
		bookSeq += 1
		skipVotes:reset("Book")
		-- Skips shorten the reveal, so re-publish the remaining time at the start of each book.
		GameState.setTimer(perBook * (n - b + 1))
		broadcastReveal({ type = "Book", bookIndex = b, bookCount = n, prompt = book.prompt, entryTime = entryTime })
		local skipBook = revealWait(GameConfig.Timers.RevealIntro)
		if not skipBook then
			for i, entry in book.entries do
				broadcastReveal({
					type = "Entry",
					bookIndex = b,
					entryIndex = i,
					entryCount = #book.entries,
					kind = entry.kind,
					content = entry.content,
					auto = entry.auto,
				})
				if revealWait(entryTime) then
					break
				end
			end
		end
		-- The "started as / ended as" card always shows, even after a skip.
		skipVotes:reset("Book")
		broadcastReveal({ type = "BookEnd", bookIndex = b, bookCount = n, prompt = book.prompt,
			final = book.entries[#book.entries] })
		revealWait(GameConfig.Timers.RevealBookOutro)
	end
	revealHistory = {}
	skipVotes = nil
	Net.fireAll("RevealEvent", { type = "Finished" })
end

local function onRevealSkipVote(player: Player, scope: any)
	if GameState.phase ~= Phases.Reveal or not skipVotes or not core then
		return
	end
	local uid = player.UserId
	if not core:isParticipant(uid) or core.left[uid] then
		return
	end
	if skipVotes:cast(scope, uid) then
		broadcastSkipStatus()
	end
end

local function abortMatch(reason: string)
	Net.notifyAll(reason, "warning")
	Net.fireAll("TaskCleared")
end

local function finishMatch()
	Net.fireAll("TaskCleared")
	StationManager.unlockAll()
	GameState.setPhase(Phases.ReturningToLobby, GameConfig.Timers.ReturningToLobby)
	core = nil
	skipVotes = nil
	pendingGuess = {}
	revealHistory = {}
	GameState.participants = {}
	GameState.step = 0
	GameState.totalSteps = 0
	StationManager.clear()
	task.wait(GameConfig.Timers.ReturningToLobby)
	lastResults = nil
	GameState.setPhase(Phases.WaitingForPlayers)
end

function RoundManager.runMatch(players: { Player })
	GameState.matchId += 1
	local matchId = GameState.matchId
	local n = #players
	local prompts, packNames = PromptManager.pick(players, GameState.difficulty, n)
	if #prompts < n then
		warn("[RoundManager] not enough prompts for " .. n .. " players")
		GameState.setPhase(Phases.StartingMatch)
		abortMatch("Ran out of prompts! Returning to the lobby.")
		finishMatch()
		return
	end

	local userIds = {}
	GameState.participants = {}
	for _, p in players do
		table.insert(userIds, p.UserId)
		GameState.participants[p.UserId] = true
	end
	core = MatchCore.new({
		userIds = userIds,
		prompts = prompts,
		Rotation = Rotation,
		validateDrawing = DrawingTypes.validate,
		isBlankDrawing = DrawingTypes.isBlank,
		emptyDrawing = DrawingTypes.empty,
		guessTimeoutText = GameConfig.Guess.TimeoutPlaceholder,
		guessLeftText = GameConfig.Guess.LeftPlaceholder,
	})
	GameState.totalSteps = n
	GameState.step = 0

	StationManager.assign(players)
	GameState.setPhase(Phases.StartingMatch, GameConfig.Timers.StartingMatch)
	StationManager.lockAll()
	Net.notifyAll(string.format("%s • Packs: %s",
		GameConfig.Difficulties[GameState.difficulty].DisplayName, table.concat(packNames, ", ")), "info")
	task.wait(GameConfig.Timers.StartingMatch)

	-- Drawing / guessing rounds
	for step = 0, n - 1 do
		local kind = Rotation.kindForStep(step)
		local phase = if kind == "Draw" then Phases.Drawing else Phases.Guessing
		local duration = if kind == "Draw" then GameConfig.Timers.Drawing else GameConfig.Timers.Guessing
		GameState.step = step
		GameState.setPhase(phase, duration)
		for _, p in participantsPresent() do
			RoundManager.sendTask(p)
		end
		local ok = waitForSubmissions(duration)
		if not ok then
			GameState.setPhase(Phases.ReturningToLobby)
			abortMatch("Too many players left. Class dismissed early!")
			-- ReturningToLobby already set; finish without re-entering it.
			StationManager.unlockAll()
			core = nil
			GameState.participants = {}
			StationManager.clear()
			task.wait(GameConfig.Timers.ReturningToLobby)
			GameState.setPhase(Phases.WaitingForPlayers)
			return
		end
		GameState.setPhase(Phases.CollectingSubmissions, GameConfig.Timers.CollectingSubmissions)
		Net.fireAll("TaskCleared")
		core:finalizeStep()
		task.wait(GameConfig.Timers.CollectingSubmissions)
	end

	-- Shared reveal: movement is restored so players can wander and emote.
	StationManager.unlockAll()
	runReveal()

	-- Anonymous voting
	local results, awardCounts = VotingManager.run(core, participantsPresent())
	lastResults = results
	for _, r in results do
		if #r.winners > 0 then
			GameState.lastAwardText = string.format("%s\n%s", r.displayName, r.winners[1].authorName)
			break
		end
	end

	-- Rewards + results
	GameState.setPhase(Phases.Results, GameConfig.Timers.Results)
	RewardManager.grantMatch(matchId, core, awardCounts)
	task.wait(GameConfig.Timers.Results)

	finishMatch()
end

local function onSubmitDrawing(player: Player, step: any, drawing: any)
	if not core or GameState.phase ~= Phases.Drawing then
		Net.notify(player, "Too late! That sketch didn't make it.", "warning")
		return
	end
	local ok, err = core:submit(player.UserId, step, "Draw", drawing)
	if ok then
		GameState.submitted[player.UserId] = true
		GameState.broadcast()
		RoundManager.sendTask(player) -- now flagged submitted -> client shows waiting
	elseif err ~= "already submitted" then
		Net.notify(player, "Sketch rejected: " .. tostring(err), "warning")
		warn(string.format("[RoundManager] rejected drawing from %s: %s", player.Name, tostring(err)))
	end
end

local function onSubmitGuess(player: Player, step: any, raw: any)
	if not core or GameState.phase ~= Phases.Guessing then
		Net.notify(player, "Too late! That guess didn't make it.", "warning")
		return
	end
	local uid = player.UserId
	if pendingGuess[uid] or core.submitted[uid] or step ~= core.step or not core:isParticipant(uid) then
		return
	end
	local text, err = TextRules.sanitize(raw, GameConfig.Guess.MaxLength)
	if not text then
		if err == "text is empty" then
			Net.notify(player, "Type a guess first!", "info")
		else
			Net.notify(player, "Guess rejected: " .. tostring(err), "warning")
		end
		return
	end
	pendingGuess[uid] = true
	local activeCore = core
	local filtered = TextFilter.forBroadcast(text :: string, uid)
	pendingGuess[uid] = nil
	if core ~= activeCore then
		return
	end
	local ok, submitErr = core:submit(uid, step, "Guess", filtered or GameConfig.Guess.FilterFailedPlaceholder)
	if ok then
		GameState.submitted[uid] = true
		GameState.broadcast()
		RoundManager.sendTask(player)
	elseif submitErr ~= "already submitted" then
		Net.notify(player, "Guess rejected: " .. tostring(submitErr), "warning")
	end
end

function RoundManager.init()
	local limit = GameConfig.RateLimits.Submit
	Net.on("SubmitDrawing", limit, onSubmitDrawing)
	Net.on("SubmitGuess", limit, onSubmitGuess)
	Net.on("RevealSkipVote", GameConfig.RateLimits.RevealSkip, onRevealSkipVote)
	Players.PlayerRemoving:Connect(function(player)
		pendingGuess[player.UserId] = nil
		if core and core:isParticipant(player.UserId) then
			core:markLeft(player.UserId)
			if GameState.phase == Phases.Reveal and skipVotes then
				broadcastSkipStatus() -- the majority threshold just changed
			end
			Net.notifyAll(player.DisplayName .. " left. Their pages will be filled in by the class gremlin.", "info")
		end
	end)
end

return RoundManager
