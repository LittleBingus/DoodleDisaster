--!strict
-- Minimal test runner for Doodle Disaster's pure game logic.
-- Run in Roblox Studio (Edit or Play/Server) from the command bar:
--     require(game.ServerStorage.Tests.TestRunner)()
-- Returns passed, failed and prints a summary to Output.

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function makeContext(results: { any }, specName: string)
	local t = {}
	function t.test(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		table.insert(results, { spec = specName, name = name, ok = ok, err = err })
	end
	function t.eq(actual: any, expected: any, msg: string?)
		if not deepEqual(actual, expected) then
			error(string.format("%sexpected %s, got %s", if msg then msg .. ": " else "", tostring(expected), tostring(actual)), 2)
		end
	end
	function t.truthy(value: any, msg: string?)
		if not value then
			error((msg or "expected truthy value") .. " (got " .. tostring(value) .. ")", 2)
		end
	end
	function t.falsy(value: any, msg: string?)
		if value then
			error((msg or "expected falsy value") .. " (got " .. tostring(value) .. ")", 2)
		end
	end
	function t.near(actual: number, expected: number, tolerance: number, msg: string?)
		if math.abs(actual - expected) > tolerance then
			error(string.format("%sexpected %.4f ± %.4f, got %.4f", if msg then msg .. ": " else "", expected, tolerance, actual), 2)
		end
	end
	return t
end

return function(filter: string?)
	local results = {}
	local specs = script.Parent:WaitForChild("specs"):GetChildren()
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)
	for _, spec in specs do
		if spec:IsA("ModuleScript") and (not filter or spec.Name:find(filter, 1, true)) then
			local ok, fnOrErr = pcall(require, spec)
			if not ok then
				table.insert(results, { spec = spec.Name, name = "(load)", ok = false, err = fnOrErr })
			else
				local ctx = makeContext(results, spec.Name)
				local ranOk, runErr = pcall(fnOrErr, ctx)
				if not ranOk then
					table.insert(results, { spec = spec.Name, name = "(run)", ok = false, err = runErr })
				end
			end
		end
	end
	local passed, failed = 0, 0
	for _, r in results do
		if r.ok then
			passed += 1
		else
			failed += 1
			warn(string.format("FAIL %s > %s: %s", r.spec, r.name, tostring(r.err)))
		end
	end
	print(string.format("[DoodleDisaster tests] %d passed, %d failed, %d total", passed, failed, passed + failed))
	return passed, failed, results
end
