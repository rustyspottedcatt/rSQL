-- ProfileSQL.luau

local Types = require(script.Parent.Parent.lib.types)
local SQLParser = require(script.Parent.SQLParser)
local Promise = require(script.Parent.Parent.Parent.Parent.Packages.promise)

local ProfileSQL = {}
ProfileSQL.__index = ProfileSQL

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
local function _extractCommand(query)
    local command = query:match("^(%w+)")
    return command and command:upper() or ""
end

--[[ 
    Executes an SQL query and returns a promise with the result.
    @function query
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param query string - The SQL query to execute.
    @return Types.TypedPromise<Types.SQLQueryResult> - A promise that resolves with the query result or rejects with an error.
]]
function ProfileSQL.query(self: Types.ProfileSQLConnection, query: Types.SQLQuery)
    return Promise.new(function(resolve, reject)
        local functionName = "ProfileSQL.query"

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
            querySuccess, queryData = self:select(parsedQuery.tableName, parsedQuery.columns, parsedQuery.whereClause, parsedQuery.orderBy, parsedQuery.limit, parsedQuery.distinct)
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
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param query string - The SQL query to parse.
    @return table - Parsed AST representing the query.
]]
function ProfileSQL.parseSQL(self: Types.ProfileSQLConnection, query: Types.SQLQuery)
    local functionName = "ProfileSQL.parseSQL"

    local success, astOrError = pcall(SQLParser.parse, normalizeSQL(query))
    if not success then
        error(generateError(functionName, "Failed to parse SQL query: " .. tostring(astOrError)))
    end

    return astOrError
end

