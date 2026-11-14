--!strict
--[[
	Leveled logger with an injectable sink.

	The library never calls `print` directly. Everything goes through a Logger so
	games can route output to their own analytics and tests can capture it.
]]

export type Level = "debug" | "info" | "warn" | "error" | "silent"
export type Sink = (level: Level, message: string) -> ()

export type LoggerOptions = { level: Level?, scope: string?, sink: Sink? }

export type Logger = {
	level: Level,
	scope: string,
	sink: Sink,
	debug: (self: Logger, fmt: string, ...any) -> (),
	info: (self: Logger, fmt: string, ...any) -> (),
	warn: (self: Logger, fmt: string, ...any) -> (),
	error: (self: Logger, fmt: string, ...any) -> (),
	child: (self: Logger, scope: string) -> Logger,
	enabled: (self: Logger, level: Level) -> boolean,
}

local RANK: { [Level]: number } = { debug = 1, info = 2, warn = 3, error = 4, silent = 5 }

local Logger = {}

local function defaultSink(level: Level, message: string)
	if level == "warn" or level == "error" then
		warn(message)
	else
		print(message)
	end
end

function Logger.new(options: LoggerOptions?): Logger
	local opts: LoggerOptions = options or {}
	local self = {
		level = opts.level or "info",
		scope = opts.scope or "rSQL",
		sink = opts.sink or defaultSink,
	} :: Logger

	local function emit(logger: Logger, level: Level, fmt: string, ...: any)
		if RANK[level] < RANK[logger.level] then
			return
		end
		local message = if select("#", ...) > 0 then string.format(fmt, ...) else fmt
		logger.sink(level, string.format("[%s] %s", logger.scope, message))
	end

	function self:enabled(level: Level): boolean
		return RANK[level] >= RANK[self.level]
	end
	function self:debug(fmt: string, ...: any)
		emit(self, "debug", fmt, ...)
	end
	function self:info(fmt: string, ...: any)
		emit(self, "info", fmt, ...)
	end
	function self:warn(fmt: string, ...: any)
		emit(self, "warn", fmt, ...)
	end
	function self:error(fmt: string, ...: any)
		emit(self, "error", fmt, ...)
	end
	function self:child(scope: string): Logger
		return Logger.new({ level = self.level, scope = self.scope .. "/" .. scope, sink = self.sink })
	end

	return self
end

--[=[
	A logger that records messages in memory. Handy for tests.
]=]
function Logger.capture(level: Level?): (Logger, { { level: Level, message: string } })
	local records: { { level: Level, message: string } } = {}
	local logger = Logger.new({
		level = level or "debug",
		sink = function(lvl: Level, message: string)
			table.insert(records, { level = lvl, message = message })
		end,
	})
	return logger, records
end

return Logger
