--!strict
-- RateLimiter: per-key sliding-window limiter. Pure logic (clock injected).

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: {
	count: number,
	window: number,
	clock: () -> number,
	hits: { [any]: { number } },
}, RateLimiter))

function RateLimiter.new(count: number, window: number, clock: (() -> number)?): RateLimiter
	return setmetatable({
		count = count,
		window = window,
		clock = clock or os.clock,
		hits = {},
	}, RateLimiter)
end

-- Returns true if the action is allowed (and records it).
function RateLimiter.allow(self: RateLimiter, key: any): boolean
	local now = self.clock()
	local list = self.hits[key]
	if not list then
		list = {}
		self.hits[key] = list
	end
	local cutoff = now - self.window
	local kept = {}
	for _, t in list do
		if t > cutoff then
			table.insert(kept, t)
		end
	end
	if #kept >= self.count then
		self.hits[key] = kept
		return false
	end
	table.insert(kept, now)
	self.hits[key] = kept
	return true
end

function RateLimiter.forget(self: RateLimiter, key: any)
	self.hits[key] = nil
end

return RateLimiter
