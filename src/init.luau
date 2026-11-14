--!strict
--[[
	rSQL: SQL for Roblox DataStores, profiles and in-memory tables.

	    local db = rSQL.datastore(DataStoreService:GetDataStore("Game"))
	    db:exec("CREATE TABLE IF NOT EXISTS Players (UserId INTEGER PRIMARY KEY, Coins INTEGER DEFAULT 0)")
	    db:exec("INSERT INTO Players (UserId) VALUES (?)", { player.UserId })
	    db:exec("UPDATE Players SET Coins = Coins + ? WHERE UserId = ?", { 50, player.UserId })

	Layers, each using only the ones below it:

	    rSQL (this file), Legacy     public API, 1.x compatibility
	    Database                     handles, cache, permissions, stats
	    Engine                       planner, executor, expressions, schemas, types
	    SQL                          lexer, parser, syntax tree, errors
	    Storage                      memory / profile / DataStore backends
	    Platform, Util               runtime adapter, hashing, logging

	MIT License. Copyright (c) 2024-2026 rustyspotted.
]]

local Version = require("@self/Version")
local Platform = require("@self/Platform")
local Parser = require("@self/SQL/Parser")
local Lexer = require("@self/SQL/Lexer")
local Database = require("@self/Database")
local Promise = require("@self/Promise")
local TableAdapter = require("@self/Storage/TableAdapter")
local DataStoreAdapter = require("@self/Storage/DataStoreAdapter")
local Legacy = require("@self/Legacy")
local Logger = require("@self/Util/Logger")

export type Database = Database.Database
export type Result = Database.Result
export type Options = Database.Options

local rSQL = {
	version = Version.string,
	NULL = Database.NULL,
	Promise = Promise,
	Logger = Logger,
	Platform = Platform,
	adapters = {
		DataStore = DataStoreAdapter.new,
		Table = TableAdapter.new,
	},
}

local DATASTORE_KEYS =
	{ layout = true, shards = true, retries = true, backoffSeconds = true, prefix = true, sleep = true }

local function split(options: { [string]: any }?): ({ [string]: any }, { [string]: any })
	local storage, database = {}, {}
	local given: { [string]: any } = options or {}
	for k, v in given do
		if DATASTORE_KEYS[k] then
			storage[k] = v
		else
			database[k] = v
		end
	end
	return storage, database
end

-- Opens a database on any storage adapter.
function rSQL.open(adapter: any, options: Database.Options?): Database.Database
	return Database.new(adapter, options)
end

-- In-memory database (item tables, loot tables, caches, tests). Nothing is saved.
function rSQL.memory(options: Database.Options?): Database.Database
	return Database.new(TableAdapter.new({}, { kind = "memory", indexed = true }), options)
end

--[=[
	Database stored in a DataStore. Options: shards (8), layout ("sharded" or
	"single"), retries (3), backoffSeconds (0.5), prefix, plus any
	Database option (permissions, onQuery, ...).
]=]
function rSQL.datastore(dataStore: any, options: { [string]: any }?): Database.Database
	local storage, database = split(options)
	return Database.new(DataStoreAdapter.new(dataStore, storage), database :: any)
end

--[=[
	Database stored inside a player's profile data (ProfileService,
	ProfileStore or DataKeep). The profile library saves and session-locks
	it; rSQL only reads and writes profile.Data.
]=]
function rSQL.profile(profile: any, options: Database.Options?): Database.Database
	return Database.new(TableAdapter.new(TableAdapter.profileRoot(profile), { kind = "profile" }), options)
end

-- Parses a statement without running it (for tooling and tests).
function rSQL.parse(sql: string)
	return Parser.parse(sql)
end

function rSQL.tokenize(sql: string)
	return Lexer.tokenize(sql)
end

-- 1.x API ---------------------------------------------------------------------------

function rSQL.connect(_self: any, dataStore: any, config: any)
	return Legacy.connect(dataStore, config)
end

function rSQL.connectToProfileService(_self: any, profile: any, config: any)
	return Legacy.connectToProfile(profile, config)
end

function rSQL.connectToDatakeep(_self: any, keep: any, config: any)
	return Legacy.connectToProfile(keep, config)
end

return rSQL
