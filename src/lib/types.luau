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
    allowAlterAdd: boolean,
    allowAlterDrop: boolean,
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
    createTable: (self: DatastoreSQLConnection, tableName: string, columns: {string}) -> (boolean, string?),
    dropTable: (self: DatastoreSQLConnection, tableName: string) -> (boolean, string?),
    truncateTable: (self: DatastoreSQLConnection, tableName: string) -> (boolean, string?),
    insert: (self: DatastoreSQLConnection, tableName: string, columns: {string}, values: {any}) -> (boolean, string?),
    select: (self: DatastoreSQLConnection, tableName: string, columns: {string}, conditions: {any}?, orderBy: {string}?, limit: number?, distinct: boolean?) -> (SQLQueryResult?, string?),
    update: (self: DatastoreSQLConnection, tableName: string, setClauses: {any}, conditions: {any}?) -> TypedPromise<(boolean, string?)>,
    delete: (self: DatastoreSQLConnection, tableName: string, conditions: {any}?) -> (boolean, string?),
    split: (self: DatastoreSQLConnection, inputStr: string, sep: string) -> {string},
    trim: (self: DatastoreSQLConnection, s: string) -> string,
    parseConditions: (self: DatastoreSQLConnection, conditionStr: string) -> {any},
    stripQuotes: (self: DatastoreSQLConnection, s: string) -> string,
    parseSetClause: (self: DatastoreSQLConnection, setStr: string) -> {any},
    alterTableAddColumn: (self: DatastoreSQLConnection, tableName: string, columnDetails: table) -> (boolean, string?),
    alterTableDropColumn: (self: DatastoreSQLConnection, tableName: string, columnDetails: {string}) -> (boolean, string?),
}
export type ProfileSQLConnection = {
    profilesTable: {Data: any},
    config: DatastoreSQLConfig,
    query: (self: ProfileSQLConnection, query: SQLQuery) -> TypedPromise<SQLQueryResult>,
    parseSQL: (self: ProfileSQLConnection, query: SQLQuery) -> any,
    createTable: (self: ProfileSQLConnection, tableName: string, columns: {string}) -> (boolean, string?),
    dropTable: (self: ProfileSQLConnection, tableName: string) -> (boolean, string?),
    truncateTable: (self: ProfileSQLConnection, tableName: string) -> (boolean, string?),
    insert: (self: ProfileSQLConnection, tableName: string, columns: {string}, values: {any}) -> (boolean, string?),
    select: (self: ProfileSQLConnection, tableName: string, columns: {string}, conditions: {any}?, orderBy: {string}?, limit: number?, distinct: boolean?) -> (SQLQueryResult?, string?),
    update: (self: ProfileSQLConnection, tableName: string, setClauses: {any}, conditions: {any}?) -> TypedPromise<(boolean, string?)>,
    delete: (self: ProfileSQLConnection, tableName: string, conditions: {any}?) -> (boolean, string?),
    split: (self: ProfileSQLConnection, inputStr: string, sep: string) -> {string},
    trim: (self: ProfileSQLConnection, s: string) -> string,
    parseConditions: (self: ProfileSQLConnection, conditionStr: string) -> {any},
    stripQuotes: (self: ProfileSQLConnection, s: string) -> string,
    parseSetClause: (self: ProfileSQLConnection, setStr: string) -> {any},
    alterTableAddColumn: (self: ProfileSQLConnection, tableName: string, columnDetails: table) -> (boolean, string?),
    alterTableDropColumn: (self: ProfileSQLConnection, tableName: string, columnDetails: {string}) -> (boolean, string?),
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
