
local MockDataStore = require(script.Parent.Mocks.MockDataStore)
local rSQL = require(script.Parent.Parent)
local SQLModule = require(script.Parent.Parent.components.SQL)
local Promise = require(script.Parent.Parent.Parent.Parent.Packages.promise)

local Types = {
    SQLModule = {},
    DataStore = {},
    SQLModuleConfig = {},
    SQLConnection = {}
}

return function ()
    describe("rSQL Module", function()
        it("should successfully connect with valid datastore and config", function()
            local mockDataStore = MockDataStore.new()
            local config = {
                allowDelete = true,
                allowUpdate = true,
                allowInsert = true,
                allowSelect = true,
                allowOverwrite = true,
            }
    
            local connectionPromise = rSQL:connect(mockDataStore, config)
            local resolved, connection = false, nil
    
            connectionPromise:andThen(function(conn)
                resolved = true
                connection = conn
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(resolved).to.equal(true)
            expect(connection).to.be.ok()
            expect(getmetatable(connection).__index).to.equal(SQLModule) -- Fixed metatable check
        end)
    
        it("should reject when datastore is nil", function()
            local config = {
                allowDelete = true,
                allowUpdate = true,
                allowInsert = true,
                allowSelect = true,
                allowOverwrite = true,
            }
    
            local connectionPromise = rSQL:connect(nil, config)
            local rejected, errorMessage = false, nil
    
            connectionPromise:catch(function(err)
                rejected = true
                errorMessage = err
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(rejected).to.equal(true)
            expect(errorMessage).to.equal("[rSQL] Unexpected `nil` value for `datastore`, expected DataStore instance.")
        end)
    
        it("should reject when config is nil", function()
            local mockDataStore = MockDataStore.new()
    
            local connectionPromise = rSQL:connect(mockDataStore, nil)
            local rejected, errorMessage = false, nil
    
            connectionPromise:catch(function(err)
                rejected = true
                errorMessage = err
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(rejected).to.equal(true)
            expect(errorMessage).to.equal("[rSQL] Unexpected `nil` value for `config`, expected SQLModuleConfig instance.")
        end)
    end)
    
    describe("SQLModule CRUD Operations", function()
        local mockDataStore = MockDataStore.new()
        local config = {
            allowDelete = true,
            allowUpdate = true,
            allowInsert = true,
            allowSelect = true,
            allowOverwrite = true,
        }
        local connection = setmetatable({ datastore = mockDataStore, config = config }, { __index = SQLModule })
    
        it("insert should add a new record successfully", function()
            local success, err = connection:insert("Users", {"id", "name"}, {"126", "Dave"})
            expect(success).to.equal(true)
            expect(err).to.equal(nil)
            local users = mockDataStore:GetAsync("Users")
            expect(#users).to.equal(1)
            expect(users[1]).to.deep.equal({id = "126", name = "Dave"})
        end)
    
        it("insert should fail when columns and values mismatch", function()
            local success, err = connection:insert("Users", {"id"}, {"127", "Eve"})
            expect(success).to.equal(false)
            expect(err):to().match("[rSQL][SQLModule.insert] Number of columns and values do not match.")
        end)
    
        it("select should retrieve matching records", function()
            connection:insert("Users", {"id", "name"}, {"128", "Frank"})
            connection:insert("Users", {"id", "name"}, {"129", "Grace"})
            expect(connection:select("Users", {"id", "name"}, {id = "128"})).to.deep.equal({{id = "128", name = "Frank"}})
        end)
    
        it("select should return empty table when no records found", function()
            local results, err = connection:select("Users", {"id", "name"}, {id = "999"})
            expect(results).to.deep.equal({})
            expect(err).to.equal("[rSQL] No records found.")
        end)
    
        it("update should modify existing records", function()
            local success, err = connection:update("Users", {name = "Franklin"}, {id = "128"})
            expect(success).to.equal(true)
            expect(err).to.equal(nil)
            local users = mockDataStore:GetAsync("Users")
            expect(users[1].name).to.equal("Franklin")
        end)
    
        it("update should fail when no matching records", function()
            local success, err = connection:update("Users", {name = "Hannah"}, {id = "999"})
            expect(success).to.equal(false)
            expect(err):to().match("[rSQL][SQLModule.update] No matching records found to update.")
        end)
    
        it("delete should remove matching records", function()
            local success, err = connection:delete("Users", {id = "126"})
            expect(success).to.equal(true)
            expect(err).to.equal(nil)
            local users = mockDataStore:GetAsync("Users")
            expect(#users).to.equal(2)
            expect(users[1].id).to.equal("128")
            expect(users[2].id).to.equal("129")
        end)
    
        it("delete should fail when no matching records", function()
            local success, err = connection:delete("Users", {id = "999"})
            expect(success).to.equal(false)
            expect(err):to().match("[rSQL][SQLModule.delete] No matching records found to delete.")
        end)
    end)
    
    describe("SQLModule.query", function()
        local mockDataStore = MockDataStore.new()
        local config = {
            allowDelete = true,
            allowUpdate = true,
            allowInsert = true,
            allowSelect = true,
            allowOverwrite = true,
        }
        local connection = setmetatable({ datastore = mockDataStore, config = config }, { __index = SQLModule })
    
        mockDataStore:SetAsync("Users", {
            {id = "123", name = "Alice"},
            {id = "124", name = "Bob"},
        })
    
        it("should execute INSERT command successfully", function()
            local insertQuery = "INSERT INTO Users (id, name) VALUES ('125', 'Charlie')"
            local insertPromise = connection:query(insertQuery)
            local resolved, result = false, nil
    
            insertPromise:andThen(function(res)
                resolved = true
                result = res
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(resolved).to.equal(true)
            expect(result).to.equal(true) -- Changed expectation to true for successful insert
    
            local users = mockDataStore:GetAsync("Users")
            expect(#users).to.equal(3)
            expect(users[3]).to.deep.equal({id = "125", name = "Charlie"})
        end)
    
        it("should execute SELECT command successfully", function()
            local selectQuery = "SELECT * FROM Users WHERE id = '123'"
            local selectPromise = connection:query(selectQuery)
            local resolved, result = false, nil
    
            selectPromise:andThen(function(res)
                resolved = true
                result = res
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(resolved).to.equal(true)
            expect(result).to.deep.equal({{id = "123", name = "Alice"}})
        end)
    
        it("should execute UPDATE command successfully", function()
            local updateQuery = "UPDATE Users SET name = 'Alicia' WHERE id = '123'"
            local updatePromise = connection:query(updateQuery)
            local resolved, result = false, nil
    
            updatePromise:andThen(function(res)
                resolved = true
                result = res
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(resolved).to.equal(true)
            expect(result).to.equal(true)
    
            local users = mockDataStore:GetAsync("Users")
            expect(users[1].name).to.equal("Alicia")
        end)
    
        it("should execute DELETE command successfully", function()
            local deleteQuery = "DELETE FROM Users WHERE id = '124'"
            local deletePromise = connection:query(deleteQuery)
            local resolved, result = false, nil
    
            deletePromise:andThen(function(res)
                resolved = true
                result = res
            end)
    
            -- Run all pending promises
            Promise._Scheduler:Drain()
    
            expect(resolved).to.equal(true)
            expect(result).to.equal(true)
    
            local users = mockDataStore:GetAsync("Users")
            expect(#users).to.equal(2)
            expect(users[2].id).to.equal("125")
        end)
    
        it("should reject when executing disallowed command", function()
            connection.config.allowDelete = false
            local deleteQuery = "DELETE FROM Users WHERE id = '125'"
            local deletePromise = connection:query(deleteQuery)
            local rejected, errorMessage = false, nil
    
            deletePromise:catch(function(err)
                rejected = true
                errorMessage = err
            end)
    
            Promise._Scheduler:Drain()
    
            expect(rejected).to.equal(true)
            expect(errorMessage):to().match("Unexpected SQL command, expected INSERT, SELECT, UPDATE or DELETE, OR command is not allowed by config.")
        end)
    end)
end
