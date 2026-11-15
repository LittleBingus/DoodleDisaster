local D = require(script.Parent.Parent.Deps)
local GuessFallback, GameConfig, TextRules = D.GuessFallback, D.GameConfig, D.TextRules

return function(t)
	t.test("uncensored guesses are kept, however short", function()
		t.truthy(GuessFallback.isUsable("a cat", "a cat"))
		t.truthy(GuessFallback.isUsable("ox", "ox"))
		t.truthy(GuessFallback.isUsable("7", "7"))
		t.truthy(GuessFallback.isUsable("#1 dad", "#1 dad"), "a # the player typed is not censorship")
		t.truthy(GuessFallback.isUsable("un gato", "un gato"))
		t.truthy(GuessFallback.isUsable("猫", "猫"), "non-ASCII text counts as words")
	end)

	t.test("fully censored or failed guesses are unusable", function()
		t.falsy(GuessFallback.isUsable("something rude", "#########"))
		t.falsy(GuessFallback.isUsable("two words", "### #####"))
		t.falsy(GuessFallback.isUsable("rude!", "####!"))
		t.falsy(GuessFallback.isUsable("anything", nil), "filter error")
		t.falsy(GuessFallback.isUsable("anything", ""))
		t.falsy(GuessFallback.isUsable("?!", "?!"), "no words at all")
	end)

	t.test("mostly censored guesses are unusable, partly censored ones are kept", function()
		t.falsy(GuessFallback.isUsable("a rudeword", "a ########"))
		t.falsy(GuessFallback.isUsable("my rudeword", "my ########"))
		t.truthy(GuessFallback.isUsable("a big rudeword dog", "a big #### dog"))
		t.truthy(GuessFallback.isUsable("flying xx spaghetti", "flying ## spaghetti"))
	end)

	t.test("replacements come only from the approved list and avoid repeats", function()
		local phrases = GameConfig.Guess.FallbackPhrases
		t.truthy(#phrases >= 20)
		local allowed = {}
		for _, p in phrases do
			allowed[p] = true
		end
		local rng = Random.new(11)
		local used, picked = {}, {}
		for _ = 1, #phrases do
			local choice = GuessFallback.pick(phrases, used, function()
				return rng:NextNumber()
			end)
			t.truthy(allowed[choice])
			t.falsy(picked[choice], "no repeat until the list is exhausted")
			picked[choice] = true
		end
		t.truthy(allowed[GuessFallback.pick(phrases, used, function()
			return 1
		end)], "still returns a phrase once all were used, even at the rng edge")
	end)

	t.test("every replacement phrase is a valid, clean guess", function()
		local seen = {}
		for _, p in GameConfig.Guess.FallbackPhrases do
			t.eq(TextRules.sanitize(p, GameConfig.Guess.MaxLength), p)
			t.falsy(p:find("#", 1, true))
			t.falsy(seen[p], "duplicate phrase: " .. p)
			seen[p] = true
		end
	end)
end
