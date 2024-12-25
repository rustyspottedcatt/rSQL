--[[
    ProfileSQL
    Handles SQL-like queries and operations on Roblox's ProfileService.
    
    @module ProfileSQL
]]
local Types = require(script.Parent.Parent.lib.types)
local Promise = require(script.Parent.Parent.Parent.Parent.Packages.promise)

local ProfileSQL = {}
ProfileSQL.__index = ProfileSQL

--[[
    Generates a standardized error message with traceback.

    @local
    @function generateError
    @param functionName string - Name of the function where the error occurred.
    @param message string - Error message.
    @return string - Formatted error message.
]]
local function generateError(functionName, message)
    return string.format("[rSQL][%s] %s\nTraceback:\n%s", functionName, message, debug.traceback())
end

--[[
    Extracts the SQL command from a query string.

    @local
    @function extractCommand
    @param query string - The SQL query string.
    @return string - The extracted SQL command in uppercase.
]]
local function extractCommand(query)
    local command = query:match("^(%w+)")
    return command and command:upper() or ""
end

--[[
    Executes a SQL query based on the provided command and configuration.

    @function query
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param query Types.SQLQuery - The SQL query string to execute.
    @return Types.TypedPromise<Types.SQLQueryResult> - A promise that resolves with the query result.
]]
function ProfileSQL.query(self: Types.ProfileSQLConnection, query: Types.SQLQuery): Types.TypedPromise<Types.SQLQueryResult>
    return Promise.new(function(resolve, reject)
        local functionName = "ProfileSQL.query"

        local success, queryCommand, tableName, columns, values, conditions = pcall(function()
            return self:parseSQL(query :: Types.SQLQuery)
        end)

        if not success then
            return reject(generateError(functionName, "Failed to parse SQL query: " .. tostring(queryCommand)))
        end

        if not queryCommand then
            return reject(generateError(functionName, "Unexpected `nil` value for `queryCommand`, expected SQL command."))
        end

        if queryCommand == "CREATE" and self.config.allowCreate then
            local success, result = self:createTable(tableName, columns)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        elseif queryCommand == "DROP" and self.config.allowDrop then
            local success, result = self:dropTable(tableName)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        elseif queryCommand == "TRUNCATE" and self.config.allowTruncate then
            local success, result = self:truncateTable(tableName)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        elseif queryCommand == "INSERT" and self.config.allowInsert then
            local success, result = self:insert(tableName, columns, values)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        elseif queryCommand == "SELECT" and self.config.allowSelect then
            local success, result = self:select(tableName, columns, conditions)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        elseif queryCommand == "UPDATE" and self.config.allowUpdate then
            local success, result = self:update(tableName, columns, values, conditions)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        elseif queryCommand == "DELETE" and self.config.allowDelete then
            local success, result = self:delete(tableName, conditions)
            if success then
                return resolve(result)
            else
                return reject(generateError(functionName, result))
            end
        else
            return reject(generateError(functionName, "Unexpected SQL command, expected INSERT, SELECT, UPDATE, DELETE, CREATE, DROP or TRUNCATE, OR command is not allowed by config."))
        end
    end)
end

