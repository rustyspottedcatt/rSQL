export type Token = { type: string, value: string }
export type ParsedQuery = {
    type: string,
    columns: { string },
    tableName: string,
    whereClause: { { column: string, operator: string, value: string } },
    setClauses: { { column: string, value: string } },
    values: { string },
    commandOptions: { string }
}

local YACC = require(script.Parent.YACC)

local SQLParser = {}
SQLParser.__index = SQLParser

local Keywords = {
    "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "TRUNCATE", "ALTER", "ADD",
    "FROM", "WHERE", "SET", "VALUES", "INTO", "TABLE", "COLUMN", "AND", "OR", "NOT",
    "NULL", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "JOIN", "ON", "GROUP", "BY",
    "ORDER", "HAVING", "ASC", "DESC"
}

local function tokenize(query: string): { Token }
    local tokens: { Token } = {}
    local current = ""
    local i = 1
    local inQuote = false
    local quoteChar = ""

    while i <= #query do
        local char = query:sub(i, i)

        if inQuote then
            if char == quoteChar then
                table.insert(tokens, { type = "STRING", value = current })
                current = ""
                inQuote = false
                quoteChar = ""
            else
                current = current .. char
            end
        else
            if char == "'" or char == '"' then
                if #current > 0 then
                    table.insert(tokens, { type = "UNKNOWN", value = current })
                    current = ""
                end
                inQuote = true
                quoteChar = char
            elseif char:match("%s") then
                if #current > 0 then
                    table.insert(tokens, { type = "UNKNOWN", value = current })
                    current = ""
                end
            elseif char:match("[(),;=*<>!]") then
                if #current > 0 then
                    table.insert(tokens, { type = "UNKNOWN", value = current })
                    current = ""
                end
                local nextChar = query:sub(i + 1, i + 1)
                if (char == ">" or char == "<" or char == "!" or char == "=") and nextChar == "=" then
                    table.insert(tokens, { type = "SYMBOL", value = char .. nextChar })
                    i = i + 1
                else
                    table.insert(tokens, { type = "SYMBOL", value = char })
                end
            else
                current = current .. char
            end
        end
        i += 1
    end

    if #current > 0 then
        if inQuote then
            error("Unclosed quote in query.")
        else
            table.insert(tokens, { type = "UNKNOWN", value = current })
        end
    end

    for _, token in ipairs(tokens) do
        if token.type ~= "STRING" then
            if table.find(Keywords, token.value:upper()) then
                token.type = "KEYWORD"
                token.value = token.value:upper()
            elseif token.value:match("^%d+$") then
                token.type = "NUMBER"
            elseif token.value:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                token.type = "IDENTIFIER"
            else
                token.type = "SYMBOL"
            end
        end
    end
    return tokens
end

function SQLParser.parse(query: string): ParsedQuery
    local tokens = tokenize(query)
    return YACC:parse(tokens)
end

return SQLParser
