--[[
    https://www.roblox.com/users/1539582829/profile
    https://twitter.com/zzen_a

    MIT License

    Copyright (c) 2024 rustyspotted

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

local Types = require(script.lib.types)

local LinearAlgebra = require(script.components.LinearAlgebra)
local Tokenizer = require(script.components.Tokenizer)
local Embedding = require(script.components.Embedding)
local MultiHeadAttention = require(script.components.MultiHeadAttention)
local FeedForward = require(script.components.FeedForward)
local LayerNorm = require(script.components.LayerNorm)
local TransformerBlock = require(script.components.TransformerBlock)
local TransformerModel = require(script.components.TransformerModel)
local CharTokenizer = require(script.components.CharTokenizer)
local BPETokenizer = require(script.components.BPETokenizer)

local RoLLM = {}

--[=[
	@prop Presets Folder
	@within RoLLM
	@readonly
	References the Presets folder. 
]=]

RoLLM.Presets = (script.Parent :: Instance)
RoLLM.Promise = require(RoLLM.Presets.promise)
RoLLM.Signal = require(RoLLM.Presets.signal)
RoLLM.Types = Types
RoLLM.LinearAlgebra = LinearAlgebra
RoLLM.Tokenizer = Tokenizer
RoLLM.Embedding = Embedding
RoLLM.MultiHeadAttention = MultiHeadAttention
RoLLM.FeedForward = FeedForward
RoLLM.LayerNorm = LayerNorm
RoLLM.TransformerBlock = TransformerBlock
RoLLM.TransformerModel = TransformerModel
RoLLM.CharTokenizer = CharTokenizer
RoLLM.BPETokenizer = BPETokenizer

local function chunkString(bigString: string, chunkSize: number): {string}
	local chunks = {}
	local idx = 1
	while idx <= #bigString do
		local chunk = string.sub(bigString, idx, idx + chunkSize - 1)
		table.insert(chunks, chunk)
		idx += chunkSize
	end
	return chunks
end

--[[
    Creates a "ready-to-use" LLM instance with a tokenizer and model.

    textData (string):  
        - A chunk of text to build an initial vocabulary (for small demos). 
          E.g., "Hello world! This is my text for building a vocab."

    config (table): 
        - A config table for the Transformer, containing:
            vocabSize: number,
            dModel: number,
            numHeads: number,
            dFF: number,
            numLayers: number,
            maxSeqLen: number,
        - or any subset you want to customize.

    Returns: 
        A table (LLM object) with methods:
            :predict(inputStr) -> string
            :generate(inputStr, numTokens) -> string
            etc.
]]

function RoLLM.new(
	textData: string | {string}, 
	config: Types.TransformerConfig, 
	chunkSize: number?
): {any}
	chunkSize = chunkSize or 500000
	local tokenizerMode = config.tokenizerMode or "char"

	local tokenizer
	if tokenizerMode == "char" then
		tokenizer = CharTokenizer.new()
	else
		tokenizer = BPETokenizer.new()
		if config.externalVocabURL then
			tokenizer:loadExternalVocab(config.externalVocabURL)
		end
	end

	local function addTextForChar(str: string)
		(tokenizer).buildVocabFromText(tokenizer, str)
	end

	if tokenizerMode == "char" then
		if type(textData) == "table" then
			for _, singleString in ipairs(textData) do
				if #singleString > chunkSize then
					local chunks = chunkString(singleString, chunkSize)
					for _, chunk in ipairs(chunks) do
						addTextForChar(chunk)
					end
				else
					addTextForChar(singleString)
				end
			end
		else
			-- single string
			if #textData > chunkSize then
				local chunks = chunkString(textData, chunkSize)
				for _, chunk in ipairs(chunks) do
					addTextForChar(chunk)
				end
			else
				addTextForChar(textData)
			end
		end
	end

	-- 3) Now we have a vocab size
	local vocabSize = tokenizer:getVocabSize()
	if vocabSize == 0 then
		error("Vocab size is 0. Did you load data or external vocab properly?")
	end
	config.vocabSize = vocabSize
	print("Final vocab size:", vocabSize)

	-- 4) Create the TransformerModel
	local model = TransformerModel.new(config)

	-- 5) Build user-facing LLM object
	local self = {}

	local function textToTokens(str: string): {number}
		return tokenizer:textToTokens(str)
	end
	local function tokensToText(toks: {number}): string
		return tokenizer:tokensToText(toks)
	end

	function self:predict(inputStr: string): string
		local tokens = textToTokens(inputStr)
		local nextID = model:predictNextToken(tokens)
		return tokensToText({ nextID })
	end

	function self:generate(inputStr: string, numTokens: number): string
		local tokens = textToTokens(inputStr)
		for _ = 1, numTokens do
			local nxt = model:predictNextToken(tokens)
			table.insert(tokens, nxt)
		end
		return tokensToText(tokens)
	end

	function self:predictTemperature(inputStr: string, temperature: number): string
		local tokens = textToTokens(inputStr)
		local nextID = model:predictNextTokenTemperature(tokens, temperature)
		return tokensToText({ nextID })
	end

	function self:generateTemperature(inputStr: string, numTokens: number, temperature: number): string
		local tokens = textToTokens(inputStr)
		for _ = 1, numTokens do
			local nxt = model:predictNextTokenTemperature(tokens, temperature)
			table.insert(tokens, nxt)
		end
		return tokensToText(tokens)
	end

	self._tokenizer = tokenizer
	self._model = model

	return self
end

return RoLLM