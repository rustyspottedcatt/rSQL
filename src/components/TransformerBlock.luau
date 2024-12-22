local Types = require(script.Parent.Parent.lib.types)
local MultiHeadAttention = require(script.Parent.MultiHeadAttention)
local FeedForward = require(script.Parent.FeedForward)
local LayerNorm = require(script.Parent.LayerNorm)

export type Matrix = Types.Matrix

export type TransformerBlockClass = {
	new: (dModel: number, numHeads: number, dFF: number) -> TransformerBlockClass,
	dModel: number,
	mha: MultiHeadAttention.MultiHeadAttentionClass,
	ff: FeedForward.FeedForwardClass,
	norm1: LayerNorm.LayerNormClass,
	norm2: LayerNorm.LayerNormClass,
	forward: (self: TransformerBlockClass, x: Matrix, mask: Matrix?) -> Matrix
}

local TransformerBlock = {}
TransformerBlock.__index = TransformerBlock

function TransformerBlock.new(dModel: number, numHeads: number, dFF: number): TransformerBlockClass
	local self = setmetatable({}, TransformerBlock)
	self.dModel = dModel
	self.mha = MultiHeadAttention.new(dModel, numHeads)
	self.ff = FeedForward.new(dModel, dFF)
	self.norm1 = LayerNorm.new(dModel)
	self.norm2 = LayerNorm.new(dModel)
	return self
end

function TransformerBlock:forward(x: Matrix, mask: Matrix?): Matrix
	-- x: (seqLen x dModel)

	-- 1) MHA
	local attnOut = self.mha:forward(x, mask)

	-- 2) Residual + Norm
	local x2: Matrix = {}
	for i = 1, #x do
		x2[i] = {}
		for j = 1, self.dModel do
			x2[i][j] = x[i][j] + attnOut[i][j]
		end
	end
	x2 = self.norm1:forward(x2)

	-- 3) FF
	local ffOut = self.ff:forward(x2)

	-- 4) Residual + Norm
	local x3: Matrix = {}
	for i = 1, #x2 do
		x3[i] = {}
		for j = 1, self.dModel do
			x3[i][j] = x2[i][j] + ffOut[i][j]
		end
	end
	x3 = self.norm2:forward(x3)

	return x3
end

return TransformerBlock
