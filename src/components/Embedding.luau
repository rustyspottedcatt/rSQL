--[[
    Embedding Module

    @module Embedding
    @type EmbeddingClass
]]

local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)

export type Matrix = Types.Matrix

export type EmbeddingClass = {
    new: (vocabSize: number, dModel: number, maxSeqLen: number?) -> EmbeddingClass,
    vocabSize: number,
    dModel: number,
    tokenEmb: Matrix,
    posEmb: Matrix?,
    forward: (self: EmbeddingClass, tokens: { number }, positions: { number }?) -> Matrix,
    backward: (self: EmbeddingClass, gradOutput: Matrix ) -> { tokensGrad: { number }, positionsGrad: Matrix? },
    getParameters: (self: EmbeddingClass) -> { tokenEmb: Matrix, posEmb: Matrix? },
    setParameters: (self: EmbeddingClass, params: { tokenEmb: Matrix, posEmb: Matrix? }) -> any,
}

local Embedding = {}
Embedding.__index = Embedding

local LinearAlgebra = LinearAlgebraModule.new()

function Embedding.new(vocabSize: number, dModel: number, maxSeqLen: number?): EmbeddingClass
    local self = setmetatable({}, Embedding)
    self.vocabSize = vocabSize
    self.dModel = dModel

    self.tokenEmb = LinearAlgebra:randomMatrix(vocabSize, dModel, 0.01)

    if maxSeqLen then
        self.posEmb = LinearAlgebra:randomMatrix(maxSeqLen, dModel, 0.01)
    end

    -- Cache for backward pass
    self.cache = {}

    return self
end

function Embedding:forward(tokens: { number }, positions: { number }?): Matrix
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

    -- Store cache for backward pass
    self.cache = {
        tokens = tokens,
        positions = positions,
    }

    return output
end

function Embedding:backward(gradOutput: Matrix): { tokensGrad: { number }, positionsGrad: Matrix? }
    local seqLen = #gradOutput
    local tokensGrad: { number } = {}
    local positionsGrad: Matrix? = nil

    if self.posEmb then
        positionsGrad = LinearAlgebra:zeros(#self.posEmb, self.dModel)
    end

    -- Initialize gradients
    for i = 1, self.vocabSize do
        tokensGrad[i] = 0
    end

    if self.posEmb then
        for i = 1, #self.posEmb do
            for d = 1, self.dModel do
                positionsGrad[i][d] = 0
            end
        end
    end

    -- Accumulate gradients
    for i = 1, seqLen do
        local tokenID = self.cache.tokens[i]
        for d = 1, self.dModel do
            tokensGrad[tokenID] += gradOutput[i][d]
            if self.posEmb and self.cache.positions then
                local posID = self.cache.positions[i]
                positionsGrad[posID][d] += gradOutput[i][d]
            end
        end
    end

    -- Gradient w.r.t tokenEmb and posEmb
    for i = 1, self.vocabSize do
        for d = 1, self.dModel do
            self.tokenEmb[i][d] += tokensGrad[i]  -- Assuming gradient descent with learning rate incorporated elsewhere
        end
    end

    if self.posEmb and positionsGrad then
        for i = 1, #self.posEmb do
            for d = 1, self.dModel do
                self.posEmb[i][d] += positionsGrad[i][d]  -- Assuming gradient descent with learning rate incorporated elsewhere
            end
        end
    end

    return { tokensGrad = tokensGrad, positionsGrad = positionsGrad }
end

function Embedding:getParameters(): { tokenEmb: Matrix, posEmb: Matrix? }
    return {
        tokenEmb = self.tokenEmb,
        posEmb = self.posEmb,
    }
end

function Embedding:setParameters(params: { tokenEmb: Matrix, posEmb: Matrix? }): any
    self.tokenEmb = params.tokenEmb
    self.posEmb = params.posEmb
end

return Embedding
