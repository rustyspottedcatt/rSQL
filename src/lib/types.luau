--[[
    Types Module

    @module Types
]]

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
    textToTokens: (self: Tokenizer, text: string) -> { number },
    tokensToText: (self: Tokenizer, tokens: { number }) -> string,
    buildVocabFromText: (self: Tokenizer, text: string) -> any,
    loadExternalVocab: (self: Tokenizer, url: string) -> any,
}

export type Optimizer = {
    updateParameters: (self: Optimizer, parameters: { any }, gradients: { any }, learningRate: number) -> any,
}

export type LossFunction = {
    compute: (self: LossFunction, logits: Matrix, targets: { number }) -> number,
    backward: (self: LossFunction, logits: Matrix, targets: { number }) -> Matrix,
}

return {}
