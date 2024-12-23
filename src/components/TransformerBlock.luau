--[[
    TransformerBlock Module

    @module TransformerBlock
    @type TransformerBlockClass
]]

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
    forward: (self: TransformerBlockClass, x: Matrix, mask: Matrix?) -> Matrix,
    backward: (self: TransformerBlockClass, gradOutput: Matrix) -> Matrix,
    getParameters: (self: TransformerBlockClass) -> { mha: MultiHeadAttention.MultiHeadAttentionClass, ff: FeedForward.FeedForwardClass, norm1: LayerNorm.LayerNormClass, norm2: LayerNorm.LayerNormClass },
    setParameters: (self: TransformerBlockClass, params: { mha: MultiHeadAttention.MultiHeadAttentionClass, ff: FeedForward.FeedForwardClass, norm1: LayerNorm.LayerNormClass, norm2: LayerNorm.LayerNormClass }) -> any,
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
    -- Self-attention
    local attnOut = self.mha:forward(x, mask)

    -- Add & Norm
    local x2 = {}
    for i = 1, #x do
        x2[i] = {}
        for j = 1, self.dModel do
            x2[i][j] = x[i][j] + attnOut[i][j]
        end
    end
    x2 = self.norm1:forward(x2)

    -- Feed Forward
    local ffOut = self.ff:forward(x2)

    -- Add & Norm
    local x3 = {}
    for i = 1, #x2 do
        x3[i] = {}
        for j = 1, self.dModel do
            x3[i][j] = x2[i][j] + ffOut[i][j]
        end
    end
    x3 = self.norm2:forward(x3)

    -- Cache for backward pass
    self.cache = {
        x = x,
        attnOut = attnOut,
        x2 = x2,
        ffOut = ffOut,
        x3 = x3,
    }

    return x3
end

function TransformerBlock:backward(gradOutput: Matrix): Matrix
    -- Backward pass for TransformerBlock
    -- This is a placeholder. Implementing full backward pass requires backprop through norm2, ff, norm1, and mha

    -- Backprop through Add & Norm2
    local gradFF = self.norm2:backward(self.cache.x2, gradOutput)
    local gradX2 = self.ff:backward(gradFF)

    -- Backprop through Add & Norm1
    local gradAttn = self.norm1:backward(self.cache.x, gradX2)
    local gradX = self.mha:backward(gradAttn)

    -- Backprop through Self-attention
    -- Additional steps would be needed to backprop through MHA's attention mechanism

    return gradX
end

function TransformerBlock:getParameters(): { mha: MultiHeadAttention.MultiHeadAttentionClass, ff: FeedForward.FeedForwardClass, norm1: LayerNorm.LayerNormClass, norm2: LayerNorm.LayerNormClass }
    return {
        mha = self.mha,
        ff = self.ff,
        norm1 = self.norm1,
        norm2 = self.norm2,
    }
end

function TransformerBlock:setParameters(params: { mha: MultiHeadAttention.MultiHeadAttentionClass, ff: FeedForward.FeedForwardClass, norm1: LayerNorm.LayerNormClass, norm2: LayerNorm.LayerNormClass }): any
    self.mha = params.mha
    self.ff = params.ff
    self.norm1 = params.norm1
    self.norm2 = params.norm2
end

return TransformerBlock
