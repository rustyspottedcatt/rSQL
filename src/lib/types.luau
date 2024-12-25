--[[
    Types Module

    @module Types
]]

export type SQLQuery = string

export type SQLQueryResult = { any }

export type DatastoreSQLConfig = {
    allowOverwrite: boolean,
    allowInsert: boolean,
    allowSelect: boolean,
    allowUpdate: boolean,
    allowDelete: boolean,
    allowCreate: boolean,
    allowDrop: boolean,
    allowTruncate: boolean,
    allowAlter: boolean,
    allowTransaction: boolean,
}

export type Status = "Started" | "Resolved" | "Rejected" | "Cancelled"

export type Promise = {
    andThen: (self: Promise, successHandler: (...any) -> ...any, failureHandler: ((...any) -> ...any)?) -> Promise,
    andThenCall: <T...>(self: Promise, callback: (T...) -> ...any, T...) -> any,
    andThenReturn: (self: Promise, ...any) -> Promise,

    await: (self: Promise) -> (boolean, ...any),
    awaitStatus: (self: Promise) -> (Status, ...any),

    cancel: (self: Promise) -> (),
    catch: (self: Promise, failureHandler: (...any) -> ...any) -> Promise,
    expect: (self: Promise) -> ...any,

    finally: (self: Promise, finallyHandler: (status: Status) -> ...any) -> Promise,
    finallyCall: <T...>(self: Promise, callback: (T...) -> ...any, T...) -> Promise,
    finallyReturn: (self: Promise, ...any) -> Promise,

    getStatus: (self: Promise) -> Status,
    now: (self: Promise, rejectionValue: any?) -> Promise,
    tap: (self: Promise, tapHandler: (...any) -> ...any) -> Promise,
    timeout: (self: Promise, seconds: number, rejectionValue: any?) -> Promise,
}

export type TypedPromise<T...> = {
    andThen: (self: Promise, successHandler: (T...) -> ...any, failureHandler: ((...any) -> ...any)?) -> Promise,
    andThenCall: <T...>(self: Promise, callback: (T...) -> ...any, T...) -> Promise,
    andThenReturn: (self: Promise, ...any) -> Promise,

    await: (self: Promise) -> (boolean, T...),
    awaitStatus: (self: Promise) -> (Status, T...),

    cancel: (self: Promise) -> (),
    catch: (self: Promise, failureHandler: (...any) -> ...any) -> Promise,
    expect: (self: Promise) -> T...,

    finally: (self: Promise, finallyHandler: (status: Status) -> ...any) -> Promise,
    finallyCall: <T...>(self: Promise, callback: (T...) -> ...any, T...) -> Promise,
    finallyReturn: (self: Promise, ...any) -> Promise,

    getStatus: (self: Promise) -> Status,
    now: (self: Promise, rejectionValue: any?) -> Promise,
    tap: (self: Promise, tapHandler: (T...) -> ...any) -> TypedPromise<T...>,
    timeout: (self: Promise, seconds: number, rejectionValue: any?) -> Promise,
}

export type DataStoreService = {
    GetDataStore: (self: DataStoreService, name: string) -> DataStore,
}

export type DataStore = {
    SetAsync: (self: DataStore, key: string, value: any) -> nil,
    GetAsync: (self: DataStore, key: string) -> any,
    UpdateAsync: (self: DataStore, key: string, transformFunction: (oldValue: any) -> any) -> any,
    RemoveAsync: (self: DataStore, key: string) -> nil,
}

