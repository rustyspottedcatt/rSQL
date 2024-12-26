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

local SQLParser = {}
SQLParser.__index = SQLParser

local Keywords: { string } = {
    "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "TRUNCATE", "ALTER", "ADD", "FROM", "WHERE", "SET", "VALUES", "INTO", "TABLE",
    "COLUMN", "AND", "OR", "NOT", "NULL", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "JOIN", "ON", "GROUP", "BY", "ORDER", "HAVING", "CREATE", "TRUNCATE", "ALTER", "ADD", "DROP"
}

local function stripQuotes(value: string): string
    return value:match("^'?(.-)'?$")
end

local function tokenize(query: string): { string }
    local tokens: { string } = {}
    local current = ""
    local i = 1
    while i <= #query do
        local char = query:sub(i, i)
        if char:match("%s") then
            if #current > 0 then
                table.insert(tokens, current)
                current = ""
            end
        elseif char:match("[(),;]") then
            if #current > 0 then
                table.insert(tokens, current)
                current = ""
            end
            table.insert(tokens, char)
        elseif char:match("[*]") then
            if #current > 0 then
                table.insert(tokens, current)
                current = ""
            end
            table.insert(tokens, "*")
        else
            current = current .. char
        end
        i += 1
    end
    if #current > 0 then
        table.insert(tokens, current)
    end
    return tokens
end

local function lex(tokens: { string }): { Token }
    local lexemes: { Token } = {}
    for _, token in ipairs(tokens) do
        if table.find(Keywords, token:upper()) then
            table.insert(lexemes, { type = "KEYWORD", value = token:upper() })
        elseif token:match("^%d+$") then
            table.insert(lexemes, { type = "NUMBER", value = token })
        elseif token:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
            table.insert(lexemes, { type = "IDENTIFIER", value = token })
        else
            table.insert(lexemes, { type = "SYMBOL", value = token })
        end
    end
    return lexemes
end

