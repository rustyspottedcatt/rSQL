local Types = require(script.Parent.Parent.lib.types)
local SQLParser = require(script.Parent.SQLParser)
local Promise = require(script.Parent.Parent.Parent.Parent.Packages.promise)

local DatastoreSQL = {}
DatastoreSQL.__index = DatastoreSQL

--[[
    Generates a formatted error message with traceback.

    @function generateError
    @param functionName string - The name of the function where the error occurred.
    @param message string - The error message.
    @return string - The formatted error message.
]]
local function generateError(functionName, message)
    return string.format("[rSQL][%s] %s\nTraceback:\n%s", functionName, message, debug.traceback())
end

--[[
    Normalizes an SQL query string by removing extra whitespace.

    @function normalizeSQL
    @param query string - The SQL query string to normalize.
    @return string - The normalized SQL query string.
]]

local function normalizeSQL(query)
    query = query:gsub("%s+", " ")
    query = query:gsub("%s*,%s*", ", ")
    query = query:gsub("%s*%(%s*", "("):gsub("%s*%)%s*", ")")

    return query:match("^%s*(.-)%s*$")
end

--[[
    Extracts the SQL command from the query string.

    @function extractCommand
    @param query string - The SQL query string.
    @return string - The extracted SQL command in uppercase.
]]
local function extractCommand(query)
    local command = query:match("^(%w+)")
    return command and command:upper() or ""
end

--[[
    Executes an SQL query and returns a promise with the result.

    @function query
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param query string - The SQL query to execute.
    @return Types.TypedPromise<Types.SQLQueryResult> - A promise that resolves with the query result or rejects with an error.
]]
function DatastoreSQL.query(self: Types.DatastoreSQLConnection, query: Types.SQLQuery)
    return Promise.new(function(resolve, reject)
        local functionName = "DatastoreSQL.query"

        local parseSuccess, parsedQuery = pcall(function()
            return self:parseSQL(query)
        end)
        if not parseSuccess then
            return reject(generateError(functionName, "Failed to parse SQL query: " .. tostring(parsedQuery)))
        end

        local queryType = parsedQuery.type
        local querySuccess, queryData

        if queryType == "CREATE" and self.config.allowCreate then
            querySuccess, queryData = self:createTable(parsedQuery.tableName, parsedQuery.columns)
        elseif queryType == "DROP" and self.config.allowDrop then
            querySuccess, queryData = self:dropTable(parsedQuery.tableName)
        elseif queryType == "TRUNCATE" and self.config.allowTruncate then
            querySuccess, queryData = self:truncateTable(parsedQuery.tableName)
        elseif queryType == "INSERT" and self.config.allowInsert then
            querySuccess, queryData = self:insert(parsedQuery.tableName, parsedQuery.columns, parsedQuery.values)
        elseif queryType == "SELECT" and self.config.allowSelect then
            querySuccess, queryData = self:select(parsedQuery.tableName, parsedQuery.columns, parsedQuery.whereClause)
        elseif queryType == "UPDATE" and self.config.allowUpdate then
            querySuccess, queryData = self:update(parsedQuery.tableName, parsedQuery.setClauses, parsedQuery.whereClause)
        elseif queryType == "DELETE" and self.config.allowDelete then
            querySuccess, queryData = self:delete(parsedQuery.tableName, parsedQuery.whereClause)
            elseif queryType == "ALTER" and self.config.allowAlter then
                local tableName, alterType, columnDetails = parsedQuery.tableName, parsedQuery.commandOptions[1], { [1] = parsedQuery.commandOptions[2], [2] = parsedQuery.commandOptions[3] }
                if alterType == "ADD" then
                    querySuccess, queryData = self:alterTableAddColumn(tableName, columnDetails)
                elseif alterType == "DROP" then
                    querySuccess, queryData = self:alterTableDropColumn(tableName, columnDetails)
                else
                    return reject(generateError(functionName, "Unsupported ALTER TABLE operation."))
                end            
        else
            return reject(generateError(functionName, "Command not supported or disallowed by configuration."))
        end

        if querySuccess then
            return resolve(queryData)
        else
            return reject(generateError(functionName, queryData))
        end
    end)
end

