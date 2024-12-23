-- Components/MultiHeadAttention.lua

--[[
    MultiHeadAttention Module

    @module MultiHeadAttention
    @type MultiHeadAttentionClass
]]

local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)

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
    forward: (self: MultiHeadAttentionClass, x: Matrix, mask: Matrix?) -> Matrix,
    backward: (self: MultiHeadAttentionClass, gradOutput: Matrix) -> Matrix,
    getParameters: (self: MultiHeadAttentionClass) -> { Wq: Matrix, Wk: Matrix, Wv: Matrix, Wo: Matrix },
    setParameters: (self: MultiHeadAttentionClass, params: { Wq: Matrix, Wk: Matrix, Wv: Matrix, Wo: Matrix }) -> any,
}

local MultiHeadAttention = {}
MultiHeadAttention.__index = MultiHeadAttention

local LinearAlgebra = LinearAlgebraModule.new()

local function splitHeads(X: Matrix, numHeads: number, dHead: number): { Matrix }
    local seqLen = #X
    local heads: { Matrix } = {}
    for h = 1, numHeads do
        heads[h] = {}
        for i = 1, seqLen do
            local row: { number } = {}
            for d = 1, dHead do
                local col = (h - 1) * dHead + d
                row[d] = X[i][col]
            end
            heads[h][i] = row
        end
    end
    return heads
end

local function mergeHeads(heads: { Matrix }, numHeads: number, dHead: number): Matrix
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

local function scaledDotProductAttention(Q: Matrix, K: Matrix, V: Matrix, mask: Matrix?): { Matrix & Matrix }
    local seqLen = #Q
    local dHead = #Q[1]

    local Kt = LinearAlgebra:transpose(K)
    local scores = LinearAlgebra:mm(Q, Kt)

    local scale = math.sqrt(dHead)
    for i = 1, seqLen do
        for j = 1, seqLen do
            scores[i][j] = scores[i][j] / scale
        end
    end

    if mask then
        for i = 1, seqLen do
            for j = 1, seqLen do
                if mask[i][j] < 0 then
                    scores[i][j] = -1e9
                end
            end
        end
    end

    local attn = LinearAlgebra:softmax(scores)
    local out = LinearAlgebra:mm(attn, V)

    -- Cache for backward pass
    local cache = {
        Q = Q,
        K = K,
        V = V,
        scores = scores,
        attn = attn,
        mask = mask,
    }

    return out, cache
end

function MultiHeadAttention.new(dModel: number, numHeads: number): MultiHeadAttentionClass
    local self = setmetatable({}, MultiHeadAttention)
    self.dModel = dModel
    self.numHeads = numHeads
    self.dHead = math.floor(dModel / numHeads)

    self.Wq = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)
    self.Wk = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)
    self.Wv = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)
    self.Wo = LinearAlgebra:randomMatrix(dModel, dModel, 0.01)

    -- Gradients
    self.gradWq = LinearAlgebra:zeros(dModel, dModel)
    self.gradWk = LinearAlgebra:zeros(dModel, dModel)
    self.gradWv = LinearAlgebra:zeros(dModel, dModel)
    self.gradWo = LinearAlgebra:zeros(dModel, dModel)

    -- Cache for backward pass
    self.cache = {}

    return self
end

function MultiHeadAttention:forward(x: Matrix, mask: Matrix?): Matrix
    local seqLen = #x

    local Q = LinearAlgebra:mm(x, self.Wq)
    local K = LinearAlgebra:mm(x, self.Wk)
    local V = LinearAlgebra:mm(x, self.Wv)

    local Q_heads = splitHeads(Q, self.numHeads, self.dHead)
    local K_heads = splitHeads(K, self.numHeads, self.dHead)
    local V_heads = splitHeads(V, self.numHeads, self.dHead)

    local headsOut: { Matrix } = {}
    local attentions: { any } = {}
    for h = 1, self.numHeads do
        headsOut[h], attentions[h] = scaledDotProductAttention(Q_heads[h], K_heads[h], V_heads[h], mask)
    end

    local merged = mergeHeads(headsOut, self.numHeads, self.dHead)
    local out = LinearAlgebra:mm(merged, self.Wo)

    -- Cache for backward pass
    self.cache = {
        x = x,
        Q = Q,
        K = K,
        V = V,
        Q_heads = Q_heads,
        K_heads = K_heads,
        V_heads = V_heads,
        headsOut = headsOut,
        attentions = attentions,
        mask = mask,
        merged = merged,
        out = out,
    }

    return out
