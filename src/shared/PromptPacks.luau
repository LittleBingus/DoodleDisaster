--!strict
-- PromptPacks: the prompt library and pack definitions.
-- Pure data, safe everywhere. Each prompt has:
--   Id, Phrase, Category ("Scenario" | "Idiom" | "Metaphor"), Difficulty ("Easy" | "Medium" | "Hard"),
--   Pack (pack id), Enabled (bool)

export type Prompt = {
	Id: string,
	Phrase: string,
	Category: string,
	Difficulty: string,
	Pack: string,
	Enabled: boolean,
}

export type Pack = {
	Id: string,
	DisplayName: string,
	Description: string,
	Free: boolean,
	Cost: number?, -- Doodle Points
	MilestoneMatches: number?, -- unlocks for free after this many completed matches
	Color: { number },
}

local PromptPacks = {}

PromptPacks.Packs = {
	{
		Id = "StarterChaos",
		DisplayName = "Starter Chaos",
		Description = "Funny scenarios, classic idioms and a few brain-benders. Always on.",
		Free = true,
		Color = { 255, 196, 0 },
	},
	{
		Id = "Brainrot",
		DisplayName = "Brainrot",
		Description = "Absurd, meme-flavoured nonsense.",
		Free = false,
		Cost = 60,
		MilestoneMatches = 8,
		Color = { 170, 85, 255 },
	},
	{
		Id = "EverydayDisasters",
		DisplayName = "Everyday Disasters",
		Description = "Relatable moments that become ridiculous when drawn.",
		Free = false,
		Cost = 80,
		MilestoneMatches = 10,
		Color = { 0, 190, 140 },
	},
	{
		Id = "ImpossibleSituations",
		DisplayName = "Impossible Situations",
		Description = "Unusual scenarios and the trickiest metaphors.",
		Free = false,
		Cost = 120,
		MilestoneMatches = 15,
		Color = { 255, 80, 90 },
	},
} :: { Pack }

local CATEGORY_DIFFICULTY = {
	Scenario = "Easy",
	Idiom = "Medium",
	Metaphor = "Hard",
}