--[[
    Parses a SQL query string into its components.

    @function parseSQL
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param query Types.SQLQuery - The SQL query string to parse.
    @return string, string, table, table, table - Parsed components of the SQL query.
]]
function ProfileSQL.parseSQL(self: Types.ProfileSQLConnection, query: Types.SQLQuery)
    local functionName = "ProfileSQL.parseSQL"
    local command = extractCommand(query)

    local createPattern = "^CREATE%s+TABLE%s+([%w_]+)%s*%(([%w_,%s]+)%)$"
    local dropPattern = "^DROP%s+TABLE%s+([%w_]+)%s*$"
    local truncatePattern = "^TRUNCATE%s+TABLE%s+([%w_]+)%s*$"
    local insertPattern = "^INSERT%s+INTO%s+([%w_]+)%s*%(([%w_,%s]+)%)%s*VALUES%s*%(([%w%s',]+)%)$"
    local selectPattern = [[SELECT%s+(.-)%s+FROM%s+(%S+)%s*WHERE%s*(.+)]]
    local updatePattern = [[UPDATE%s+(%S+)%s+SET%s+(.-)%s*WHERE%s*(.+)]]
    local deletePattern = [[DELETE%s+FROM%s+(%S+)%s+WHERE%s+(.+)]]

    local function stripQuotes(s: string): string
        return s:gsub("^'(.-)'$", "%1")
    end

    if command == "CREATE" then
        local createMatch = { string.match(query, createPattern) }
        if #createMatch == 2 then
            local tableName, columnsStr = createMatch[1], createMatch[2]
            local columns = self:split(columnsStr, ",")
            return "CREATE", tableName, columns, nil, nil
        else
            print("CREATE pattern did not match. Expected 2 captures, got:", #createMatch)
            error(generateError(functionName, "CREATE TABLE query did not match the expected pattern."))
        end
    elseif command == "DROP" then
        local dropMatch = { string.match(query, dropPattern) }
        if #dropMatch == 1 then
            local tableName = dropMatch[1]
            return "DROP", tableName, nil, nil, nil
        else
            print("DROP pattern did not match. Expected 1 capture, got:", #dropMatch)
            error(generateError(functionName, "DROP TABLE query did not match the expected pattern."))
        end
    elseif command == "TRUNCATE" then
        local truncateMatch = { string.match(query, truncatePattern) }
        if #truncateMatch == 1 then
            local tableName = truncateMatch[1]
            return "TRUNCATE", tableName, nil, nil, nil
        else
            print("TRUNCATE pattern did not match. Expected 1 capture, got:", #truncateMatch)
            error(generateError(functionName, "TRUNCATE TABLE query did not match the expected pattern."))
        end
    elseif command == "INSERT" then
        local insertMatch = { string.match(query, insertPattern) }
        if #insertMatch == 3 then
            local tableName, columnsStr, valuesStr = insertMatch[1], insertMatch[2], insertMatch[3]
            local columns = self:split(columnsStr, ",")
            local values = self:split(valuesStr, ",")

            for i, value in ipairs(values) do
                values[i] = stripQuotes(value)
            end

            return "INSERT", tableName, columns, values, nil
        else
            print("INSERT pattern did not match. Expected 3 captures, got:", #insertMatch)
            error(generateError(functionName, "INSERT query did not match the expected pattern."))
        end
    elseif command == "SELECT" then
        local selectMatch = { string.match(query, selectPattern) }
        if #selectMatch >= 2 then
            local columnsStr, tableName, conditionsStr = selectMatch[1], selectMatch[2], selectMatch[3]
            local columns = self:split(columnsStr, ",")

            local conditions = nil
            if conditionsStr then
                conditions = self:parseConditions(conditionsStr)
                for key, value in pairs(conditions) do
                    conditions[key] = stripQuotes(value)
                end
            end

            return "SELECT", tableName, columns, nil, conditions
        else
            print("SELECT pattern did not match. Expected at least 2 captures, got:", #selectMatch)
            error(generateError(functionName, "SELECT query did not match the expected pattern."))
        end
    elseif command == "UPDATE" then
        local updateMatch = { string.match(query, updatePattern) }
        if #updateMatch >= 3 then
            local tableName, setStr, conditionsStr = updateMatch[1], updateMatch[2], updateMatch[3]
            local setClauses = self:parseSetClause(setStr)

            for key, value in pairs(setClauses) do
                setClauses[key] = stripQuotes(value)
            end

            local conditions = nil
            if conditionsStr then
                conditions = self:parseConditions(conditionsStr)
                for key, value in pairs(conditions) do
                    conditions[key] = stripQuotes(value)
                end
            end

            return "UPDATE", tableName, setClauses, nil, conditions
        else
            print("UPDATE pattern did not match. Expected 3 captures, got:", #updateMatch)
            error(generateError(functionName, "UPDATE query did not match the expected pattern."))
        end
    elseif command == "DELETE" then
        local deleteMatch = { string.match(query, deletePattern) }
        if #deleteMatch >= 2 then
            local tableName, conditionsStr = deleteMatch[1], deleteMatch[2]

            local conditions = nil
            if conditionsStr then
                conditions = self:parseConditions(conditionsStr)
                for key, value in pairs(conditions) do
                    conditions[key] = stripQuotes(value)
                end
            end

            return "DELETE", tableName, nil, nil, conditions
        else
            print("DELETE pattern did not match. Expected 2 captures, got:", #deleteMatch)
            error(generateError(functionName, "DELETE query did not match the expected pattern."))
        end
    else
        print("Unsupported SQL command detected:", command)
        error(generateError(functionName, "Unsupported SQL command: " .. command))
    end
end

--[[
    Creates a new table in the profiles table.

    @function createTable
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to create.
    @param columns table - List of column names.
    @return boolean, string? - Success status and an optional error message.
]]
function ProfileSQL.createTable(self: Types.ProfileSQLConnection, tableName: string, columns: table): (boolean, string?)
    local functionName = "ProfileSQL.createTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columns or #columns == 0 then
        return false, generateError(functionName, "Columns must be specified for CREATE TABLE.")
    end

    if self.profilesTable[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' already exists.")
    end

    self.profilesTable[tableName] = {}
    return true, "[rSQL] Table '" .. tableName .. "' created successfully."
end

--[[
    Drops an existing table from the profiles table.

    @function dropTable
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to drop.
    @return boolean, string? - Success status and an optional error message.
]]
function ProfileSQL.dropTable(self: Types.ProfileSQLConnection, tableName: string): (boolean, string?)
    local functionName = "ProfileSQL.dropTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not self.profilesTable[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    self.profilesTable[tableName] = nil
    return true, "[rSQL] Table '" .. tableName .. "' dropped successfully."
end

--[[
    Truncates a table by deleting all its records.

    @function truncateTable
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to truncate.
    @return boolean, string? - Success status and an optional error message.
]]
function ProfileSQL.truncateTable(self: Types.ProfileSQLConnection, tableName: string): (boolean, string?)
    local functionName = "ProfileSQL.truncateTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not self.profilesTable[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    self.profilesTable[tableName] = {}
    return true, "[rSQL] Table '" .. tableName .. "' truncated successfully."
end

--[[
    Inserts a new record into the specified table.

    @function insert
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to insert into.
    @param columns table - List of column names.
    @param values table - List of values corresponding to the columns.
    @return boolean, string? - Success status and an optional error message.
]]
function ProfileSQL.insert(self: Types.ProfileSQLConnection, tableName: string, columns: table, values: table): (boolean, string?)
    local functionName = "ProfileSQL.insert"
    if #columns ~= #values then
        return false, generateError(functionName, "Number of columns and values do not match.")
    end

    local record = {}
    for i, column in ipairs(columns) do
        record[column] = values[i]
    end

    local fetchedData: table = self.profilesTable[tableName]

    if fetchedData == nil and self.config.allowOverwrite then
        fetchedData = {}
    elseif fetchedData == nil and not self.config.allowOverwrite then
        return false, generateError(functionName, "Table does not exist and overwrite is not allowed, so cannot insert data.")
    end

    table.insert(fetchedData, record)
    self.profilesTable[tableName] = fetchedData

    return true
end

--[[
    Selects records from the specified table based on conditions.

    @function select
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to select from.
    @param columns table - List of columns to retrieve.
    @param conditions table? - Optional conditions to filter the records.
    @return Types.SQLQueryResult?, string? - Query result and an optional error message.
]]
function ProfileSQL.select(self: Types.ProfileSQLConnection, tableName: string, columns: table, conditions: table?): (Types.SQLQueryResult?, string?)
    local functionName = "ProfileSQL.select"
    local fetchedData: table = self.profilesTable[tableName]

    if not fetchedData then
        return {}, generateError(functionName, "Failed to fetch data from profilesTable.")
    end

    local results: table = {}
    for _, record in ipairs(fetchedData) do
        local match: boolean = true
        if conditions then
            for key: string, value: string in pairs(conditions) do
                if tostring(record[key]) ~= value then
                    match = false
                    break
                end
            end
        end

        if match then
            if columns[1] == "*" then
                table.insert(results, record)
            else
                local selectedRecord = {}
                for _, column in ipairs(columns) do
                    selectedRecord[column] = record[column]
                end
                table.insert(results, selectedRecord)
            end
        end
    end

    if #results == 0 then
        return generateError(functionName, "No matching records found."), results
    else
        return "[rSQL] Records successfully fetched.", results
    end
end

--[[
    Updates records in the specified table based on conditions.

    @function update
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to update.
    @param setClauses table - Key-value pairs representing columns to update and their new values.
    @param conditions table? - Optional conditions to filter the records to update.
    @return boolean, string? - Success status and an optional error message.
]]
function ProfileSQL.update(self: Types.ProfileSQLConnection, tableName: string, setClauses: table, conditions: table?): (boolean, string?)
    local functionName = "ProfileSQL.update"
    local fetchedData: table = self.profilesTable[tableName]

    if not fetchedData then
        if self.config.allowOverwrite then
            fetchedData = {}
            self.profilesTable[tableName] = fetchedData
        else
            return false, generateError(functionName, "Table does not exist and overwrite is not allowed, so cannot update data.")
        end
    end

    local updated: boolean = false
    for _, record in ipairs(fetchedData) do
        local matches = true
        if conditions then
            for key, value in pairs(conditions) do
                if tostring(record[key]) ~= value then
                    matches = false
                    break
                end
            end
        end

        if matches then
            for key, value in pairs(setClauses) do
                record[key] = value
            end
            updated = true
        end
    end

    if updated then
        self.profilesTable[tableName] = fetchedData
        return true
    else
        return false, generateError(functionName, "No matching records found to update.")
    end
end

--[[
    Deletes records from the specified table based on conditions.

    @function delete
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - Name of the table to delete from.
    @param conditions table? - Optional conditions to filter the records to delete.
    @return boolean, string? - Success status and an optional error message.
]]
function ProfileSQL.delete(self: Types.ProfileSQLConnection, tableName: string, conditions: table?): (boolean, string?)
    local functionName = "ProfileSQL.delete"
    local fetchedData: table = self.profilesTable[tableName]

    if not fetchedData then
        if self.config.allowOverwrite then
            fetchedData = {}
            self.profilesTable[tableName] = fetchedData
        else
            return false, generateError(functionName, "Table does not exist and overwrite is not allowed, so cannot delete data.")
        end
    end

    local originalCount: number = #fetchedData
    local filteredData: table = {}

    for _, record in ipairs(fetchedData) do
        local matches = true
        if conditions then
            for key, value in pairs(conditions) do
                if tostring(record[key]) ~= value then
                    matches = false
                    break
                end
            end
        end

        if not matches then
            table.insert(filteredData, record)
        end
    end

    if #filteredData == originalCount then
        return false, generateError(functionName, "No matching records found to delete.")
    elseif #filteredData == 0 then
        self.profilesTable[tableName] = {}
        return false, generateError(functionName, "All records deleted.")
    else
        self.profilesTable[tableName] = filteredData
        return true
    end
end

--[[
    Splits a string based on the provided separator.

    @function split
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param inputStr string - The string to split.
    @param sep string - The separator to split by.
    @return table - A table containing the split substrings.
]]
function ProfileSQL.split(self: Types.ProfileSQLConnection, inputStr: string, sep: string): table
    local result: table = {}
    for str in string.gmatch(inputStr, "([^" .. sep .. "]+)") do
        table.insert(result, self:trim(str))
    end
    return result
end

--[[
    Trims leading and trailing whitespace from a string.

    @function trim
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param s string - The string to trim.
    @return string - The trimmed string.
]]
function ProfileSQL.trim(self: Types.ProfileSQLConnection, s: string): string
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--[[
    Parses a conditions string into a table of key-value pairs.

    @function parseConditions
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param conditionStr string - The conditions string to parse.
    @return table - A table containing the parsed conditions.
]]
function ProfileSQL.parseConditions(self: Types.ProfileSQLConnection, conditionStr: string): table
    local functionName = "ProfileSQL.parseConditions"
    local conditions = {}
    for key, value in string.gmatch(conditionStr, "(%w+)%s*=%s*'?(%w+)'?") do
        conditions[key] = value
    end
    if next(conditions) == nil then
        error(generateError(functionName, "Failed to parse conditions: No valid key-value pairs found."))
    end
    return conditions
end

--[[
    Removes surrounding single quotes from a string.

    @function stripQuotes
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param s string - The string to strip quotes from.
    @return string - The unquoted string.
]]
function ProfileSQL.stripQuotes(self: Types.ProfileSQLConnection, s: string): string
    return s:gsub("^'(.-)'$", "%1")
end

--[[
    Parses the SET clause of an UPDATE statement into a table of key-value pairs.

    @function parseSetClause
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param setStr string - The SET clause string to parse.
    @return table - A table containing the parsed SET clauses.
]]
function ProfileSQL.parseSetClause(self: Types.ProfileSQLConnection, setStr: string): table
    local functionName = "ProfileSQL.parseSetClause"
    local setClauses = {}
    for key, value in string.gmatch(setStr, "(%w+)%s*=%s*'?(%w+)'?") do
        setClauses[key] = value
    end
    if next(setClauses) == nil then
        error(generateError(functionName, "Failed to parse SET clause: No valid key-value pairs found."))
    end
    return setClauses
end

return ProfileSQL
