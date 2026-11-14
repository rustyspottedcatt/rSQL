--!strict
-- String helpers for error messages.

local Text = {}

-- Levenshtein distance (case-insensitive), using two rows of memory.
function Text.distance(a: string, b: string): number
	a, b = string.lower(a), string.lower(b)
	local prev = table.create(#b + 1, 0)
	for j = 1, #b + 1 do
		prev[j] = j - 1
	end
	for i = 1, #a do
		local cur = table.create(#b + 1, 0)
		cur[1] = i
		for j = 1, #b do
			local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
			cur[j + 1] = math.min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
		end
		prev = cur
	end
	return prev[#b + 1]
end

-- The candidate closest to `word`, if it is at most `maxDistance` edits away.
function Text.closest(word: string, candidates: { string }, maxDistance: number): string?
	local best, bestDistance = nil, maxDistance + 1
	for _, candidate in candidates do
		if math.abs(#candidate - #word) <= maxDistance then
			local d = Text.distance(word, candidate)
			if d < bestDistance and d < #word then
				best, bestDistance = candidate, d
			end
		end
	end
	return best
end

return Text
