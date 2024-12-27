local YACC = {}
YACC.__index = YACC

function YACC.new()
    local self = setmetatable({}, YACC)
    return self
end

function YACC:parse(tokens)
    local index = 1

    local function peek()
        return tokens[index]
    end

    local function consume()
        local tok = tokens[index]
        index = index + 1
        return tok
    end

    local function expect(value)
        local tok = consume()
        if not tok or tok.value ~= value then
            error("Expected " .. value)
        end
    end

    local function parseSelect()
        expect("SELECT")
        local columns = {}
        while true do
            local tok = consume()
            if not tok then break end
            if tok.value ~= "," and tok.value ~= "FROM" then
                table.insert(columns, tok.value)
            elseif tok.value == "FROM" then
                index = index - 1
                break
            end
            if peek() and peek().value == "," then
                consume()
            else
                break
            end
        end
        expect("FROM")
        local tableNameToken = consume()
        if not tableNameToken then
            error("Expected table name but found nil.")
        end
        local tableName = tableNameToken.value
        local whereClause = {}
        if peek() and peek().value == "WHERE" then
            consume()
            while true do
                local column = consume().value
                local operator = consume().value
                local valueToken = consume()
                if not valueToken then
                    error("Expected value but found nil.")
                end
                local value = valueToken.value
                table.insert(whereClause, { column = column, operator = operator, value = value })
                if peek() and (peek().value == "AND" or peek().value == "OR") then
                    consume()
                else
                    break
                end
            end
        end
        return {
            type = "SELECT",
            columns = columns,
            tableName = tableName,
            whereClause = whereClause,
            setClauses = {},
            values = {},
            commandOptions = {}
        }
    end

    local function parseInsert()
        expect("INSERT")
        expect("INTO")
        local tableName = consume().value
        local columns = {}
        if peek() and peek().value == "(" then
            consume()
            while true do
                local tok = consume()
                if tok.value ~= "," and tok.value ~= ")" then
                    table.insert(columns, tok.value)
                elseif tok.value == ")" then
                    break
                end
                if peek() and peek().value == "," then
                    consume()
                else
                    break
                end
            end
            expect(")")
        end
        expect("VALUES")
        local values = {}
        if peek() and peek().value == "(" then
            consume()
            while true do
                local tok = consume()
                if not tok then
                    error("Expected value but found nil.")
                end
                if tok.value ~= "," and tok.value ~= ")" then
                    table.insert(values, tok.value)
                elseif tok.value == ")" then
                    break
                end
                if peek() and peek().value == "," then
                    consume()
                else
                    break
                end
            end
            expect(")")
        end
        return {
            type = "INSERT",
            tableName = tableName,
            columns = columns,
            values = values,
            setClauses = {},
            whereClause = {},
            commandOptions = {}
        }
    end

    local function parseUpdate()
        expect("UPDATE")
        local tableName = consume().value
        expect("SET")
        local setClauses = {}
        while true do
            local column = consume().value
            expect("=")
            local valueToken = consume()
            if not valueToken then
                error("Expected value but found nil.")
            end
            local value = valueToken.value
            table.insert(setClauses, { column = column, value = value })
            if peek() and peek().value == "," then
                consume()
            else
                break
            end
        end
        local whereClause = {}
        if peek() and peek().value == "WHERE" then
            consume()
            while true do
                local column = consume().value
                local operator = consume().value
                local valueToken = consume()
                if not valueToken then
                    error("Expected value but found nil.")
                end
                local value = valueToken.value
                table.insert(whereClause, { column = column, operator = operator, value = value })
                if peek() and (peek().value == "AND" or peek().value == "OR") then
                    consume()
                else
                    break
                end
            end
        end
        return {
            type = "UPDATE",
            tableName = tableName,
            setClauses = setClauses,
            whereClause = whereClause,
            columns = {},
            values = {},
            commandOptions = {}
        }
    end

    local function parseDelete()
        expect("DELETE")
        expect("FROM")
        local tableName = consume().value
        local whereClause = {}
        if peek() and peek().value == "WHERE" then
            consume()
            while true do
                local column = consume().value
                local operator = consume().value
                local valueToken = consume()
                if not valueToken then
                    error("Expected value but found nil.")
                end
                local value = valueToken.value
                table.insert(whereClause, { column = column, operator = operator, value = value })
                if peek() and (peek().value == "AND" or peek().value == "OR") then
                    consume()
                else
                    break
                end
            end
        end
        return {
            type = "DELETE",
            tableName = tableName,
            whereClause = whereClause,
            columns = {},
            setClauses = {},
            values = {},
            commandOptions = {}
        }
    end

    local function parseCreate()
        expect("CREATE")
        expect("TABLE")
        
        local tableNameToken = consume()
        if not tableNameToken then
            error("[rSQL][parseCreate] Expected table name but found nil.")
        end
        local tableName = tableNameToken.value
        
        local columns = {}
    
        if peek() and peek().value == "(" then
            consume()
            if peek() and peek().value == ")" then
                consume()
            else
                while true do
                    local columnToken = consume()
                    if not columnToken then
                        error("[rSQL][parseCreate] Expected column name but found nil.")
                    end
                    table.insert(columns, columnToken.value)
                    
                    local nextToken = peek()
                    if nextToken and nextToken.value == "," then
                        consume()
                    elseif nextToken and nextToken.value == ")" then
                        consume()
                        break
                    else
                        error("[rSQL][parseCreate] Expected ',' or ')' but found " .. (nextToken and nextToken.value or "nil"))
                    end
                end
            end
        else
            error("[rSQL][parseCreate] Expected '(' after table name.")
        end
    
        return {
            type = "CREATE",
            tableName = tableName,
            columns = columns,
            whereClause = {},
            setClauses = {},
            values = {},
            commandOptions = {}
        }
    end    

    local function parseDrop()
        expect("DROP")
        expect("TABLE")
        local tableName = consume().value
        return {
            type = "DROP",
            tableName = tableName,
            columns = {},
            whereClause = {},
            setClauses = {},
            values = {},
            commandOptions = {}
        }
    end

    local function parseTruncate()
        expect("TRUNCATE")
        local tableName = consume().value
        return {
            type = "TRUNCATE",
            tableName = tableName,
            columns = {},
            whereClause = {},
            setClauses = {},
            values = {},
            commandOptions = {}
        }
    end

    local function parseAlter()
        expect("ALTER")
        expect("TABLE")
        local tableName = consume().value
        local alterType = consume().value
        expect("COLUMN")
        local columnName = consume().value
        if alterType == "ADD" then
            local columnType = consume().value
            return {
                type = "ALTER",
                tableName = tableName,
                columns = {},
                setClauses = {},
                values = {},
                whereClause = {},
                commandOptions = { alterType, columnName, columnType }
            }
        elseif alterType == "DROP" then
            return {
                type = "ALTER",
                tableName = tableName,
                columns = {},
                setClauses = {},
                values = {},
                whereClause = {},
                commandOptions = { alterType, columnName }
            }
        else
            error("Unsupported ALTER operation: " .. alterType)
        end
    end

    if not peek() then
        error("Empty query")
    end

    local command = peek().value
    if command == "SELECT" then
        return parseSelect()
    elseif command == "INSERT" then
        return parseInsert()
    elseif command == "UPDATE" then
        return parseUpdate()
    elseif command == "DELETE" then
        return parseDelete()
    elseif command == "CREATE" then
        return parseCreate()
    elseif command == "DROP" then
        return parseDrop()
    elseif command == "TRUNCATE" then
        return parseTruncate()
    elseif command == "ALTER" then
        return parseAlter()
    else
        error("Unknown SQL command: " .. command)
    end
end

return YACC
