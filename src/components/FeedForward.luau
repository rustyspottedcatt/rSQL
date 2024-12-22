local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)

local LinearAlgebra = LinearAlgebraModule.new()

export type Matrix = Types.Matrix

export type FeedForwardClass = {
	new: (dModel: number, dFF: number) -> FeedForwardClass,
	dModel: number,
	dFF: number,
	W1: Matrix,
	b1: Matrix,
	W2: Matrix,
	b2: Matrix,
	forward: (self: FeedForwardClass, x: Matrix) -> Matrix
}

local FeedForward = {}
FeedForward.__index = FeedForward

function FeedForward.new(dModel: number, dFF: number): FeedForwardClass
	local self = setmetatable({}, FeedForward)
	self.dModel = dModel
	self.dFF = dFF

	self.W1 = LinearAlgebra:randomMatrix(dModel, dFF, 0.01)
	self.b1 = LinearAlgebra:zeros(1, dFF)
	self.W2 = LinearAlgebra:randomMatrix(dFF, dModel, 0.01)
	self.b2 = LinearAlgebra:zeros(1, dModel)

	return self
end

local function relu(mat: Matrix): Matrix
	for i = 1, #mat do
		for j = 1, #mat[i] do
			mat[i][j] = math.max(0, mat[i][j])
		end
	end
	return mat
end

function FeedForward:forward(x: Matrix): Matrix
	-- x: (seqLen x dModel)
	local seqLen = #x

	-- xW1 + b1 => (seqLen x dFF)
	local hidden = LinearAlgebra:mm(x, self.W1)
	for i = 1, seqLen do
		for j = 1, self.dFF do
			hidden[i][j] += self.b1[1][j]
		end
	end

	hidden = relu(hidden)

	-- hiddenW2 + b2 => (seqLen x dModel)
	local out = LinearAlgebra:mm(hidden, self.W2)
	for i = 1, seqLen do
		for j = 1, self.dModel do
			out[i][j] += self.b2[1][j]
		end
	end

	return out
end

return FeedForward
