local Types = require(script.Parent.Parent.lib.types)
local LinearAlgebraModule = require(script.Parent.LinearAlgebra)

export type Matrix = Types.Matrix

export type LayerNormClass = {
	new: (dModel: number, eps: number?) -> LayerNormClass,
	dModel: number,
	eps: number,
	gamma: {number},
	beta: {number},
	forward: (self: LayerNormClass, x: Matrix) -> Matrix
}

local LayerNorm = {}
LayerNorm.__index = LayerNorm

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
	return self
end

function LayerNorm:forward(x: Matrix): Matrix
	local seqLen = #x
	local out: Matrix = {}

	for i = 1, seqLen do
		out[i] = {}
		local row = x[i]

		-- mean
		local mean = 0
		for j = 1, self.dModel do
			mean += row[j]
		end
		mean /= self.dModel

		-- var
		local var = 0
		for j = 1, self.dModel do
			local diff = row[j] - mean
			var += diff * diff
		end
		var /= self.dModel
		local std = math.sqrt(var + self.eps)

		-- normalized
		for j = 1, self.dModel do
			out[i][j] = ((row[j] - mean) / std) * self.gamma[j] + self.beta[j]
		end
	end

	return out
end

return LayerNorm
