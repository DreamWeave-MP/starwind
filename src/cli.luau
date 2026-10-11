--!strict
--!native
--[[
@starwind/cli: the Starwind Definitive build's command line.

  run(argv) -> exit status
  parse(argv) -> (command, nil) | (nil, message)

  starwind build <root> [--output <dir>] [--strict] [--keep-work] [--timings]
  starwind help

`build` runs @starwind's `build` on the sw_merged folder `root`; its options are that function's,
under their command-line spellings. `--timings` prints each stage's seconds once the build is
done, slowest first. `parse` reads an argument list into the command it names without running
it, or says what it couldn't read.

Exit statuses: 0 when the command did what it was asked, 8 when the command line can't be used
(no command, an unknown command or option, a missing or extra argument, a root that isn't a
folder), 9 when the build raised. Messages go to standard error as `starwind: <message>`.
]]

local process = require '@dream/process'
local starwind = require '@starwind'

export type Command = { action: 'build' | 'help', options: starwind.Options? }

local Exit = table.freeze { ok = 0, invalidInput = 8, runtime = 9 }

local Usage = [[
starwind: the Starwind Merged Plugin Project's Definitive build

  starwind build <root> [--output <dir>] [--strict] [--keep-work] [--timings]
  starwind help

build reads the JSON sources in <root>/plugins, <root> being the sw_merged folder, and writes
out/Starwind-Definitive.omwaddon, out/Star_Data.omwaddon, out/Starwind.omwaddon, the reports,
and build-manifest.json.

  --output <dir>  where to write them (default <root>/.swbuild/definitive)
  --strict        fail on dialogue order and link drift too
  --keep-work     also keep work/Starwind-Definitive-pre-addVanilla.omwaddon and
                  work/decoupleLog.txt
  --timings       print each stage's seconds afterwards, slowest first

Exit status: 0 done, 8 the command line can't be used, 9 the build failed.]]

local function out(text: string) process.write('stdout', `{text}\n`) end

local function err(text: string) process.write('stderr', `{text}\n`) end

local function usage(message: string): number
  err(`starwind: {message}`)
  return Exit.invalidInput
end

local function parseBuild(argv: { string }): (Command?, string?)
  local options: starwind.Options = { root = '' }
  local positional: { string } = {}
  local index = 2

  while index <= #argv do
    local argument = argv[index]

    if argument == '--' then
      table.move(argv, index + 1, #argv, #positional + 1, positional)
      break
    elseif argument == '--output' then
      local found = argv[index + 1]

      if not found then return nil, '--output requires a path' end

      options.output, index = found, index + 1
    elseif argument == '--strict' then
      options.strict = true
    elseif argument == '--keep-work' then
      options.keepWork = true
    elseif argument == '--timings' then
      options.timings = {}
    elseif string.sub(argument, 1, 1) == '-' then
      return nil, `unknown option '{argument}'`
    else
      table.insert(positional, argument)
    end

    index += 1
  end

  if #positional == 0 then return nil, 'build requires the sw_merged folder' end

  if #positional > 1 then return nil, `build takes one folder, not '{positional[2]}' as well` end

  options.root = positional[1]
  return { action = 'build' :: 'build', options = options }, nil
end

local function parse(argv: { string }): (Command?, string?)
  local action = argv[1]

  if not action then return nil, 'a command is required' end

  if action == 'help' or action == '--help' or action == '-h' then
    if #argv > 1 then return nil, `help takes no arguments, not '{argv[2]}'` end

    return { action = 'help' :: 'help' }, nil
  end

  if action == 'build' then return parseBuild(argv) end

  return nil, `unknown command '{action}'`
end

local function printTimings(timings: { [string]: number })
  local stages = {}

  for name in timings do
    table.insert(stages, name)
  end

  table.sort(stages, function(left, right)
    if timings[left] ~= timings[right] then return timings[left] > timings[right] end

    return left < right
  end)

  for _, name in stages do
    out(string.format('%9.3fs  %s', timings[name], name))
  end
end

local function run(argv: { string }): number
  local command, message = parse(argv)

  if not command then return usage(message :: string) end

  if command.action == 'help' then
    out(Usage)
    return Exit.ok
  end

  local options = command.options :: starwind.Options

  -- `build` makes its output folders before it reads anything, by default under the root.
  if not jess.fs.isDir(options.root) then return usage(`'{options.root}' isn't a folder`) end

  -- The build raises where build_starwind.py exits non-zero, with its message.
  local built, result = pcall(starwind.build, options)

  if not built then
    err(`starwind: {result}`)
    return Exit.runtime
  end

  out(`starwind: built {result.output}`)

  if options.timings then printTimings(options.timings) end

  return Exit.ok
end

return table.freeze { Exit = Exit, parse = parse, run = run }
