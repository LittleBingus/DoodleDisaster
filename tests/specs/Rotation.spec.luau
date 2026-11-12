local D = require(script.Parent.Parent.Deps)
local Rotation = D.Rotation

return function(t)
	for n = 1, 8 do
		t.test("schedule is valid for " .. n .. " players", function()
			local ok, err = Rotation.validateSchedule(Rotation.buildSchedule(n), n)
			t.truthy(ok, err)
		end)
	end

	t.test("validator catches a duplicated book", function()
		local bad = Rotation.buildSchedule(4)
		bad[2][1] = bad[2][2]
		t.falsy((Rotation.validateSchedule(bad, 4)))
	end)

	t.test("bookForPlayer and playerForBook are inverses", function()
		for n = 3, 8 do
			for step = 0, n - 1 do
				for p = 1, n do
					local b = Rotation.bookForPlayer(p, step, n)
					t.eq(Rotation.playerForBook(b, step, n), p)
				end
			end
		end
	end)

	t.test("entries alternate Draw/Guess; final is Draw for odd, Guess for even", function()
		for n = 3, 8 do
			for step = 0, n - 1 do
				t.eq(Rotation.kindForStep(step), if step % 2 == 0 then "Draw" else "Guess")
			end
			t.eq(Rotation.kindForStep(n - 1), if n % 2 == 1 then "Draw" else "Guess", "final entry for n=" .. n)
		end
	end)
end
