--!strict
-- Rewards: decides who earns what at the end of a match. Pure logic.
--
-- participants: { { userId, stillPresent, activeSubmissions, totalTasks } }
-- awardWinners: { [userId]: number of awards won }
-- config: GameConfig.Rewards
-- returns { [userId]: { points, matchCompleted, awards } } for eligible players only.

local Rewards = {}

export type Participant = {
	userId: number,
	stillPresent: boolean,
	activeSubmissions: number,
	totalTasks: number,
}

export type Grant = { points: number, matchCompleted: boolean, awards: number }

function Rewards.isLegitimateCompletion(p: Participant, config: any): boolean
	if not p.stillPresent then
		return false
	end
	if p.totalTasks <= 0 then
		return false
	end
	return p.activeSubmissions / p.totalTasks >= config.MinActiveSubmissionRatio
end

function Rewards.compute(participants: { Participant }, awardWinners: { [number]: number }, config: any): { [number]: Grant }
	local grants: { [number]: Grant } = {}
	for _, p in participants do
		if Rewards.isLegitimateCompletion(p, config) then
			local awards = awardWinners[p.userId] or 0
			grants[p.userId] = {
				points = config.MatchCompletion + awards * config.AwardBonus,
				matchCompleted = true,
				awards = awards,
			}
		end
	end
	return grants
end

return Rewards
