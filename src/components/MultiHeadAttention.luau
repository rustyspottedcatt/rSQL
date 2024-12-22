local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)
local LinearAlgebra = LinearAlgebraModule.new()

export type Matrix = Types.Matrix

export type MultiHeadAttentionClass = {
	new: (dModel: number, numHeads: number) -> MultiHeadAttentionClass,
	dModel: number,
	numHeads: number,
	dHead: number,
	Wq: Matrix,
	Wk: Matrix,
	Wv: Matrix,
	Wo: Matrix,
	forward: (self: MultiHeadAttentionClass, x: Matrix, mask: Matrix?) -> Matrix
}

local MHA = {}
MHA.__index = MHA

function MHA.new(dModel: number, numHeads: number): MultiHeadAttentionClass
	local self = setmetatable({}, MHA)
	self.dModel = dModel
	self.numHeads = numHeads
	self.dHead = dModel // numHeads

	self.Wq = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)
	self.Wk = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)
	self.Wv = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)
	self.Wo = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)

	return self
end

local function splitHeads(X: Matrix, numHeads: number, dHead: number): {Matrix}
	local seqLen = #X
	local heads = {}
	for h = 1, numHeads do
		heads[h] = {}
		for i = 1, seqLen do
			local row = {}
			for d = 1, dHead do
				local col = (h - 1)*dHead + d
				row[d] = X[i][col]
			end
			heads[h][i] = row
		end
	end
	return heads
end

local function mergeHeads(heads: {Matrix}, numHeads: number, dHead: number): Matrix
	local seqLen = #heads[1]
	local merged: Matrix = {}
	for i = 1, seqLen do
		merged[i] = {}
		for h = 1, numHeads do
			for d = 1, dHead do
				table.insert(merged[i], heads[h][i][d])
			end
		end
	end
	return merged
end

local function scaledDotProductAttention(Q: Matrix, K: Matrix, V: Matrix, mask: Matrix?): Matrix
	local seqLen = #Q
	local dHead = #Q[1]

	-- QK^T
	local Kt = LinearAlgebra:transpose(K)
	local scores = LinearAlgebra:mm(Q, Kt)

	-- scale
	local scale = math.sqrt(dHead)
	for i = 1, seqLen do
		for j = 1, seqLen do
			scores[i][j] = scores[i][j] / scale
		end
	end

	-- mask (e.g., causal)
	if mask then
		for i = 1, seqLen do
			for j = 1, seqLen do
				if mask[i][j] < 0 then
					scores[i][j] = -1e9
				end
			end
		end
	end

	-- softmax
	local attn = LinearAlgebra:softmax(scores)
	-- attn x V
	local out = LinearAlgebra:mm(attn, V)
	return out
end

function MHA:forward(x: Matrix, mask: Matrix?): Matrix
	local seqLen = #x

	-- Project x into Q, K, V
	local Q = LinearAlgebra:mm(x, self.Wq)
	local K = LinearAlgebra:mm(x, self.Wk)
	local V = LinearAlgebra:mm(x, self.Wv)

	-- Split into heads
	local Q_heads = splitHeads(Q, self.numHeads, self.dHead)
	local K_heads = splitHeads(K, self.numHeads, self.dHead)
	local V_heads = splitHeads(V, self.numHeads, self.dHead)

	-- Attention per head
	local headsOut = {}
	for h = 1, self.numHeads do
		headsOut[h] = scaledDotProductAttention(Q_heads[h], K_heads[h], V_heads[h], mask)
	end

	-- Merge heads
	local merged = mergeHeads(headsOut, self.numHeads, self.dHead)

	-- Final linear
	local out = LinearAlgebra:mm(merged, self.Wo)
	return out
end

return MHA