--[[
    Parses an SQL query into its components using the SQLParser module.

    @function parseSQL
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param query string - The SQL query to parse.
    @return table - Parsed AST representing the query.
]]
function DatastoreSQL.parseSQL(self: Types.DatastoreSQLConnection, query: Types.SQLQuery)
    local functionName = "DatastoreSQL.parseSQL"

    local success, astOrError = pcall(SQLParser.parse, normalizeSQL(query))
    if not success then
        error(generateError(functionName, "Failed to parse SQL query: " .. tostring(astOrError)))
    end

    return astOrError
end


--[[
    Creates a new table in the datastore.

    @function createTable
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to create.
    @param columns table - A table of column names.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.createTable(self: Types.DatastoreSQLConnection, tableName: string, columns: table): (boolean, string?)
    local functionName = "DatastoreSQL.createTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columns or #columns == 0 then
        return false, generateError(functionName, "Columns must be specified for CREATE TABLE.")
    end

    local updateSuccess, updateError = pcall(function()
        self.datastore:UpdateAsync(tableName, function(currentData)
            if currentData then
                return currentData
            end
            return {}
        end)
    end)

    if updateSuccess then
        return true, "[rSQL] Table '" .. tableName .. "' created successfully."
    else
        return false, generateError(functionName, "Failed to create table: " .. tostring(updateError))
    end
end

--[[
    Drops an existing table from the datastore.

    @function dropTable
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to drop.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.dropTable(self: Types.DatastoreSQLConnection, tableName: string): (boolean, string?)
    local functionName = "DatastoreSQL.dropTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    local fetchSuccess, fetchedData = pcall(function()
        return self.datastore:GetAsync(tableName)
    end)

    if not fetchSuccess or not fetchedData then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    local removeSuccess, removeError = pcall(function()
        self.datastore:RemoveAsync(tableName)
    end)

    if not removeSuccess then
        return false, generateError(functionName, "Failed to drop table: " .. tostring(removeError))
    else
        return true, "[rSQL] Table '" .. tableName .. "' dropped successfully."
    end
end

--[[
    Truncates an existing table by removing all its records.

    @function truncateTable
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to truncate.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.truncateTable(self: Types.DatastoreSQLConnection, tableName: string): (boolean, string?)
    local functionName = "DatastoreSQL.truncateTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    local updateSuccess, updateError = pcall(function()
        return self.datastore:UpdateAsync(tableName, function(currentData)
            if not currentData then
                return false
            end
            return {}
        end)
    end)

    if updateSuccess then
        return true, "[rSQL] Table '" .. tableName .. "' truncated successfully."
    else
        return false, generateError(functionName, "Failed to truncate table: " .. tostring(updateError))
    end
end

--[[
    Inserts a new record into a table.

    @function insert
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to insert into.
    @param columns table - A table of column names.
    @param values table - A table of values corresponding to the columns.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.insert(self: Types.DatastoreSQLConnection, tableName: string, columns: table, values: table): (boolean, string?)
    local functionName = "DatastoreSQL.insert"
    if #columns ~= #values then
        return false, generateError(functionName, "Number of columns and values do not match.")
    end

    local record = {}
    for i, column in ipairs(columns) do
        local value = values[i]
        
        if typeof(value) == "string" then
            value = self:stripQuotes(value)
        end

        record[column] = value
    end

    local primaryKeyColumn = columns[1]
    local primaryKeyValue = record[primaryKeyColumn]

    local updateSuccess, updateError = pcall(function()
        self.datastore:UpdateAsync(tableName, function(currentData)
            currentData = currentData or {}

            local foundDuplicate = false
            for _, existingRecord in ipairs(currentData) do
                if existingRecord[primaryKeyColumn] == primaryKeyValue then
                    foundDuplicate = true
                    break
                end
            end

            if not foundDuplicate then
                table.insert(currentData, record)
            end

            return currentData
        end)
    end)

    if updateSuccess then
        return true, "[rSQL] Data inserted successfully."
    else
        return false, generateError(functionName, "Failed to insert data: " .. tostring(updateError))
    end
end


--[[
    Selects records from a table based on conditions, order, limit, and distinct.

    @function select
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to select from.
    @param columns table - A table of column names to retrieve.
    @param conditions table? - A table of conditions for filtering records.
    @param orderBy table? - A table of columns to order the results by.
    @param limit number? - The maximum number of records to return.
    @param distinct boolean? - Whether to return distinct records.
    @return Types.SQLQueryResult - SQL query result.
]]
function DatastoreSQL.select(self: Types.DatastoreSQLConnection, tableName: string, columns: table, conditions: table?, orderBy: table?, limit: number?, distinct: boolean?): Types.SQLQueryResult
    local functionName = "DatastoreSQL.select"
    local fetchSuccess, fetchedData: table = pcall(function()
        return self.datastore:GetAsync(tableName)
    end)

    if not fetchSuccess or not fetchedData then
        return false, generateError(functionName, "Failed to fetch data from DataStore.")
    end

    local results: table = {}

    if conditions then
        for _, condition in ipairs(conditions) do
            condition.value = self:stripQuotes(condition.value)
        end
    end

    for _, record in ipairs(fetchedData) do
        local match: boolean = true

        for key, value in pairs(record) do
            record[key] = self:stripQuotes(value)
        end

        if conditions then
            for _, condition in ipairs(conditions) do
                if tostring(record[condition.column]) ~= condition.value then
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

    if distinct then
        local uniqueResults = {}
        local seen = {}
        for _, record in ipairs(results) do
            local key = table.concat({ table.unpack(record) }, "|")
            if not seen[key] then
                table.insert(uniqueResults, record)
                seen[key] = true
            end
        end
        results = uniqueResults
    end

    if orderBy and #orderBy > 0 then
        table.sort(results, function(a, b)
            for _, column in ipairs(orderBy) do
                local direction = "ASC"
                local colName = column

                if column:find("%s+") then
                    colName, direction = column:match("^(%w+)%s+(ASC|DESC)$")
                    direction = direction or "ASC"
                end

                if a[colName] ~= b[colName] then
                    if direction == "ASC" then
                        return a[colName] < b[colName]
                    else
                        return a[colName] > b[colName]
                    end
                end
            end
            return false
        end)
    end

    if limit and limit > 0 then
        for i = #results, limit + 1, -1 do
            table.remove(results, i)
        end
    end

    if #results == 0 then
        return false, generateError(functionName, "No matching records found.")
    else
        return "[rSQL] Records successfully fetched.", results
    end
end


--[[
    Updates records in a table based on conditions.

    @function update
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to update.
    @param setClauses table - A table of key-value pairs to set.
    @param conditions table? - A table of conditions for filtering records.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.update(self: Types.DatastoreSQLConnection, tableName: string, setClauses: table, conditions: table?): Types.TypedPromise<(boolean, string?)>
    local functionName = "DatastoreSQL.update"

    local updateSuccess, updateError = pcall(function()
        self.datastore:UpdateAsync(tableName, function(currentData)
            if not currentData then
                error("Table '" .. tableName .. "' does not exist.")
            end

            local updated = false

            for _, record in ipairs(currentData) do
                local matches = true

                for _, condition in ipairs(conditions) do
                    local column = condition.column
                    local operator = condition.operator
                    local value = condition.value

                    if tostring(record[column]) ~= tostring(value) then
                        matches = false
                        break
                    end
                end

                if matches then
                    for _, setClause in ipairs(setClauses) do
                        local setColumn = setClause.column
                        local setValue = setClause.value

                        record[setColumn] = setValue
                    end
                    updated = true
                end
            end

            if not updated then
                error("No matching records found to update.")
            end

            return currentData
        end)
    end)

    if updateSuccess then
        return true, "[rSQL] Records updated successfully."
    else
        return false, generateError(functionName, "Failed to update records: " .. tostring(updateError))
    end
end

--[[
    Deletes records from a table based on conditions.

    @function delete
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to delete from.
    @param conditions table? - A table of conditions for filtering records.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.delete(self: Types.DatastoreSQLConnection, tableName: string, conditions: table?): (boolean, string?)
    local functionName = "DatastoreSQL.delete"

    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if conditions then
        for _, condition in ipairs(conditions) do
            condition.value = self:stripQuotes(condition.value) 
        end
    end

    local updateSuccess, updateError = pcall(function()
        self.datastore:UpdateAsync(tableName, function(currentData)
            if not currentData then
                error("Table '" .. tableName .. "' does not exist.")
            end

            local originalCount = #currentData
            local filteredData = {}

            for _, record in ipairs(currentData) do
                local matches = true

                for key, value in pairs(record) do
                    record[key] = self:stripQuotes(value) 
                end

                if conditions then
                    for _, condition in ipairs(conditions) do
                        if tostring(record[condition.column]) ~= condition.value then
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
                error("No matching records found to delete.")
            end

            return filteredData
        end)
    end)

    if updateSuccess then
        return true, "[rSQL] Records deleted successfully."
    else
        return false, generateError(functionName, "Failed to delete records: " .. tostring(updateError))
    end
end


--[[
    Splits a string by a given separator.

    @function split
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param inputStr string - The string to split.
    @param sep string - The separator to split by.
    @return table - A table of split substrings.
]]
function DatastoreSQL.split(self: Types.DatastoreSQLConnection, inputStr: string, sep: string): table
    local result: table = {}
    for str in string.gmatch(inputStr, "([^" .. sep .. "]+)") do
        table.insert(result, self:trim(str))
    end
    return result
end

--[[
    Trims leading and trailing whitespace from a string.

    @function trim
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param s string - The string to trim.
    @return string - The trimmed string.
]]
function DatastoreSQL.trim(self: Types.DatastoreSQLConnection, s: string): string
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--[[
    Parses the WHERE clause into a table of conditions.

    @function parseConditions
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param conditionStr string - The WHERE clause string to parse.
    @return table - A table containing the parsed conditions.
]]
function DatastoreSQL.parseConditions(self: Types.DatastoreSQLConnection, conditionStr: string): table
    local functionName = "DatastoreSQL.parseConditions"
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
    Removes surrounding quotes from a string.

    @function stripQuotes
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param s string - The string to strip quotes from.
    @return string - The unquoted string.
]]
function DatastoreSQL.stripQuotes(self: Types.DatastoreSQLConnection, s: string): string
    return s:gsub("^'(.-)'$", "%1")
end

--[[
    Parses the SET clause of an UPDATE statement into a table of key-value pairs.

    @function parseSetClause
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param setStr string - The SET clause string to parse.
    @return table - A table containing the parsed SET clauses.
]]
function DatastoreSQL.parseSetClause(self: Types.DatastoreSQLConnection, setStr: string): table
    local setClauses = {}
    for key, value in string.gmatch(setStr, "(%w+)%s*=%s*([^,]+)") do
        setClauses[key] = self:stripQuotes(value:match("^%s*(.-)%s*$"))
    end
    if next(setClauses) == nil then
        error("Failed to parse SET clause: No valid key-value pairs found.")
    end
    return setClauses
end

--[[
    Adds a new column to an existing table.

    @function alterTableAddColumn
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to alter.
    @param columnDetails table - A table containing the column name and type.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.alterTableAddColumn(self: Types.DatastoreSQLConnection, tableName: string, columnDetails: table): (boolean, string?)
    local functionName = "DatastoreSQL.alterTableAddColumn"
    local columnName, columnType = columnDetails[1], columnDetails[2]

    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columnName or #columnName == 0 then
        return false, generateError(functionName, "Column name cannot be empty.")
    end

    local updateSuccess, updateError = pcall(function()
        self.datastore:UpdateAsync(tableName, function(currentData)
            if not currentData then
                error("Table '" .. tableName .. "' does not exist.")
            end

            for _, record in ipairs(currentData) do
                record[columnName] = nil
            end

            return currentData
        end)
    end)

    if updateSuccess then
        return true, string.format("[rSQL] Column '%s' added to table '%s' successfully.", columnName, tableName)
    else
        return false, generateError(functionName, "Failed to add column: " .. tostring(updateError))
    end
end

--[[
    Drops an existing column from a table.

    @function alterTableDropColumn
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to alter.
    @param columnDetails table - The table of the column to drop.
    @return boolean, string? - Success status and a message.
]]
function DatastoreSQL.alterTableDropColumn(self: Types.DatastoreSQLConnection, tableName: string, columnDetails : table): (boolean, string?)
    local functionName = "DatastoreSQL.alterTableDropColumn"
    local columnName = columnDetails[1]

    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columnName or #columnName == 0 then
        return false, generateError(functionName, "Column name cannot be empty.")
    end

    local updateSuccess, updateError = pcall(function()
        self.datastore:UpdateAsync(tableName, function(currentData)
            if not currentData then
                error("Table '" .. tableName .. "' does not exist.")
            end

            for _, record in ipairs(currentData) do
                record[columnName] = nil
            end

            return currentData
        end)
    end)

    if updateSuccess then
        return true, string.format("[rSQL] Column '%s' dropped from table '%s' successfully.", columnName, tableName)
    else
        return false, generateError(functionName, "Failed to drop column: " .. tostring(updateError))
    end
end

return DatastoreSQL
