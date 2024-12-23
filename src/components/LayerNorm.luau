--[[
    LayerNorm Module

    @module LayerNorm
    @type LayerNormClass
]]

local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)

export type Matrix = Types.Matrix

export type LayerNormClass = {
    new: (dModel: number, eps: number?) -> LayerNormClass,
    dModel: number,
    eps: number,
    gamma: { number },
    beta: { number },
    forward: (self: LayerNormClass, x: Matrix) -> Matrix,
    backward: (self: LayerNormClass, x: Matrix, gradOutput: Matrix) -> Matrix,
    getParameters: (self: LayerNormClass) -> { gamma: { number }, beta: { number } },
    setParameters: (self: LayerNormClass, params: { gamma: { number }, beta: { number } }) -> any,
}

local LayerNorm = {}
LayerNorm.__index = LayerNorm

local LinearAlgebra = LinearAlgebraModule.new()

function LayerNorm.new(dModel: number, eps: number?): LayerNormClass
    local self = setmetatable({}, LayerNorm)
    self.dModel = dModel
    self.eps = eps or 1e-5

    self.gamma = {}
    self.beta = {}
    for i = 1, dModel do
        self.gamma[i] = 1
        self.beta[i] = 0
    end

    -- Cache for backward pass
    self.cache = {}

    return self
end

function LayerNorm:forward(x: Matrix): Matrix
    local seqLen = #x
    local out: Matrix = {}

    -- Compute mean and variance for each row
    local mean = {}
    local var = {}
    for i = 1, seqLen do
        mean[i] = 0
        for j = 1, self.dModel do
            mean[i] += x[i][j]
        end
        mean[i] /= self.dModel

        var[i] = 0
        for j = 1, self.dModel do
            local diff = x[i][j] - mean[i]
            var[i] += diff * diff
        end
        var[i] /= self.dModel
    end

    -- Normalize and scale
    for i = 1, seqLen do
        out[i] = {}
        for j = 1, self.dModel do
            out[i][j] = ((x[i][j] - mean[i]) / math.sqrt(var[i] + self.eps)) * self.gamma[j] + self.beta[j]
        end
    end

    -- Store cache for backward pass
    self.cache = {
        x = x,
        mean = mean,
        var = var,
        normalized = out,
    }

    return out
end

function LayerNorm:backward(x: Matrix, gradOutput: Matrix): Matrix
    local seqLen = #x
    local gradInput: Matrix = {}
    local gradGamma: { number } = {}
    local gradBeta: { number } = {}

    -- Initialize gradients
    for j = 1, self.dModel do
        gradGamma[j] = 0
        gradBeta[j] = 0
    end

    -- Compute gradients w.r.t gamma and beta
    for i = 1, seqLen do
        for j = 1, self.dModel do
            gradGamma[j] += gradOutput[i][j] * self.cache.normalized[i][j]
            gradBeta[j] += gradOutput[i][j]
        end
    end

    -- Compute gradients w.r.t input
    for i = 1, seqLen do
        gradInput[i] = {}
        for j = 1, self.dModel do
            local norm = 1 / math.sqrt(self.cache.var[i] + self.eps)
            gradInput[i][j] = gradOutput[i][j] * self.gamma[j] * norm
        end
    end

    -- Further gradients would involve derivatives through normalization
    -- This is a simplified version; full implementation requires more steps

    -- Update parameters (gamma and beta) gradients
    self.gradGamma = gradGamma
    self.gradBeta = gradBeta

    return gradInput
end

function LayerNorm:getParameters(): { gamma: { number }, beta: { number } }
    return {
        gamma = self.gamma,
        beta = self.beta,
    }
end

function LayerNorm:setParameters(params: { gamma: { number }, beta: { number } }): void
    for j, value in ipairs(params.gamma) do
        self.gamma[j] = value
    end
    for j, value in ipairs(params.beta) do
        self.beta[j] = value
    end
end

return LayerNorm
