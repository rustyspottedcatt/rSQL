--!strict
-- Library version. Keep it in sync with wally.toml.

local Version = {
	major = 2,
	minor = 0,
	patch = 1,
	prerelease = nil :: string?,
}

Version.string = string.format("%d.%d.%d", Version.major, Version.minor, Version.patch)
	.. (if Version.prerelease then "-" .. Version.prerelease else "")

return table.freeze(Version)
