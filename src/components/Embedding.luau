local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)

export type Matrix = Types.Matrix
export type LinearAlgebraClass = LinearAlgebraModule.LinearAlgebraClass

export type EmbeddingClass = {
	new: (vocabSize: number, dModel: number, maxSeqLen: number?) -> EmbeddingClass,
	vocabSize: number,
	dModel: number,
	tokenEmb: Matrix,
	posEmb: Matrix?,
	forward: (self: EmbeddingClass, tokens: {number}, positions: {number}?) -> Matrix
}

local Embedding = {}
Embedding.__index = Embedding

local LinearAlgebra = LinearAlgebraModule.new()

function Embedding.new(vocabSize: number, dModel: number, maxSeqLen: number?): EmbeddingClass
	local self = setmetatable({}, Embedding)
	self.vocabSize = vocabSize
	self.dModel = dModel

	-- token embeddings: (vocabSize x dModel)
	self.tokenEmb = LinearAlgebra:randomMatrix(vocabSize, dModel, 0.01)

	if maxSeqLen then
		self.posEmb = LinearAlgebra:randomMatrix(maxSeqLen, dModel, 0.01)
	end

	return self
end

-- forward: convert tokens to embeddings + optional positional embeddings
function Embedding:forward(tokens: {number}, positions: {number}?): Matrix
	local seqLen = #tokens
	local output: Matrix = {}

	for i = 1, seqLen do
		output[i] = {}
		local tokenID = tokens[i]

		for d = 1, self.dModel do
			local val = self.tokenEmb[tokenID][d]
			if self.posEmb and positions then
				local posID = positions[i]
				val += self.posEmb[posID][d]
			end
			output[i][d] = val
		end
	end

	return output
end

return Embedding
