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
local Optimizer = require(script.lib.Optimizer)
local CrossEntropyLoss = require(script.lib.CrossEntropyLoss)

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

--[=[
    @function chunkString
    @within RoLLM
    @param bigString string - The string to be chunked.
    @param chunkSize number - The size of each chunk.
    @return {string} - A table containing string chunks.
]=]
local function chunkString(bigString: string, chunkSize: number): { string }
    local chunks: { string } = {}
    local idx = 1
    while idx <= #bigString do
        local chunk = string.sub(bigString, idx, idx + chunkSize - 1)
        table.insert(chunks, chunk)
        idx += chunkSize
    end
    return chunks
end

--[=[
    Creates a "ready-to-use" LLM instance with a tokenizer and model.

    @function new
    @within RoLLM
    @param textData string | {string} - Text data for building the vocabulary.
    @param config Types.TransformerConfig - Configuration table for the Transformer.
    @param chunkSize number? - Optional chunk size for processing text.
    @return {any} - An LLM object with prediction, generation, and training methods.
]=]
function RoLLM.new(
    textData: string | { string },
    config: Types.TransformerConfig,
    chunkSize: number?
): { any }
    chunkSize = chunkSize or 500000
    local tokenizerMode: string = config.tokenizerMode or "char"

    local tokenizer: typeof(Tokenizer.new("char"))
    if tokenizerMode == "char" then
        tokenizer = CharTokenizer.new()
    else
        tokenizer = BPETokenizer.new()
        if config.externalVocabURL then
            tokenizer:loadExternalVocab(config.externalVocabURL)
        end
    end

    local function addTextForChar(str: string): any
		if tokenizerMode == "char" then
        	tokenizer:buildVocabFromText(str)
		else
			tokenizer:textToTokens(str);
		end
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
            if #textData > chunkSize then
                local chunks = chunkString(textData, chunkSize)
                for _, chunk in ipairs(chunks) do
                    addTextForChar(chunk)
                end
            else
                addTextForChar(textData)
            end
        end
    else
		if #textData > chunkSize then
			local chunks = chunkString(textData, chunkSize)
			for _, chunk in ipairs(chunks) do
				addTextForChar(chunk)
			end
		else
			addTextForChar(textData)
		end
    end

    local vocabSize: number = tokenizer:getVocabSize()
    if vocabSize == 0 then
        error("Vocab size is 0. Did you load data or external vocab properly?")
    end
    config.vocabSize = vocabSize
    print("Final vocab size:", vocabSize)

    local model: TransformerModel.TransformerModelClass = TransformerModel.new(config)

    local self = {}

    local function textToTokens(str: string): { number }
        return tokenizer:textToTokens(str)
    end

    local function tokensToText(toks: { number }): string
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

    --[=[
        Trains the Transformer model using provided training data.

        @function trainModel
        @within RoLLM
        @param trainingData {string} - A table of training strings.
        @param epochs number - Number of training epochs.
        @param learningRate number - Learning rate for the optimizer.
        @return nil
    ]=]
	function self:trainModel(trainingData: { string }, epochs: number, learningRate: number): any
		local optimizerInstance = Optimizer.new(learningRate)
		local lossFunction = CrossEntropyLoss.new()
	
		print(string.format("Starting Training: %d epochs, Learning Rate: %f", epochs, learningRate))
	
		for epoch = 1, epochs do
			local totalLoss = 0
			for _, data in ipairs(trainingData) do
				local tokens = textToTokens(data)
	
				if #tokens < 2 then
					error(string.format("Input sequence is too short for training. Tokens: %s", table.concat(tokens, ", ")))
				end
	
				print(string.format("Input tokens for training: %s", table.concat(tokens, ", ")))
	
				local logits = model:forward(tokens)
	
				local targets = {}
				for i = 2, #tokens do
					table.insert(targets, tokens[i])
				end
	
				print(string.format("Generated targets: %s", table.concat(targets, ", ")))
	
				local loss = lossFunction:compute(logits, targets)
				totalLoss += loss
	
				local gradOutput = lossFunction:backward(logits, targets)
				model:backward(gradOutput)
	
				optimizerInstance:updateParameters(model:getParameters())
			end
			print(string.format("Epoch %d/%d, Loss: %.4f", epoch, epochs, totalLoss))
		end
	
		print("Training Completed.")
	end	
	
    self._tokenizer = tokenizer
    self._model = model

    return self
end

return RoLLM
