--[[
    CrossEntropyLoss Module

    @module CrossEntropyLoss
    @type CrossEntropyLossClass
]]
local CrossEntropyLoss = {}
CrossEntropyLoss.__index = CrossEntropyLoss

-- Exported type for clarity (optional)
export type CrossEntropyLossClass = {
    new: () -> CrossEntropyLossClass,
    compute: (self: CrossEntropyLossClass, logits: { { number } }, targets: { number }) -> number,
    backward: (self: CrossEntropyLossClass, logits: { { number } }, targets: { number }) -> { { number } },
}

-- Constructor for CrossEntropyLoss
function CrossEntropyLoss.new(): CrossEntropyLossClass
    local self = setmetatable({}, CrossEntropyLoss)
    self.loss = 0
    self.probs = {}  -- Stores softmax probabilities for each sample
    self.grad = {}   -- Stores gradients w.r.t logits
    return self
end

-- Helper function to compute softmax for a single row of logits
local function softmax(logits: { number }): { number }
    local maxLogit = -math.huge
    -- Find the maximum logit for numerical stability
    for _, logit in ipairs(logits) do
        if logit > maxLogit then
            maxLogit = logit
        end
    end

    local sumExp = 0
    local probs = {}
    -- Compute exponentials and sum
    for _, logit in ipairs(logits) do
        local expVal = math.exp(logit - maxLogit)
        table.insert(probs, expVal)
        sumExp += expVal
    end

    -- Normalize to get probabilities
    for i, prob in ipairs(probs) do
        probs[i] = prob / sumExp
    end

    return probs
end

-- Computes the cross-entropy loss
-- @param logits { { number } } - The raw output logits from the model for each sample
-- @param targets { number } - The target class indices for each sample
-- @return number - The total cross-entropy loss over all samples
function CrossEntropyLoss:compute(logits: { { number } }, targets: { number }): number
    self.loss = 0
    self.probs = {}  -- Reset probabilities for the current batch

    for i, logitRow in ipairs(logits) do
        -- Compute softmax probabilities for the current sample
        local probs = softmax(logitRow)
        self.probs[i] = probs  -- Store for backward pass

        -- Retrieve the target class index
        local target = targets[i]

        -- Validate target presence and range
        if target == nil then
            error(string.format("Target at index %d is nil. Logits: %s", i, table.concat(logitRow, ", ")))
        end
        if type(target) ~= "number" then
            error(string.format("Target at index %d is not a number. Logits: %s", i, table.concat(logitRow, ", ")))
        end
        if target < 1 or target > #logitRow then
            error(string.format("Target at index %d is out of range. Target: %d, Logit Row Size: %d", i, target, #logitRow))
        end

        -- Retrieve the probability of the target class
        local targetProb = probs[target]

        -- Validate probability positivity
        if targetProb <= 0 then
            error(string.format("Probability at index %d for target %d is not positive. Probability: %f", i, target, targetProb))
        end

        -- Accumulate the negative log probability
        self.loss += -math.log(targetProb)
    end

    return self.loss
end

-- Computes the gradient of the loss w.r.t logits
-- @param logits { { number } } - The raw output logits from the model for each sample
-- @param targets { number } - The target class indices for each sample
-- @return { { number } } - The gradient of the loss w.r.t each logit
function CrossEntropyLoss:backward(logits: { { number } }, targets: { number }): { { number } }
    self.grad = {}

    for i, logitRow in ipairs(logits) do
        self.grad[i] = {}
        local probs = self.probs[i]
        local target = targets[i]

        for j, prob in ipairs(probs) do
            if j == target then
                -- Gradient for the target class
                self.grad[i][j] = prob - 1
            else
                -- Gradient for non-target classes
                self.grad[i][j] = prob
            end
        end
    end

    return self.grad
end

return CrossEntropyLoss
