--!strict
--[[
	32-bit integer helpers.

	Luau numbers are doubles, so a plain 32x32 multiply loses the low bits once the
	product passes 2^53. `imul` splits the operands into 16-bit halves to keep the
	result exact modulo 2^32, matching C's uint32_t semantics.
]]

local Bits = {}

local TWO_32 = 4294967296

function Bits.imul(a: number, b: number): number
	local ah = bit32.rshift(a, 16)
	local al = bit32.band(a, 0xFFFF)
	local bh = bit32.rshift(b, 16)
	local bl = bit32.band(b, 0xFFFF)
	local high = bit32.lshift(ah * bl + al * bh, 16)
	return (high + al * bl) % TWO_32
end

function Bits.u32(x: number): number
	return x % TWO_32
end

-- FNV-1a 32-bit hash of a string as a number in [0, 2^32).
function Bits.hash32(s: string): number
	local hash = 2166136261
	for i = 1, #s do
		hash = bit32.bxor(hash, string.byte(s, i))
		hash = Bits.imul(hash, 16777619)
	end
	return hash
end

--[=[
	FNV-1a 32-bit hash of a string, returned as an 8-character hex string.
	Used for integrity checks and shard placement, not for security.
]=]
function Bits.fnv1a(s: string): string
	local hash = 2166136261
	for i = 1, #s do
		hash = bit32.bxor(hash, string.byte(s, i))
		hash = Bits.imul(hash, 16777619)
	end
	return string.format("%08x", hash)
end

return Bits
