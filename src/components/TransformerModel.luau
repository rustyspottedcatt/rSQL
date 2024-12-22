local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)
local Embedding = require(script.Parent.Embedding)
local TransformerBlock = require(script.Parent.TransformerBlock)

export type Matrix = Types.Matrix
export type TransformerConfig = Types.TransformerConfig

local LinearAlgebra = LinearAlgebraModule.new()

export type TransformerModelClass = {
	new: (config: TransformerConfig) -> TransformerModelClass,
	vocabSize: number,
	dModel: number,
	numLayers: number,
	blocks: {any},
	embedding: any,
	finalProj: Matrix,
	forward: (self: TransformerModelClass, tokens: {number}) -> Matrix,
	predictNextToken: (self: TransformerModelClass, tokens: {number}) -> number,
	predictNextTokenTemperature: (self: TransformerModelClass, tokens: {number}, temperature: number) -> number
}

local TransformerModel = {}
TransformerModel.__index = TransformerModel

function TransformerModel.new(config: TransformerConfig): TransformerModelClass
	local self = setmetatable({}, TransformerModel)

	self.vocabSize = config.vocabSize or 0
	self.dModel = config.dModel
	self.numLayers = config.numLayers or 2

	-- Create embedding
	self.embedding = Embedding.new(self.vocabSize, self.dModel, config.maxSeqLen)

	-- Create multiple blocks
	self.blocks = {}
	for i = 1, config.numLayers do
		self.blocks[i] = TransformerBlock.new(config.dModel, config.numHeads, config.dFF)
	end

	-- Final projection from dModel -> vocabSize
	self.finalProj = LinearAlgebra:randomMatrix(config.dModel, self.vocabSize, 0.01)

	return self
end

-- Forward pass: tokens -> logits
function TransformerModel:forward(tokens: {number}): Matrix
	local seqLen = #tokens

	-- positions
	local positions = {}
	for i = 1, seqLen do
		positions[i] = i
	end

	-- 1) Embedding => (seqLen x dModel)
	local x = self.embedding:forward(tokens, positions)

	-- 2) Build causal mask for language modeling
	local mask = LinearAlgebra:zeros(seqLen, seqLen)
	for i = 1, seqLen do
		for j = 1, seqLen do
			if j > i then
				mask[i][j] = -1e9
			end
		end
	end

	-- 3) Pass through blocks
	for _, block in ipairs(self.blocks) do
		x = block:forward(x, mask)
	end

	-- 4) Final projection => (seqLen x vocabSize)
	local logits = LinearAlgebra:mm(x, self.finalProj)
	return logits
end

-- Deterministic (argmax)
function TransformerModel:predictNextToken(tokens: {number}): number
	local logits = self:forward(tokens)
	local seqLen = #logits
	local lastLogits = logits[seqLen]  -- 1D array of length vocabSize

	local maxVal = -1e9
	local maxIndex = 1
	for i, val in ipairs(lastLogits) do
		if val > maxVal then
			maxVal = val
			maxIndex = i
		end
	end
	return maxIndex
end

-- Temperature-based sampling
function TransformerModel:predictNextTokenTemperature(tokens: {number}, temperature: number): number
	local logits = self:forward(tokens)
	local seqLen = #logits
	local lastLogits = logits[seqLen]
	local vocabSize = #lastLogits

	-- If near-zero temperature, just do argmax
	if temperature < 1e-7 then
		local maxVal = -1e9
		local maxIndex = 1
		for i, val in ipairs(lastLogits) do
			if val > maxVal then
				maxVal = val
				maxIndex = i
			end
		end
		return maxIndex
	end

	-- Apply temperature scaling
	local scaled = {}
	local maxLogit = -1e9
	for i = 1, vocabSize do
		local val = lastLogits[i] / temperature
		scaled[i] = val
		if val > maxLogit then
			maxLogit = val
		end
	end

	-- Softmax
	local sumExp = 0
	for i = 1, vocabSize do
		scaled[i] = math.exp(scaled[i] - maxLogit)
		sumExp += scaled[i]
	end
	for i = 1, vocabSize do
		scaled[i] = scaled[i] / sumExp
	end

	-- Sample
	local randVal = math.random()
	local cumulative = 0
	for i = 1, vocabSize do
		cumulative += scaled[i]
		if randVal <= cumulative then
			return i
		end
	end
	return vocabSize
end

return TransformerModel