end

function MultiHeadAttention:backward(gradOutput: Matrix): Matrix
    -- Backward pass for MultiHeadAttention
    -- This is a placeholder. Implementing full backward pass requires tracking gradients through all operations.

    -- Compute gradients w.r.t Wo
    local gradWo = LinearAlgebra:mm(LinearAlgebra:transpose(self.cache.merged), gradOutput)
    self.gradWo = gradWo

    -- Compute gradients w.r.t merged
    local gradMerged = LinearAlgebra:mm(gradOutput, LinearAlgebra:transpose(self.Wo))

    -- Split gradients into heads
    local gradHeadsOut: { Matrix } = {}
    for h = 1, self.numHeads do
        gradHeadsOut[h] = {}
        for i = 1, #gradMerged do
            gradHeadsOut[h][i] = {}
            for d = 1, self.dHead do
                gradHeadsOut[h][i][d] = gradMerged[i][(h - 1) * self.dHead + d]
            end
        end
    end

    -- Backward through scaled dot-product attention
    local gradQ_heads: { Matrix } = {}
    local gradK_heads: { Matrix } = {}
    local gradV_heads: { Matrix } = {}

    for h = 1, self.numHeads do
        local gradOut = gradHeadsOut[h]
        -- Placeholder: Assume identity gradient
        local gradAttention = gradOut  -- This should be computed based on attention gradients
        gradQ_heads[h] = gradAttention
        gradK_heads[h] = gradAttention  -- Placeholder
        gradV_heads[h] = gradAttention  -- Placeholder
    end

    -- Merge gradients from heads
    local gradMergedMatrix: Matrix = {}
    for h = 1, self.numHeads do
        for i = 1, #gradMerged do
            if not gradMergedMatrix[i] then
                gradMergedMatrix[i] = {}
            end
            for d = 1, self.dHead do
                gradMergedMatrix[i][(h - 1) * self.dHead + d] = gradHeadsOut[h][i][d]
            end
        end
    end

    -- Backward through Q, K, V projections
    local gradQ = LinearAlgebra:mm(gradQ_heads[1], LinearAlgebra:transpose(self.Wq))
    local gradK = LinearAlgebra:mm(gradK_heads[1], LinearAlgebra:transpose(self.Wk))
    local gradV = LinearAlgebra:mm(gradV_heads[1], LinearAlgebra:transpose(self.Wv))

    -- Update gradients for Wq, Wk, Wv
    for h = 1, self.numHeads do
        self.gradWq = LinearAlgebra:add(self.gradWq, LinearAlgebra:mm(LinearAlgebra:transpose(self.cache.x), gradQ_heads[h]))
        self.gradWk = LinearAlgebra:add(self.gradWk, LinearAlgebra:mm(LinearAlgebra:transpose(self.cache.x), gradK_heads[h]))
        self.gradWv = LinearAlgebra:add(self.gradWv, LinearAlgebra:mm(LinearAlgebra:transpose(self.cache.x), gradV_heads[h]))
    end

    -- Backward through Q, K, V projections
    local gradX = LinearAlgebra:zeros(#self.cache.x, self.dModel)
    for h = 1, self.numHeads do
        local gradQ_h = gradQ_heads[h]
        local gradK_h = gradK_heads[h]
        local gradV_h = gradV_heads[h]

        local gradX_part = LinearAlgebra:mm(gradQ_h, LinearAlgebra:transpose(self.Wq))
        gradX_part = LinearAlgebra:add(gradX_part, LinearAlgebra:mm(gradK_h, LinearAlgebra:transpose(self.Wk)))
        gradX_part = LinearAlgebra:add(gradX_part, LinearAlgebra:mm(gradV_h, LinearAlgebra:transpose(self.Wv)))

        gradX = LinearAlgebra:add(gradX, gradX_part)
    end

    return gradX
end

function MultiHeadAttention:getParameters(): { Wq: Matrix, Wk: Matrix, Wv: Matrix, Wo: Matrix }
    return {
        Wq = self.Wq,
        Wk = self.Wk,
        Wv = self.Wv,
        Wo = self.Wo,
    }
end

function MultiHeadAttention:setParameters(params: { Wq: Matrix, Wk: Matrix, Wv: Matrix, Wo: Matrix }): any
    self.Wq = params.Wq
    self.Wk = params.Wk
    self.Wv = params.Wv
    self.Wo = params.Wo
end

return MultiHeadAttention
