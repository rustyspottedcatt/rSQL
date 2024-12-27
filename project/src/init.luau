--[[
    https://www.roblox.com/users/1539582829/profile
    https://twitter.com/zzen_a

    MIT License

    Copyright (c) 2024 rustyspotted

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

--[[
    rSQL Module
    A module to handle SQL-like operations with Roblox's DataStoreService.

    @module rSQL
]]

local Types = require(script.lib.types)
local Promise = require(script.Parent.Parent.Packages.promise)
local Signal = require(script.Parent.Parent.Packages.signal)
local DatastoreSQL = require(script.components.DatastoreSQL)
local ProfileSQL = require(script.components.ProfileSQL)

local rSQL = {}
rSQL.__index = rSQL

rSQL.Promise = Promise
rSQL.Signal = Signal
rSQL.Types = Types

--[[
    Establishes a connection to the DataStore with the provided configuration.

    @function connect
    @param datastore Types.DataStore - The DataStore instance to connect to.
    @param config Types.DatastoreSQLConfig - Configuration settings for the SQL module.
    @return Types.TypedPromise<Types.SQLConnection> - A promise that resolves with the SQL connection.
]]
function rSQL:connect(datastore: Types.DataStore, config: Types.DatastoreSQLConfig): Types.TypedPromise<Types.DatastoreSQLConnection>
    return Promise.new(function(resolve, reject)
        if not datastore then
            return reject("[rSQL] Unexpected `nil` value for `datastore`, expected DataStore instance.")
        end
        if not config then
            return reject("[rSQL] Unexpected `nil` value for `config`, expected SQLModuleConfig instance.")
        end

        local SQLConnection = setmetatable({
            datastore = datastore :: Types.DataStore,
            config = config :: Types.DatastoreSQLConfig
        }, { __index = DatastoreSQL })

        return resolve(SQLConnection :: Types.DatastoreSQLConnection)
    end)
end

--[[
    Establishes a connection to the Profile Service with the provided configuration.

    @function connectToProfileService
    @param profilesTable table - The table containing profile data.
    @param config Types.DatastoreSQLConfig - Configuration settings for the SQL module.
    @return Types.TypedPromise<Types.ProfileSQLConnection> - A promise that resolves with the Profile SQL connection.
]]

function rSQL:connectToProfileService(profilesTable : {any}, config: Types.DatastoreSQLConfig): Types.TypedPromise<Types.ProfileSQLConnection>
    return Promise.new(function(resolve, reject)
        if not profilesTable or (typeof(profilesTable) ~= "table") then
            return reject("[rSQL] Unexpected `nil` value for `profilesTable`, expected table.")
        end
        if not config then
            return reject("[rSQL] Unexpected `nil` value for `config`, expected SQLModuleConfig instance.")
        end

        local SQLConnection = setmetatable({
            profilesTable = profilesTable :: {any},
            config = config :: Types.DatastoreSQLConfig
        }, { __index = ProfileSQL })

        return resolve(SQLConnection :: Types.ProfileSQLConnection)
    end)
end

--[[
    Establishes a connection to Datakeep with the provided configuration.

    @function connectToDatakeep
    @param profilesTable table - The table containing profile data.
    @param config Types.DatastoreSQLConfig - Configuration settings for the SQL module.
    @return Types.TypedPromise<Types.ProfileSQLConnection> - A promise that resolves with the Profile SQL connection.
]]

function rSQL:connectToDatakeep(profilesTable : {any}, config: Types.DatastoreSQLConfig): Types.TypedPromise<Types.ProfileSQLConnection>
    return Promise.new(function(resolve, reject)
        if not profilesTable or typeof(profilesTable) ~= "table" then
            return reject("[rSQL] Unexpected `nil` value for `profilesTable`, expected table.")
        end
        if not config then
            return reject("[rSQL] Unexpected `nil` value for `config`, expected SQLModuleConfig instance.")
        end

        local SQLConnection = setmetatable({
            profilesTable = profilesTable :: {any},
            config = config :: Types.DatastoreSQLConfig
        }, { __index = ProfileSQL })

        return resolve(SQLConnection :: Types.ProfileSQLConnection)
    end)
end

return rSQL
