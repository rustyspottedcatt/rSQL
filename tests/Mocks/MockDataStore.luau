
local MockDataStore = {}
MockDataStore.__index = MockDataStore

function MockDataStore.new(initialData)
    local self = setmetatable({}, MockDataStore)
    self.data = initialData or {}
    return self
end

function MockDataStore:GetAsync(key)
    return self.data[key]
end

function MockDataStore:SetAsync(key, value)
    self.data[key] = value
end

function MockDataStore:UpdateAsync(key, transformFunction)
    local currentValue = self:GetAsync(key)
    local newValue = transformFunction(currentValue)
    self:SetAsync(key, newValue)
    return newValue
end

function MockDataStore:RemoveAsync(key)
    self.data[key] = nil
end

function MockDataStore:Reset(initialData)
    self.data = initialData or {}
end

return MockDataStore