export type DatastoreSQLConnection = {
    datastore: DataStore,
    config: DatastoreSQLConfig,
    query: (self: DatastoreSQLConnection, query: SQLQuery) -> TypedPromise<SQLQueryResult>,
    parseSQL: (self: DatastoreSQLConnection, query: SQLQuery) -> any,
    createTable: (self: DatastoreSQLConnection, tableName: string, columns: table) -> (boolean, string?),
    dropTable: (self: DatastoreSQLConnection, tableName: string) -> (boolean, string?),
    truncateTable: (self: DatastoreSQLConnection, tableName: string) -> (boolean, string?),
    insert: (self: DatastoreSQLConnection, tableName: string, columns: table, values: table) -> (boolean, string?),
    select: (self: DatastoreSQLConnection, tableName: string, columns: table, conditions: table?) -> (SQLQueryResult?, string?),
    update: (self: DatastoreSQLConnection, tableName: string, setClauses: table, conditions: table?) -> (boolean, string?),
    delete: (self: DatastoreSQLConnection, tableName: string, conditions: table?) -> (boolean, string?),
    split: (self: DatastoreSQLConnection, inputStr: string, sep: string) -> table,
    trim: (self: DatastoreSQLConnection, s: string) -> string,
    parseConditions: (self: DatastoreSQLConnection, conditionStr: string) -> table,
    stripQuotes: (self: DatastoreSQLConnection, s: string) -> string,
    parseSetClause: (self: DatastoreSQLConnection, setStr: string) -> table,
}

export type ProfileSQLConnection = {
    profilesTable: table,
    config: DatastoreSQLConfig,
    transaction: table?, -- Added to handle transactions
    query: (self: ProfileSQLConnection, query: SQLQuery) -> TypedPromise<SQLQueryResult>,
    parseSQL: (self: ProfileSQLConnection, query: SQLQuery) -> (string?, string?, table?, string?, table?, table?),
    insert: (self: ProfileSQLConnection, tableName: string, columns: table, values: table) -> (boolean, string?),
    select: (self: ProfileSQLConnection, tableName: string, columns: table, conditions: table?, options: table?) -> (SQLQueryResult?, string?),
    update: (self: ProfileSQLConnection, tableName: string, setClauses: table, conditions: table?) -> (boolean, string?),
    delete: (self: ProfileSQLConnection, tableName: string, conditions: table?) -> (boolean, string?),
    createTable: (self: ProfileSQLConnection, tableName: string, schema: table) -> (boolean, string?),
    dropTable: (self: ProfileSQLConnection, tableName: string) -> (boolean, string?),
    alterTable: (self: ProfileSQLConnection, tableName: string, alteration: table) -> (boolean, string?),
    truncateTable: (self: ProfileSQLConnection, tableName: string) -> (boolean, string?),
    beginTransaction: (self: ProfileSQLConnection) -> (boolean, string?),
    commitTransaction: (self: ProfileSQLConnection) -> (boolean, string?),
    rollbackTransaction: (self: ProfileSQLConnection) -> (boolean, string?),
    split: (self: ProfileSQLConnection, inputStr: string, sep: string) -> table,
    trim: (self: ProfileSQLConnection, s: string) -> string,
    parseConditions: (self: ProfileSQLConnection, conditionStr: string) -> table,
    parseSetClause: (self: ProfileSQLConnection, setStr: string) -> table,
}

export type DatastoreSQL = {
    query: (self: DatastoreSQLConnection, query: SQLQuery) -> TypedPromise<SQLQueryResult>,
    parseSQL: (self: DatastoreSQLConnection, query: SQLQuery) -> (string?, string?, table?, string?, table?),
    insert: (self: DatastoreSQLConnection, tableName: string, columns: table, values: table) -> (boolean, string?),
    select: (self: DatastoreSQLConnection, tableName: string, columns: table, conditions: table?) -> (SQLQueryResult?, string?),
    update: (self: DatastoreSQLConnection, tableName: string, setClauses: table, conditions: table?) -> (boolean, string?),
    delete: (self: DatastoreSQLConnection, tableName: string, conditions: table?) -> (boolean, string?),
    split: (self: DatastoreSQLConnection, inputStr: string, sep: string) -> table,
    trim: (self: DatastoreSQLConnection, s: string) -> string,
    parseConditions: (self: DatastoreSQLConnection, conditionStr: string) -> table,
    parseSetClause: (self: DatastoreSQLConnection, setStr: string) -> table,
    connect: (self: DatastoreSQL, datastore: DataStore, config: DatastoreSQLConfig) -> DatastoreSQLConnection,
}

return {}
