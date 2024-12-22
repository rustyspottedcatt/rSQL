export type TransformerConfig = {
	vocabSize: number?,
	dModel: number,
	numHeads: number,
	dFF: number,
	numLayers: number,
	maxSeqLen: number,
	tokenizerMode: string?,
	externalVocabURL: string?,
}

export type Matrix = { [number]: { [number]: number } }

export type Vector = { [number]: number }

export type Tokenizer = {
	getVocabSize: (self: Tokenizer) -> number,
	textToTokens: (self: Tokenizer, text: string) -> {number},
	tokensToText: (self: Tokenizer, tokens: {number}) -> string,
}
return {}