local function parse(tokens: { Token }): ParsedQuery
    local index = 1

    local function peek(): Token
        return tokens[index]
    end

    local function consume(): Token
        local current = tokens[index]
        index = index + 1
        return current
    end

    local function parseCreate(): ParsedQuery
        consume()
    
        local tableKeyword = consume().value 
        local tableName = consume().value
    
        local columns = {}
    
        if peek().value == "(" then
            consume()
            repeat
                local columnPart = consume().value
                
                columnPart = stripQuotes(columnPart)
                if columnPart ~= "," and columnPart ~= ")" then
                    table.insert(columns, columnPart)
                end
            until peek().value == ")"
            consume() 
        end
    
        return { type = "CREATE", tableName = tableName, columns = columns }
    end    

    local function parseDrop(): ParsedQuery
        consume()
        local tableName = consume().value
        if tableName:upper() ~= "TABLE" then
            return error("Expected TABLE after DROP keyword")
        end
        tableName = consume().value

        return { type = "DROP", tableName = tableName }
    end

    local function parseTruncate(): ParsedQuery
        consume()
        local tableName = consume().value
        return { type = "TRUNCATE", tableName = tableName }
    end

    local function parseAlter(): ParsedQuery
        consume()
        local tableName = consume().value 
        
        if tableName:upper() ~= "TABLE" then
            return error("Expected TABLE after ALTER keyword")
        end
        
        tableName = consume().value 
    
        local alterType = consume().value 
        local columnKeyword = consume().value 
    
        if columnKeyword:upper() ~= "COLUMN" then
            return error("Expected 'COLUMN' keyword after ADD/DROP")
        end
    
        local columnName = consume().value 
        if alterType == "ADD" then
            local columnType = consume().value 
            return { type = "ALTER", tableName = tableName, commandOptions = { alterType, columnName, columnType } }
        elseif alterType == "DROP" then
            return { type = "ALTER", tableName = tableName, commandOptions = { alterType, columnName } }
        else
            error("Unsupported ALTER operation: " .. alterType)
        end
    end

    local function parseSelect(): ParsedQuery
        consume()
        local columns: { string } = {}
        repeat
            local column = consume().value
            column = stripQuotes(column)

            if column ~= "," then
                table.insert(columns, column)
            end
        until peek().value ~= ","
        consume()
        local tableName = consume().value
        local whereClause: { { column: string, operator: string, value: string } } = {}
        if peek().value:upper() == "WHERE" then
            consume()
            repeat
                local column = consume().value
                local operator = consume().value
                local value = consume().value
                value = stripQuotes(value)

                table.insert(whereClause, { column = column, operator = operator, value = value })
            until not peek() or peek().value == ";"
        end
        return { type = "SELECT", columns = columns, tableName = tableName, whereClause = whereClause }
    end

    local function parseInsert(): ParsedQuery
        consume()
        consume()
        local tableName = consume().value
        local columns: { string } = {}
        if peek().value == "(" then
            consume()
            repeat
                local column = consume().value
                column = stripQuotes(column)

                if column ~= "," and column ~= ")" then
                    table.insert(columns, column)
                end
            until peek().value == ")"
            consume()
        end
        consume()
        local values: { string } = {}
        if peek().value == "(" then
            consume()
            repeat
                local value = consume().value
                value = stripQuotes(value)

                if value ~= "," and value ~= ")" then
                    table.insert(values, value)
                end
            until peek().value == ")"
            consume()
        end
        return { type = "INSERT", tableName = tableName, columns = columns, values = values }
    end

    local function parseUpdate(): ParsedQuery
        consume()
        local tableName = consume().value
        consume()
        local setClauses: { { column: string, value: string } } = {}
        repeat
            local column = consume().value
            consume()
            local value = consume().value
            value = stripQuotes(value)

            table.insert(setClauses, { column = column, value = value })
        until peek().value ~= ","
        if peek().value:upper() == "WHERE" then
            consume()
            local whereClause: { { column: string, operator: string, value: string } } = {}
            repeat
                local column = consume().value
                local operator = consume().value
                local value = consume().value
                value = stripQuotes(value)

                table.insert(whereClause, { column = column, operator = operator, value = value })
            until not peek() or peek().value == ";"
            return { type = "UPDATE", tableName = tableName, setClauses = setClauses, whereClause = whereClause }
        end
        return { type = "UPDATE", tableName = tableName, setClauses = setClauses, whereClause = {} }
    end

    local function parseDelete(): ParsedQuery
        consume()
        consume()
        local tableName = consume().value
        local whereClause: { { column: string, operator: string, value: string } } = {}
        if peek().value:upper() == "WHERE" then
            consume()
            repeat
                local column = consume().value
                local operator = consume().value
                local value = consume().value
                value = stripQuotes(value)

                table.insert(whereClause, { column = column, operator = operator, value = value })
            until not peek() or peek().value == ";"
        end
        return { type = "DELETE", tableName = tableName, whereClause = whereClause }
    end

    local function parseQuery(): ParsedQuery
        local token = peek()
        if token.value:upper() == "SELECT" then
            return parseSelect()
        elseif token.value:upper() == "INSERT" then
            return parseInsert()
        elseif token.value:upper() == "UPDATE" then
            return parseUpdate()
        elseif token.value:upper() == "DELETE" then
            return parseDelete()
        elseif token.value:upper() == "CREATE" then
            return parseCreate()
        elseif token.value:upper() == "DROP" then
            return parseDrop()
        elseif token.value:upper() == "TRUNCATE" then
            return parseTruncate()
        elseif token.value:upper() == "ALTER" then
            return parseAlter()
        else
            error("Unknown SQL command: " .. token.value)
        end
    end

    return parseQuery()
end

function SQLParser.parse(query: string): ParsedQuery
    local tokens = tokenize(query)
    local lexemes = lex(tokens)
    return parse(lexemes)
end

return SQLParser
