local Types = require(script.Parent.Parent.lib.types)

export type Matrix = Types.Matrix
export type Vector = Types.Vector

export type LinearAlgebraClass = {
	new: () -> LinearAlgebraClass,
	zeros: (self: LinearAlgebraClass, rows: number, cols: number) -> Matrix,
	randomMatrix: (self: LinearAlgebraClass, rows: number, cols: number, scale: number?) -> Matrix,
	mm: (self: LinearAlgebraClass, A: Matrix, B: Matrix) -> Matrix,
	add: (self: LinearAlgebraClass, A: Matrix, B: Matrix) -> Matrix,
	scale: (self: LinearAlgebraClass, A: Matrix, s: number) -> Matrix,
	transpose: (self: LinearAlgebraClass, A: Matrix) -> Matrix,
	softmax: (self: LinearAlgebraClass, A: Matrix) -> Matrix,
}

local LinearAlgebra = {}
LinearAlgebra.__index = LinearAlgebra

function LinearAlgebra.new(): LinearAlgebraClass
	local self = setmetatable({}, LinearAlgebra)
	return self
end

-- Creates a matrix of size (rows x cols) filled with zeros
function LinearAlgebra:zeros(rows: number, cols: number): Matrix
	local mat: Matrix = {}
	for i = 1, rows do
		local row = {}
		for j = 1, cols do
			row[j] = 0
		end
		mat[i] = row
	end
	return mat
end

-- Creates a matrix with random values in [-scale, scale]
function LinearAlgebra:randomMatrix(rows: number, cols: number, scale: number?): Matrix
	scale = scale or 0.1
	local mat: Matrix = {}
	for i = 1, rows do
		local row = {}
		for j = 1, cols do
			row[j] = (math.random() * 2 - 1) * scale
		end
		mat[i] = row
	end
	return mat
end

-- Matrix multiply: A (m x n) * B (n x p) => C (m x p)
function LinearAlgebra:mm(A: Matrix, B: Matrix): Matrix
	local m = #A
	local n = #A[1]
	local p = #B[1]

	local C = self:zeros(m, p)
	for i = 1, m do
		for j = 1, p do
			local sum = 0
			for k = 1, n do
				sum += A[i][k] * B[k][j]
			end
			C[i][j] = sum
		end
	end
	return C
end

-- Elementwise A + B
function LinearAlgebra:add(A: Matrix, B: Matrix): Matrix
	local rows = #A
	local cols = #A[1]
	local C = self:zeros(rows, cols)
	for i = 1, rows do
		for j = 1, cols do
			C[i][j] = A[i][j] + B[i][j]
		end
	end
	return C
end

-- Scale all elements of A by s
function LinearAlgebra:scale(A: Matrix, s: number): Matrix
	local rows = #A
	local cols = #A[1]
	local C = self:zeros(rows, cols)
	for i = 1, rows do
		for j = 1, cols do
			C[i][j] = A[i][j] * s
		end
	end
	return C
end

-- Transpose of A
function LinearAlgebra:transpose(A: Matrix): Matrix
	local rows = #A
	local cols = #A[1]
	local T = self:zeros(cols, rows)
	for i = 1, rows do
		for j = 1, cols do
			T[j][i] = A[i][j]
		end
	end
	return T
end

-- Softmax row-wise
function LinearAlgebra:softmax(A: Matrix): Matrix
	local rows = #A
	local cols = #A[1]
	local out = self:zeros(rows, cols)

	for i = 1, rows do
		local rowMax = -1e9
		for j = 1, cols do
			if A[i][j] > rowMax then
				rowMax = A[i][j]
			end
		end
		local sumExp = 0
		for j = 1, cols do
			out[i][j] = math.exp(A[i][j] - rowMax)
			sumExp += out[i][j]
		end
		for j = 1, cols do
			out[i][j] /= sumExp
		end
	end

	return out
end

return LinearAlgebra
