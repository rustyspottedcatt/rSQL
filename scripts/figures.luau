--[[
	Builds the README / DevForum figures from real data.

	    lune run bench/run                    # refresh docs/figures/data/bench.json
	    lune run scripts/figures              # writes build/figures/*.html
	    swift tools/render-figures.swift      # renders docs/img/*.png (macOS)

	Numbers come from the benchmark run; query output, plans and error
	messages come from running the engine here. Nothing is typed in by hand.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local rSQL = require("../src")
local Json = require("../src/Util/Json")
local FakeDataStore = require("../tests/support/FakeDataStore")

local OUT = "build/figures"
for _, dir in { "build", OUT } do
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
end

local bench = Json.decode(fs.readFile("docs/figures/data/bench.json"))

-- Dark card theme. Series colors are the validated dark steps of the
-- reference categorical palette; text never uses a series color.
local CSS = [[
:root {
  --card: #1a1a19; --raised: #232321; --grid: #2e2e2b; --axis: #4a4a46;
  --ink: #f0efec; --ink-2: #c3c2b7; --muted: #8f8e85;
  --s1: #3987e5; --s2: #d95926; --s3: #199e70; --s4: #c98500;
}
html, body { margin: 0; background: var(--card); }
body { font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; color: var(--ink); -webkit-font-smoothing: antialiased; }
.figure { width: 800px; box-sizing: border-box; padding: 28px 32px 24px; background: var(--card); }
h1 { font-size: 21px; font-weight: 650; margin: 0 0 4px; letter-spacing: -0.01em; }
.sub { font-size: 13.5px; color: var(--ink-2); margin: 0 0 18px; line-height: 1.45; }
.note { font-size: 11.5px; color: var(--muted); margin-top: 14px; line-height: 1.5; }
.mono { font-family: "SF Mono", Menlo, monospace; }
svg text { font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; }
.legend { display: flex; gap: 18px; font-size: 12.5px; color: var(--ink-2); margin: 0 0 8px; }
.legend i { display: inline-block; width: 12px; height: 12px; border-radius: 3px; margin-right: 6px; vertical-align: -1px; }
]]

local function page(name: string, body: string, extraCss: string?)
	fs.writeFile(
		OUT .. "/" .. name .. ".html",
		string.format(
			'<!doctype html><html><head><meta charset="utf-8"><style>%s%s</style></head><body><div class="figure">%s</div></body></html>',
			CSS,
			extraCss or "",
			body
		)
	)
	print("wrote " .. OUT .. "/" .. name .. ".html")
end

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- run the suite and use its count, so the banner can't drift from it
-- (tests defined in loops make counting `it(` in the files wrong)
local testCount = 0
do
	local run = process.exec("lune", { "run", "tests/run" })
	local passed, failed = string.match(run.stdout, "(%d+) passed, (%d+) failed")
	assert(run.ok and passed and failed == "0", "the test suite must pass before drawing figures")
	testCount = tonumber(passed) :: number
end

local last = bench.lookup[#bench.lookup]
local ratio = last.single.bytes / last.sharded.bytes

-- shared: box-drawn result table, same as the shell prints
local function boxTable(columns: { string }, rows: { { [string]: any } }): string
	local function cell(v: any): string
		return if v == nil then "NULL" else tostring(v)
	end
	local widths = {}
	for i, c in columns do
		widths[i] = #c
		for _, row in rows do
			widths[i] = math.max(widths[i], #cell(row[c]))
		end
	end
	local function line(l: string, m: string, r: string): string
		local parts = {}
		for i in columns do
			parts[i] = string.rep("─", widths[i] + 2)
		end
		return l .. table.concat(parts, m) .. r
	end
	local function rowText(values: { string }): string
		local parts = {}
		for i, v in values do
			parts[i] = " " .. v .. string.rep(" ", widths[i] - #v) .. " "
		end
		return "│" .. table.concat(parts, "│") .. "│"
	end
	local out = { line("┌", "┬", "┐"), rowText(columns), line("├", "┼", "┤") }
	for _, row in rows do
		local values = {}
		for i, c in columns do
			values[i] = cell(row[c])
		end
		table.insert(out, rowText(values))
	end
	table.insert(out, line("└", "┴", "┘"))
	return table.concat(out, "\n")
end

-- 1. Banner --------------------------------------------------------------------------

page(
	"01-banner",
	string.format(
		[[<div class="title">rSQL <span class="v">2.0</span></div>
<div class="tag">SQL for Roblox DataStores, player profiles and in-memory tables. Rewritten from scratch: a real parser, typed columns, sharded storage and no dependencies.</div>
<pre class="q"><span class="k">SELECT</span> Name, Coins <span class="k">FROM</span> Players <span class="k">WHERE</span> Team = ? <span class="k">ORDER BY</span> Coins <span class="k">DESC LIMIT</span> 5</pre>
<div class="stats">
  <div><b>%.0f×</b><span>less data read per key lookup at 5,000 rows</span></div>
  <div><b>%d</b><span>tests, run under Lune, from the built place and in Studio</span></div>
  <div><b>1.x</b><span>scripts and saved data keep working</span></div>
</div>]],
		ratio,
		testCount
	),
	[[
.figure { padding: 34px 36px 30px; background: radial-gradient(120% 140% at 100% 0%, #1f2b3d 0%, var(--card) 55%); }
.title { font-size: 44px; font-weight: 750; letter-spacing: -0.02em; }
.title .v { color: var(--s1); }
.tag { font-size: 16px; color: var(--ink-2); margin-top: 6px; max-width: 640px; line-height: 1.45; }
.q { font-family: "SF Mono", Menlo, monospace; font-size: 13px; background: #121211; border-radius: 8px; padding: 12px 14px; margin: 20px 0 22px; color: var(--ink); white-space: pre-wrap; }
.q .k { color: #86b6ef; }
.stats { display: flex; gap: 34px; }
.stats div { display: flex; flex-direction: column; } .stats b { font-size: 24px; font-weight: 700; }
.stats span { font-size: 12px; color: var(--muted); margin-top: 2px; max-width: 190px; }
]]
)

-- 2. Architecture --------------------------------------------------------------------

page(
	"02-architecture",
	[[<h1>How 2.0 is put together</h1>
<p class="sub">A query goes down the stack once: parsed, planned, run, stored. Each layer only uses the layers under it, so the engine never knows whether rows live in a DataStore, a profile or memory.</p>
<div class="stack">
  <div class="layer top"><b>rSQL · Database</b><span>rSQL.datastore / profile / memory · exec · prepare · permissions · stats · 1.x API</span></div>
  <div class="layer"><b>SQL</b><span>lexer with positions · recursive-descent parser · syntax tree · errors with a caret and "did you mean"</span></div>
  <div class="layer"><b>Engine</b><span>planner (key lookup or scan) · executor (JOIN, GROUP BY, ORDER BY, LIMIT) · compiled expressions · typed schemas</span></div>
  <div class="tri">
    <div class="layer st"><b>DataStore</b><span>tables sharded by key hash · UpdateAsync per shard · retries · 1.x layout</span></div>
    <div class="layer st"><b>Profile</b><span>ProfileService · ProfileStore · DataKeep, inside profile.Data</span></div>
    <div class="layer st"><b>Memory</b><span>indexed tables for items, loot, shops, tests</span></div>
  </div>
  <div class="layer base"><b>Platform · Util</b><span>clock · yielding · hashing · JSON · logging</span></div>
</div>]],
	[[
.stack { display: flex; flex-direction: column; gap: 8px; }
.tri { display: flex; gap: 8px; } .tri > * { flex: 1; }
.layer { background: var(--raised); border-radius: 8px; padding: 11px 14px; display: flex; flex-direction: column; gap: 3px; border-left: 3px solid var(--axis); }
.layer b { font-size: 14px; font-weight: 650; } .layer span { font-size: 12px; color: var(--ink-2); line-height: 1.4; }
.layer.top { border-left-color: var(--s1); } .layer.st { border-left-color: var(--s3); } .layer.base { border-left-color: var(--muted); }
]]
)

-- 3. Shell session -------------------------------------------------------------------

do
	local db = rSQL.datastore(FakeDataStore.new(), { shards = 8, sleep = function() end })
	local transcript = {}
	local function run(sql: string)
		table.insert(transcript, '<span class="p">rsql&gt;</span> ' .. esc(sql))
		local ok, result = pcall(db.exec, db, sql)
		if not ok then
			table.insert(transcript, '<span class="e">' .. esc(tostring(result)) .. "</span>")
		elseif #result.columns > 0 then
			table.insert(transcript, esc(boxTable(result.columns, result.rows)))
			table.insert(
				transcript,
				string.format(
					'<span class="m">%d row%s · %s · %d DataStore read%s</span>',
					#result.rows,
					if #result.rows == 1 then "" else "s",
					esc((result.plan and result.plan[1]) or result.kind),
					result.stats.reads,
					if result.stats.reads == 1 then "" else "s"
				)
			)
		else
			table.insert(transcript, '<span class="m">' .. esc(result.message or "ok") .. "</span>")
		end
		table.insert(transcript, "")
	end
	db:exec("CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Name TEXT NOT NULL, Team TEXT, Coins INTEGER DEFAULT 0)")
	db:exec(
		"INSERT INTO Players (UserId, Name, Team, Coins) VALUES (101, 'alice', 'red', 120), (102, 'bob', 'blue', 40), (103, 'carol', 'red', 75), (104, 'dave', 'green', 40)"
	)
	run("UPDATE Players SET Coins = Coins + 25 WHERE UserId = 102")
	run("SELECT Name, Coins FROM Players WHERE UserId = 102")
	run("SELECT Team, COUNT(*) AS n, SUM(Coins) AS coins FROM Players GROUP BY Team ORDER BY coins DESC")
	page(
		"03-queries",
		string.format(
			[[<h1>Real SQL against a DataStore</h1>
<p class="sub">Output from <span class="mono">lune run scripts/rsql</span> on a table spread over 8 DataStore keys. The key lookup touches one shard; the GROUP BY reads all of them.</p>
<pre class="term">%s</pre>]],
			table.concat(transcript, "\n")
		),
		[[
.term { font-family: Menlo, monospace; font-size: 11.5px; line-height: 1.25; background: #121211; border-radius: 10px; padding: 16px 18px; margin: 0; color: var(--ink); white-space: pre; }
.term .p { color: #86b6ef; } .term .m { color: var(--muted); } .term .e { color: #e66767; }
]]
	)
end

-- 4. Bytes per lookup ----------------------------------------------------------------

do
	local W, H = 736, 300
	local left, right, top, bottom = 52, 118, 12, 44
	local xMax = 5000
	local yMax = math.ceil(last.single.bytes / 1024 / 100) * 100
	local function x(v: number): number
		return left + (W - left - right) * v / xMax
	end
	local function y(kb: number): number
		return top + (H - top - bottom) * (1 - kb / yMax)
	end
	local parts = { string.format('<svg width="%d" height="%d">', W, H + 10) }
	for v = 0, yMax, 100 do
		table.insert(
			parts,
			string.format(
				'<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="var(--grid)"/><text x="%d" y="%.1f" fill="var(--muted)" font-size="11.5" text-anchor="end">%d KB</text>',
				left,
				W - right,
				y(v),
				y(v),
				left - 8,
				y(v) + 4,
				v
			)
		)
	end
	for _, v in { 0, 1000, 2000, 3000, 4000, 5000 } do
		table.insert(
			parts,
			string.format(
				'<text x="%.1f" y="%d" fill="var(--muted)" font-size="11.5" text-anchor="middle">%s</text>',
				x(v),
				H - 22,
				commas(v)
			)
		)
	end
	table.insert(
		parts,
		string.format(
			'<text x="%d" y="%d" fill="var(--muted)" font-size="11.5" text-anchor="middle">rows in the table</text>',
			(left + W - right) // 2,
			H + 4
		)
	)
	for _, series in
		{
			{ key = "single", color = "var(--s2)", label = "1.x layout" },
			{ key = "sharded", color = "var(--s1)", label = "2.0 sharded" },
		}
	do
		local path = { string.format("M%.1f,%.1f", x(0), y(0)) }
		for _, p in bench.lookup do
			table.insert(path, string.format("L%.1f,%.1f", x(p.rows), y(p[series.key].bytes / 1024)))
		end
		table.insert(
			parts,
			string.format(
				'<path d="%s" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round"/>',
				table.concat(path, " "),
				series.color
			)
		)
		for _, p in bench.lookup do
			table.insert(
				parts,
				string.format(
					'<circle cx="%.1f" cy="%.1f" r="4" fill="%s" stroke="var(--card)" stroke-width="2"/>',
					x(p.rows),
					y(p[series.key].bytes / 1024),
					series.color
				)
			)
		end
		table.insert(
			parts,
			string.format(
				'<text x="%.1f" y="%.1f" fill="var(--ink)" font-size="12.5" font-weight="600">%.0f KB</text><text x="%.1f" y="%.1f" fill="var(--ink-2)" font-size="11.5">%s</text>',
				x(5000) + 10,
				y(last[series.key].bytes / 1024) + 1,
				last[series.key].bytes / 1024,
				x(5000) + 10,
				y(last[series.key].bytes / 1024) + 15,
				series.label
			)
		)
	end
	table.insert(parts, "</svg>")
	page(
		"04-bytes-per-lookup",
		string.format(
			[[<h1>Data read to fetch one player</h1>
<p class="sub"><span class="mono">SELECT ... WHERE UserId = ?</span> on a Players table as it grows. 1.x kept the whole table in one DataStore key and read all of it every time. 2.0 spreads rows over 8 keys by a hash of the primary key and reads only the right one.</p>
<div class="legend"><span><i style="background:var(--s2)"></i>1.x layout (one key)</span><span><i style="background:var(--s1)"></i>2.0 sharded (8 keys)</span></div>
%s
<p class="note">Measured with <span class="mono">lune run bench/run</span> against a DataStore stand-in that counts the JSON size of every value it returns. One key also caps a 1.x table at 4 MB (about %s rows like these); 8 shards hold 8 times that, and <span class="mono">db:reshard()</span> can add more.</p>]],
			table.concat(parts),
			commas(4 * 1024 * 1024 / (last.tableBytes / last.rows))
		)
	)
end

-- 5. Requests per statement ----------------------------------------------------------

do
	local rows = {}
	local maxValue = 9
	for _, op in bench.operations do
		local function bar(value: number, color: string): string
			return string.format(
				'<div class="bar"><span style="width:%.1fpx;background:%s"></span><em>%d</em></div>',
				math.max(3, 230 * value / maxValue),
				color,
				value
			)
		end
		table.insert(
			rows,
			string.format(
				'<div class="op"><div class="label">%s</div><div class="bars">%s%s</div></div>',
				esc(op.label),
				bar(op.reads, "var(--s1)"),
				bar(op.writes, "var(--s4)")
			)
		)
	end
	page(
		"05-requests",
		string.format(
			[[<h1>DataStore requests per statement</h1>
<p class="sub">1,000-row table over 8 shards. Statements that name the primary key touch one shard. Filters on other columns visit every shard; writes go through UpdateAsync, so each shard updates atomically.</p>
<div class="legend"><span><i style="background:var(--s1)"></i>reads (GetAsync)</span><span><i style="background:var(--s4)"></i>writes (UpdateAsync / RemoveAsync)</span></div>
<div class="ops">%s</div>
<p class="note">Reads include one for the table's meta key. Counted by the DataStore stand-in in <span class="mono">bench/run.luau</span>.</p>]],
			table.concat(rows)
		),
		[[
.ops { display: flex; flex-direction: column; gap: 10px; margin-top: 6px; }
.op { display: flex; align-items: center; }
.label { width: 180px; font-size: 13px; color: var(--ink-2); }
.bars { display: flex; flex-direction: column; gap: 3px; }
.bar { display: flex; align-items: center; gap: 8px; }
.bar span { display: inline-block; height: 12px; border-radius: 0 4px 4px 0; }
.bar em { font-style: normal; font-size: 12px; color: var(--ink); font-weight: 600; }
]]
	)
end

-- 6. Shard balance -------------------------------------------------------------------

do
	local counts = bench.shardRows
	local total, maxCount = 0, 0
	for _, c in counts do
		total += c
		maxCount = math.max(maxCount, c)
	end
	local W, H = 736, 210
	local barW, gap = 62, 22
	local base = H - 40
	local parts = { string.format('<svg width="%d" height="%d">', W, H) }
	for i, c in counts do
		local h = (base - 20) * c / (maxCount * 1.15)
		local x0 = 40 + (i - 1) * (barW + gap)
		table.insert(
			parts,
			string.format(
				'<rect x="%d" y="%.1f" width="%d" height="%.1f" rx="4" fill="var(--s1)"/><text x="%.1f" y="%.1f" fill="var(--ink)" font-size="12.5" font-weight="600" text-anchor="middle">%d</text><text x="%.1f" y="%d" fill="var(--muted)" font-size="11.5" text-anchor="middle">shard %d</text>',
				x0,
				base - h,
				barW,
				h,
				x0 + barW / 2,
				base - h - 6,
				c,
				x0 + barW / 2,
				base + 18,
				i
			)
		)
	end
	table.insert(
		parts,
		string.format('<line x1="30" x2="%d" y1="%d" y2="%d" stroke="var(--axis)"/>', W - 10, base, base)
	)
	table.insert(parts, "</svg>")
	page(
		"06-shards",
		string.format(
			[[<h1>Where the rows end up</h1>
<p class="sub">%s rows of a Players table, each placed by <span class="mono">hash(UserId) %% 8</span>. Every shard is its own DataStore key with its own 4 MB budget, and they fill evenly.</p>
<div class="keys mono">Players/meta &nbsp;·&nbsp; Players/1.1 &nbsp;·&nbsp; Players/1.2 &nbsp;·&nbsp; … &nbsp;·&nbsp; Players/1.8</div>
%s
<p class="note">Rows are stored as a map from key to row inside each shard, so finding one row in its shard is a single table lookup.</p>]],
			commas(total),
			table.concat(parts)
		),
		[[.keys { font-size: 12px; color: var(--ink-2); background: #121211; border-radius: 6px; padding: 8px 12px; margin-bottom: 10px; display: inline-block; }]]
	)
end

-- 7. Error messages ------------------------------------------------------------------

do
	local db = rSQL.memory()
	db:exec("CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Name TEXT NOT NULL, Coins INTEGER DEFAULT 0)")
	local cards = {}
	for _, item in
		{
			{ "typo in a keyword", "SELECT Name FROM Players WHER Coins > 10" },
			{ "typo in a column", "SELECT Nmae, Coins FROM Players" },
			{ "wrong type for a column", "INSERT INTO Players (UserId, Name, Coins) VALUES (7, 'ann', 'lots')" },
			{ "missing parameter", "UPDATE Players SET Coins = Coins + ? WHERE UserId = ?" },
		}
	do
		local ok, err = pcall(db.exec, db, item[2], { 10 })
		assert(not ok, "expected an error for " .. item[2])
		table.insert(
			cards,
			string.format(
				'<div class="card"><div class="what">%s</div><pre>%s</pre></div>',
				item[1],
				esc(tostring(err))
			)
		)
	end
	page(
		"07-errors",
		string.format(
			[[<h1>Errors that say what went wrong</h1>
<p class="sub">1.x errors said which step failed. 2.0 points at the exact spot in the query, suggests the name you probably meant, and checks types before anything is written.</p>
<div class="cards">%s</div>]],
			table.concat(cards)
		),
		[[
.cards { display: flex; flex-direction: column; gap: 10px; }
.card { background: #121211; border-radius: 8px; padding: 10px 14px; }
.what { font-size: 11.5px; color: var(--muted); margin-bottom: 4px; }
.card pre { margin: 0; font-family: "SF Mono", Menlo, monospace; font-size: 12.5px; line-height: 1.45; color: #f0b0a8; white-space: pre; }
]]
	)
end

-- 8. What changed --------------------------------------------------------------------

page(
	"08-what-changed",
	[[<h1>1.x vs 2.0</h1>
<p class="sub">The problems people ran into, and what happens now. Every row on the right has a test.</p>
<table>
<tr><th></th><th>1.x</th><th>2.0</th></tr>
<tr><td>CREATE TABLE on every server start</td><td class="bad">replaced the table with an empty one, wiping saved rows</td><td class="good">keeps the data (and IF NOT EXISTS works)</td></tr>
<tr><td>Numbers</td><td class="bad">came back as strings</td><td class="good">typed columns: INTEGER, REAL, TEXT, BOOLEAN, JSON, BLOB</td></tr>
<tr><td>Table size</td><td class="bad">one DataStore key, 4 MB for the whole table</td><td class="good">sharded over keys, 4 MB per shard, reshardable</td></tr>
<tr><td>Reading one row</td><td class="bad">downloads the whole table</td><td class="good">reads one shard</td></tr>
<tr><td>Player input in queries</td><td class="bad">string.format into the SQL</td><td class="good">parameters (? and :name), never parsed as SQL</td></tr>
<tr><td>Queries</td><td class="bad">SELECT with WHERE and LIKE</td><td class="good">JOIN, GROUP BY, HAVING, ORDER BY, LIMIT, IN, BETWEEN, LIKE, math, EXPLAIN</td></tr>
<tr><td>Dependencies</td><td class="bad">promise and signal packages</td><td class="good">none (a compatible promise is built in)</td></tr>
</table>]],
	[[
table { width: 100%; border-collapse: separate; border-spacing: 0 6px; font-size: 13px; }
th { text-align: left; font-size: 12px; color: var(--muted); font-weight: 600; padding: 0 10px; }
td { background: var(--raised); padding: 9px 10px; vertical-align: top; line-height: 1.4; }
td:first-child { color: var(--ink); font-weight: 600; border-radius: 6px 0 0 6px; width: 190px; }
td:last-child { border-radius: 0 6px 6px 0; }
td.bad { color: var(--ink-2); } td.good { color: var(--ink); }
td.good::before { content: "✓ "; color: #3fbf8a; } td.bad::before { content: "✕ "; color: #e66767; }
]]
)

print(string.format("\n%d tests counted, %.1fx less data per lookup at %d rows", testCount, ratio, last.rows))
