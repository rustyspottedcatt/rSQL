local HttpService = game:GetService("HttpService")

local BPETokenizer = {}
BPETokenizer.__index = BPETokenizer

function BPETokenizer.new()
	local self = setmetatable({}, BPETokenizer)
	self.vocab = {}    -- token -> ID
	self.ivocab = {}   -- ID -> token
	self.vocabSize = 0
	self.unknownToken = "<UNK>"
	return self
end

function BPETokenizer:loadExternalVocab(url: string)
	local success, result = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not success then
		error("Failed to fetch external vocab from URL: " .. tostring(result))
	end

	local successDecode, decodeResult = pcall(function()
		return HttpService:JSONDecode(result)
	end)
	if not successDecode then
		error("Failed to decode external vocab JSON.")
	end

	for token, tokenId in pairs(decodeResult) do
		self.vocab[token] = tokenId
		self.ivocab[tokenId] = token
	end

	-- ensure <UNK>
	if not self.vocab[self.unknownToken] then
		local maxID = 0
		for _, tid in pairs(self.vocab) do
			if tid > maxID then
				maxID = tid
			end
		end
		local newID = maxID + 1
		self.vocab[self.unknownToken] = newID
		self.ivocab[newID] = self.unknownToken
	end

	-- figure out vocab size
	local highest = 0
	for _, tid in pairs(self.vocab) do
		if tid > highest then
			highest = tid
		end
	end
	self.vocabSize = highest
end

function BPETokenizer:getVocabSize(): number
	return self.vocabSize
end

function BPETokenizer:textToTokens(text: string): {number}
	local tokens = {}
	for word in text:gmatch("%S+") do
		local id = self.vocab[word]
		if not id then
			id = self.vocab[self.unknownToken]
		end
		table.insert(tokens, id)
	end
	return tokens
end

function BPETokenizer:tokensToText(tokens: {number}): string
	local words = {}
	for _, id in ipairs(tokens) do
		local tk = self.ivocab[id] or self.unknownToken
		table.insert(words, tk)
	end
	return table.concat(words, " ")
end

return BPETokenizer