-- Compact source table: { pack, category, phrase[, difficultyOverride] }
local RAW: { { string } } = {
	-- Starter Chaos: Easy scenarios
	{ "StarterChaos", "Scenario", "A banana riding a skateboard" },
	{ "StarterChaos", "Scenario", "A penguin delivering pizza" },
	{ "StarterChaos", "Scenario", "A dinosaur eating spaghetti" },
	{ "StarterChaos", "Scenario", "A grandmother fighting a giant chicken" },
	{ "StarterChaos", "Scenario", "A cat working at a restaurant" },
	{ "StarterChaos", "Scenario", "A shark taking a bubble bath" },
	{ "StarterChaos", "Scenario", "A robot walking a dog" },
	{ "StarterChaos", "Scenario", "A snowman at the beach" },
	{ "StarterChaos", "Scenario", "A giraffe stuck in an elevator" },
	{ "StarterChaos", "Scenario", "An octopus playing the drums" },
	{ "StarterChaos", "Scenario", "A wizard ordering fast food" },
	{ "StarterChaos", "Scenario", "A cow on a trampoline" },
	{ "StarterChaos", "Scenario", "A pirate afraid of water" },
	{ "StarterChaos", "Scenario", "A hamster driving a monster truck" },
	{ "StarterChaos", "Scenario", "A teacher sleeping in class" },
	{ "StarterChaos", "Scenario", "An alien at a birthday party" },
	{ "StarterChaos", "Scenario", "A frog lifting weights" },
	{ "StarterChaos", "Scenario", "A taco on vacation" },
	{ "StarterChaos", "Scenario", "A ghost doing laundry" },
	{ "StarterChaos", "Scenario", "A knight riding a goose" },
	-- Starter Chaos: Medium idioms
	{ "StarterChaos", "Idiom", "It's raining cats and dogs" },
	{ "StarterChaos", "Idiom", "Spill the beans" },
	{ "StarterChaos", "Idiom", "Break the ice" },
	{ "StarterChaos", "Idiom", "A fish out of water" },
	{ "StarterChaos", "Idiom", "The elephant in the room" },
	{ "StarterChaos", "Idiom", "Hit the nail on the head" },
	{ "StarterChaos", "Idiom", "Let the cat out of the bag" },
	{ "StarterChaos", "Idiom", "Piece of cake" },
	{ "StarterChaos", "Idiom", "Cold feet" },
	{ "StarterChaos", "Idiom", "When pigs fly" },
	{ "StarterChaos", "Idiom", "Butterflies in your stomach" },
	{ "StarterChaos", "Idiom", "Bite off more than you can chew" },
	{ "StarterChaos", "Idiom", "Couch potato" },
	{ "StarterChaos", "Idiom", "Hold your horses" },
	{ "StarterChaos", "Idiom", "Once in a blue moon" },
	{ "StarterChaos", "Idiom", "Barking up the wrong tree" },
	-- Starter Chaos: Hard metaphors
	{ "StarterChaos", "Metaphor", "Carrying the weight of the world" },
	{ "StarterChaos", "Metaphor", "Time is slipping away" },
	{ "StarterChaos", "Metaphor", "Walking on thin ice" },
	{ "StarterChaos", "Metaphor", "A wolf in sheep's clothing" },
	{ "StarterChaos", "Metaphor", "Burning the candle at both ends" },
	{ "StarterChaos", "Metaphor", "A storm in a teacup" },
	{ "StarterChaos", "Metaphor", "Drowning in homework" },
	{ "StarterChaos", "Metaphor", "A heart of gold" },
	{ "StarterChaos", "Metaphor", "The calm before the storm" },
	{ "StarterChaos", "Metaphor", "Opening a can of worms" },
	{ "StarterChaos", "Metaphor", "Reaching for the stars" },
	{ "StarterChaos", "Metaphor", "Lost in your own thoughts" },

	-- Brainrot
	{ "Brainrot", "Scenario", "A toilet that wants to be famous" },
	{ "Brainrot", "Scenario", "A pigeon running for president" },
	{ "Brainrot", "Scenario", "A sandwich with a six-pack" },
	{ "Brainrot", "Scenario", "A goldfish livestreaming" },
	{ "Brainrot", "Scenario", "A potato with main character energy" },
	{ "Brainrot", "Scenario", "A duck that only speaks in emojis" },
	{ "Brainrot", "Idiom", "Touch grass" },
	{ "Brainrot", "Idiom", "Living rent-free in your head" },
	{ "Brainrot", "Idiom", "Lost the plot" },
	{ "Brainrot", "Idiom", "Going down the rabbit hole" },
	{ "Brainrot", "Metaphor", "Your brain buffering at 1%" },
	{ "Brainrot", "Metaphor", "Running on zero sleep and pure vibes" },
	{ "Brainrot", "Metaphor", "The group chat on fire" },

	-- Everyday Disasters
	{ "EverydayDisasters", "Scenario", "Stepping on a LEGO brick" },
	{ "EverydayDisasters", "Scenario", "Dropping your phone in the toilet" },
	{ "EverydayDisasters", "Scenario", "Waving at someone who wasn't waving at you" },
	{ "EverydayDisasters", "Scenario", "Burning toast at 7 AM" },
	{ "EverydayDisasters", "Scenario", "A seagull stealing your fries" },
	{ "EverydayDisasters", "Scenario", "Forgetting your homework on the bus" },
	{ "EverydayDisasters", "Idiom", "Got up on the wrong side of the bed" },
	{ "EverydayDisasters", "Idiom", "Running around like a headless chicken" },
	{ "EverydayDisasters", "Idiom", "Crying over spilled milk" },
	{ "EverydayDisasters", "Idiom", "Up to your ears in laundry" },
	{ "EverydayDisasters", "Metaphor", "Monday is a mountain" },
	{ "EverydayDisasters", "Metaphor", "The fridge is a black hole" },
	{ "EverydayDisasters", "Metaphor", "Stuck in a traffic jam of thoughts" },

	-- Impossible Situations
	{ "ImpossibleSituations", "Scenario", "A volcano that sneezes glitter" },
	{ "ImpossibleSituations", "Scenario", "The moon getting a haircut" },
	{ "ImpossibleSituations", "Scenario", "A whale stuck in a phone booth" },
	{ "ImpossibleSituations", "Scenario", "Gravity taking a day off" },
	{ "ImpossibleSituations", "Idiom", "Moving mountains" },
	{ "ImpossibleSituations", "Idiom", "Raining on someone's parade" },
	{ "ImpossibleSituations", "Idiom", "Painting the town red" },
	{ "ImpossibleSituations", "Metaphor", "Building castles in the air" },
	{ "ImpossibleSituations", "Metaphor", "Chasing your own shadow" },
	{ "ImpossibleSituations", "Metaphor", "A sea of faces" },
	{ "ImpossibleSituations", "Metaphor", "Bottling up a thunderstorm" },
	{ "ImpossibleSituations", "Metaphor", "Swimming against the current" },
	{ "ImpossibleSituations", "Metaphor", "Knowledge is a lighthouse" },
}

local function buildPrompts(): { Prompt }
	local prompts: { Prompt } = {}
	local counters: { [string]: number } = {}
	for _, row in RAW do
		local pack, category, phrase = row[1], row[2], row[3]
		counters[pack] = (counters[pack] or 0) + 1
		table.insert(prompts, {
			Id = string.format("%s_%03d", pack, counters[pack]),
			Phrase = phrase,
			Category = category,
			Difficulty = row[4] or CATEGORY_DIFFICULTY[category],
			Pack = pack,
			Enabled = true,
		})
	end
	return prompts
end

PromptPacks.Prompts = buildPrompts()
PromptPacks.FreePackId = "StarterChaos"

function PromptPacks.getPack(packId: string): Pack?
	for _, pack in PromptPacks.Packs do
		if pack.Id == packId then
			return pack
		end
	end
	return nil
end

return PromptPacks