--[[ 
    Creates a new table in the profiles table.
    @function createTable
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to create.
    @param columns table - A table of column names.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.createTable(self: Types.ProfileSQLConnection, tableName: string, columns: {any}): (boolean, string?)
    local functionName = "ProfileSQL.createTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columns or #columns == 0 then
        return false, generateError(functionName, "Columns must be specified for CREATE TABLE.")
    end

    if self.profilesTable.Data[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' already exists.")
    end

    local updateSuccess, updateError = pcall(function()
        self.profilesTable.Data[tableName] = {
            _schema = columns,
            rows = {}
        }
    end)

    if updateSuccess then
        return true, "[rSQL] Table '" .. tableName .. "' created successfully."
    else
        return false, generateError(functionName, "Failed to create table: " .. tostring(updateError))
    end
end

--[[ 
    Drops an existing table from the profiles table.
    @function dropTable
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to drop.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.dropTable(self: Types.ProfileSQLConnection, tableName: string): (boolean, string?)
    local functionName = "ProfileSQL.dropTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not self.profilesTable.Data[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    local updateSuccess, updateError = pcall(function()
        self.profilesTable.Data[tableName] = nil 
    end)

    if updateSuccess then
        return true, "[rSQL] Table '" .. tableName .. "' dropped successfully."
    else
        return false, generateError(functionName, "Failed to drop table: " .. tostring(updateError))
    end
end

--[[ 
    Truncates an existing table by removing all its records.
    @function truncateTable
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to truncate.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.truncateTable(self: Types.ProfileSQLConnection, tableName: string): (boolean, string?)
    local functionName = "ProfileSQL.truncateTable"
    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not self.profilesTable.Data[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    local updateSuccess, updateError = pcall(function()
        self.profilesTable.Data[tableName].rows = {}
    end)

    if updateSuccess then
        return true, "[rSQL] Table '" .. tableName .. "' truncated successfully."
    else
        return false, generateError(functionName, "Failed to truncate table: " .. tostring(updateError))
    end
end

--[[ 
    Inserts a new record into a table in the profiles table.
    @function insert
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to insert into.
    @param columns table - A table of column names.
    @param values table - A table of values corresponding to the columns.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.insert(self: Types.ProfileSQLConnection, tableName: string, columns: {any}, values: {any}): (boolean, string?)
    local functionName = "ProfileSQL.insert"
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
        local tableData = self.profilesTable.Data[tableName]
        if not tableData then
            error("Table '" .. tableName .. "' does not exist.")
        end

        -- Check for duplicate primary key
        for _, existingRecord in ipairs(tableData.rows) do
            if existingRecord[primaryKeyColumn] == primaryKeyValue then
                error("Duplicate primary key value '" .. tostring(primaryKeyValue) .. "' for column '" .. primaryKeyColumn .. "'.")
            end
        end

        table.insert(tableData.rows, record)
    end)

    if updateSuccess then
        return true, "[rSQL] Data inserted successfully."
    else
        return false, generateError(functionName, "Failed to insert data: " .. tostring(updateError))
    end
end

--[[ 
    Selects records from a table in the profiles table based on conditions.
    @function select
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to select from.
    @param columns table - A table of column names to retrieve.
    @param conditions table? - A table of conditions for filtering records.
    @param orderBy table? - A table of columns to order the results by.
    @param limit number? - The maximum number of records to return.
    @param distinct boolean? - Whether to return distinct records.
    @return (boolean, any) - SQL query result.
]]
function ProfileSQL.select(self: Types.ProfileSQLConnection, tableName: string, columns: {any}, conditions: {any}?, orderBy: {any}?, limit: number?, distinct: boolean?): (boolean, any?)
    local functionName = "ProfileSQL.select"
    local tableData = self.profilesTable.Data[tableName]

    if not tableData then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    local results = {}

    -- Apply Conditions
    for _, record in ipairs(tableData.rows) do
        local match = true

        if conditions then
            for _, condition in ipairs(conditions) do
                local recordValue = tostring(record[condition.column] or "")
                local conditionValue = tostring(condition.value or "")

                -- Handle numeric comparisons if applicable
                local numRecord = tonumber(recordValue)
                local numCondition = tonumber(conditionValue)

                if numRecord and numCondition then
                    recordValue = numRecord
                    conditionValue = numCondition
                end

                if condition.operator == "=" or condition.operator == "==" then
                    if recordValue ~= conditionValue then
                        match = false
                        break
                    end
                elseif condition.operator == "!=" then
                    if recordValue == conditionValue then
                        match = false
                        break
                    end
                elseif condition.operator == ">" then
                    if not (recordValue > conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == "<" then
                    if not (recordValue < conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == ">=" then
                    if not (recordValue >= conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == "<=" then
                    if not (recordValue <= conditionValue) then
                        match = false
                        break
                    end
                else
                    warn("[rSQL] Unsupported operator in condition:", condition.operator)
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

    -- Apply Distinct
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

    -- Apply Ordering
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

    -- Apply Limit
    if limit and limit > 0 then
        while #results > limit do
            table.remove(results)
        end
    end

    if #results == 0 then
        return false, generateError(functionName, "No matching records found.")
    else
        return true, results
    end
end

--[[ 
    Updates records in a table based on conditions.
    @function update
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to update.
    @param setClauses table - A table of key-value pairs to set.
    @param conditions table? - A table of conditions for filtering records.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.update(self: Types.ProfileSQLConnection, tableName: string, setClauses: {any}, conditions: {any}?): (boolean, string?)
    local functionName = "ProfileSQL.update"

    if not self.profilesTable.Data[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    local updated = false

    for _, record in ipairs(self.profilesTable.Data[tableName].rows) do
        local match = true

        if conditions then
            for _, condition in ipairs(conditions) do
                local recordValue = tostring(record[condition.column] or "")
                local conditionValue = tostring(condition.value or "")

                -- Handle numeric comparisons if applicable
                local numRecord = tonumber(recordValue)
                local numCondition = tonumber(conditionValue)

                if numRecord and numCondition then
                    recordValue = numRecord
                    conditionValue = numCondition
                end

                if condition.operator == "=" or condition.operator == "==" then
                    if recordValue ~= conditionValue then
                        match = false
                        break
                    end
                elseif condition.operator == "!=" then
                    if recordValue == conditionValue then
                        match = false
                        break
                    end
                elseif condition.operator == ">" then
                    if not (recordValue > conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == "<" then
                    if not (recordValue < conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == ">=" then
                    if not (recordValue >= conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == "<=" then
                    if not (recordValue <= conditionValue) then
                        match = false
                        break
                    end
                else
                    warn("[rSQL] Unsupported operator in condition:", condition.operator)
                    match = false
                    break
                end
            end
        end

        if match then
            for _, setClause in ipairs(setClauses) do
                local column = setClause.column
                local value = setClause.value

                if self.profilesTable.Data[tableName]._schema then
                    if not table.find(self.profilesTable.Data[tableName]._schema, column) then
                        return false, generateError(functionName, "Column '" .. column .. "' does not exist in table '" .. tableName .. "'.")
                    end
                end

                if typeof(value) == "string" then
                    value = self:stripQuotes(value)
                end

                record[column] = value
            end
            updated = true
        end
    end

    if updated then
        return true, "[rSQL] Records updated successfully."
    else
        return false, generateError(functionName, "No matching records found to update.")
    end
end

--[[ 
    Deletes records from a table based on conditions.
    @function delete
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to delete from.
    @param conditions table? - A table of conditions for filtering records.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.delete(self: Types.ProfileSQLConnection, tableName: string, conditions: {any}?): (boolean, string?)
    local functionName = "ProfileSQL.delete"

    if not self.profilesTable.Data[tableName] then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    local originalCount = #self.profilesTable.Data[tableName].rows
    local filteredRows = {}

    for _, record in ipairs(self.profilesTable.Data[tableName].rows) do
        local match = true

        if conditions then
            for _, condition in ipairs(conditions) do
                local recordValue = tostring(record[condition.column] or "")
                local conditionValue = tostring(condition.value or "")

                -- Handle numeric comparisons if applicable
                local numRecord = tonumber(recordValue)
                local numCondition = tonumber(conditionValue)

                if numRecord and numCondition then
                    recordValue = numRecord
                    conditionValue = numCondition
                end

                if condition.operator == "=" or condition.operator == "==" then
                    if recordValue ~= conditionValue then
                        match = false
                        break
                    end
                elseif condition.operator == "!=" then
                    if recordValue == conditionValue then
                        match = false
                        break
                    end
                elseif condition.operator == ">" then
                    if not (recordValue > conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == "<" then
                    if not (recordValue < conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == ">=" then
                    if not (recordValue >= conditionValue) then
                        match = false
                        break
                    end
                elseif condition.operator == "<=" then
                    if not (recordValue <= conditionValue) then
                        match = false
                        break
                    end
                else
                    warn("[rSQL] Unsupported operator in condition:", condition.operator)
                    match = false
                    break
                end
            end
        end

        if not match then
            table.insert(filteredRows, record)
        end
    end

    if conditions and #filteredRows == originalCount then
        return false, generateError(functionName, "No matching records found to delete.")
    end

    self.profilesTable.Data[tableName].rows = filteredRows

    return true, "[rSQL] Records deleted successfully."
end

--[[ 
    Adds a new column to an existing table.
    @function alterTableAddColumn
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to alter.
    @param columnDetails table - A table containing the column name and type.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.alterTableAddColumn(self: Types.ProfileSQLConnection, tableName: string, columnDetails: {any}): (boolean, string?)
    local functionName = "ProfileSQL.alterTableAddColumn"
    local columnName, _columnType = columnDetails[1], columnDetails[2]

    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columnName or #columnName == 0 then
        return false, generateError(functionName, "Column name cannot be empty.")
    end

    local tableData = self.profilesTable.Data[tableName]
    if not tableData then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    if table.find(tableData._schema, columnName) then
        return false, generateError(functionName, "Column '" .. columnName .. "' already exists in table '" .. tableName .. "'.")
    end

    local updateSuccess, updateError = pcall(function()
        table.insert(tableData._schema, columnName)
        for _, record in ipairs(tableData.rows) do
            record[columnName] = nil
        end
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
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param tableName string - The name of the table to alter.
    @param columnDetails table - The table of the column to drop.
    @return boolean, string? - Success status and a message.
]]
function ProfileSQL.alterTableDropColumn(self: Types.ProfileSQLConnection, tableName: string, columnDetails : {any}): (boolean, string?)
    local functionName = "ProfileSQL.alterTableDropColumn"
    local columnName = columnDetails[1]

    if not tableName or #tableName == 0 then
        return false, generateError(functionName, "Table name cannot be empty.")
    end

    if not columnName or #columnName == 0 then
        return false, generateError(functionName, "Column name cannot be empty.")
    end

    local tableData = self.profilesTable.Data[tableName]
    if not tableData then
        return false, generateError(functionName, "Table '" .. tableName .. "' does not exist.")
    end

    if not table.find(tableData._schema, columnName) then
        return false, generateError(functionName, "Column '" .. columnName .. "' does not exist in table '" .. tableName .. "'.")
    end

    local updateSuccess, updateError = pcall(function()
        -- Remove from schema
        for i, col in ipairs(tableData._schema) do
            if col == columnName then
                table.remove(tableData._schema, i)
                break
            end
        end

        -- Remove from all records
        for _, record in ipairs(tableData.rows) do
            record[columnName] = nil
        end
    end)

    if updateSuccess then
        return true, string.format("[rSQL] Column '%s' dropped from table '%s' successfully.", columnName, tableName)
    else
        return false, generateError(functionName, "Failed to drop column: " .. tostring(updateError))
    end
end

--[[
    Removes surrounding quotes from a string.

    @function stripQuotes
    @param self Types.DatastoreSQLConnection - The SQL connection instance.
    @param s string - The string to strip quotes from.
    @return string - The unquoted string.
]]
function ProfileSQL.stripQuotes(self: Types.DatastoreSQLConnection, value: string): string
    local stripped = string.gsub(value, [["([^"]*)"]], "%1")
    stripped = string.gsub(stripped, [[%'([^']*)%']], "%1")
    
    return stripped
end

--[[ 
    Splits a string by a given separator.
    @function split
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param inputStr string - The string to split.
    @param sep string - The separator to split by.
    @return table - A table of split substrings.
]]
function ProfileSQL.split(self: Types.ProfileSQLConnection, inputStr: string, sep: string): {any}
    local result = {}
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
    Parses the WHERE clause into a table of conditions.
    @function parseConditions
    @param self Types.ProfileSQLConnection - The SQL connection instance.
    @param conditionStr string - The WHERE clause string to parse.
    @return table - A table containing the parsed conditions.
]]
function ProfileSQL.parseConditions(self: Types.ProfileSQLConnection, conditionStr: string): {any}
    local functionName = "ProfileSQL.parseConditions"
    local conditions = {}
    for column, operator, value in string.gmatch(conditionStr, "(%w+)%s*([=!<>]+)%s*'([^']*)'") do
        table.insert(conditions, { column = column, operator = operator, value = value })
    end
    for column, operator, value in string.gmatch(conditionStr, '(%w+)%s*([=!<>]+)%s*"([^"]*)"') do
        table.insert(conditions, { column = column, operator = operator, value = value })
    end
    if #conditions == 0 then
        error(generateError(functionName, "Failed to parse conditions: No valid key-value pairs found."))
    end
    return conditions
end

return ProfileSQL
