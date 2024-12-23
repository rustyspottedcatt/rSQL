--[[
    Optimizer Module

    @module Optimizer
    @type OptimizerClass
]]

local Types = require(script.Parent.types)

export type OptimizerClass = {
    new: (learningRate: number, beta1: number?, beta2: number?, epsilon: number?) -> OptimizerClass,
    learningRate: number,
    beta1: number,
    beta2: number,
    epsilon: number,
    m: { [string]: { [number]: { [number]: number } } },
    v: { [string]: { [number]: { [number]: number } } },
    t: number,
    updateParameters: (self: OptimizerClass, parameters: { any }, learningRate: number) -> any,
}

local Optimizer = {}
Optimizer.__index = Optimizer

function Optimizer.new(learningRate: number, beta1: number?, beta2: number?, epsilon: number?): OptimizerClass
    local self = setmetatable({}, Optimizer)
    self.learningRate = learningRate
    self.beta1 = beta1 or 0.9
    self.beta2 = beta2 or 0.999
    self.epsilon = epsilon or 1e-8
    self.m = {}
    self.v = {}
    self.t = 0
    return self
end

function Optimizer:updateParameters(parameters: { any }, learningRate: number): void
    self.t += 1
    local lr = learningRate or self.learningRate

    for paramName, param in pairs(parameters) do
        if type(param) == "table" then
            if not self.m[paramName] then
                self.m[paramName] = {}
                self.v[paramName] = {}
                for i, row in ipairs(param) do
                    self.m[paramName][i] = {}
                    self.v[paramName][i] = {}
                    for j, _ in ipairs(row) do
                        self.m[paramName][i][j] = 0
                        self.v[paramName][i][j] = 0
                    end
                end
            end

            for i, row in ipairs(param) do
                for j, _ in ipairs(row) do
                    local grad = param.gradW and param.gradW[i][j] or 0  -- Adjust based on parameter type
                    self.m[paramName][i][j] = self.beta1 * self.m[paramName][i][j] + (1 - self.beta1) * grad
                    self.v[paramName][i][j] = self.beta2 * self.v[paramName][i][j] + (1 - self.beta2) * (grad * grad)

                    local mHat = self.m[paramName][i][j] / (1 - self.beta1 ^ self.t)
                    local vHat = self.v[paramName][i][j] / (1 - self.beta2 ^ self.t)

                    param[i][j] = param[i][j] - lr * mHat / (math.sqrt(vHat) + self.epsilon)
                end
            end
        elseif type(param) == "number" then
           
        end
    end
end

return Optimizer
