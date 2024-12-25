local PlayerDatastore = game:GetService("DataStoreService"):GetDataStore("PlayerDatastore")
local rSQL = require(path.to.rSQL)

local DB_CONNECTION = rSQL.connect(PlayerDatastore, yourConfigHERE)