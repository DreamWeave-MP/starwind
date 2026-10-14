--!strict
--!native
-- `@starwind/cli`: the argument lists it reads into `build`'s options, the ones it refuses and
-- why, and the exit status of each way a command can end short of a finished build. Its messages
-- go to the suite's own standard error.
local cli = require '@starwind/cli'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

-- Each argument list `parse` refuses, and what it says of it.
local Refused: { { argv: { string }, message: string } } = {
  { argv = {}, message = 'a command is required' },
  { argv = { 'frobnicate' }, message = 'unknown command \'frobnicate\'' },
  { argv = { 'Build', 'sw_merged' }, message = 'unknown command \'Build\'' },
  { argv = { '--strict', 'build', 'sw_merged' }, message = 'unknown command \'--strict\'' },
  { argv = { 'build' }, message = 'build requires the sw_merged folder' },
  { argv = { 'build', '--strict' }, message = 'build requires the sw_merged folder' },
  { argv = { 'build', 'sw_merged', '--bogus' }, message = 'unknown option \'--bogus\'' },
  { argv = { 'build', 'sw_merged', '-o', 'out' }, message = 'unknown option \'-o\'' },
  { argv = { 'build', 'sw_merged', '--keepwork' }, message = 'unknown option \'--keepwork\'' },
  { argv = { 'build', 'sw_merged', '--strict=1' }, message = 'unknown option \'--strict=1\'' },
  { argv = { 'build', '--help' }, message = 'unknown option \'--help\'' },
  { argv = { 'build', 'sw_merged', '--output' }, message = '--output requires a path' },
  {
    argv = { 'build', 'sw_merged', 'elsewhere' },
    message = 'build takes one folder, not \'elsewhere\' as well',
  },
  {
    argv = { 'build', 'sw_merged', '--', '--strict' },
    message = 'build takes one folder, not \'--strict\' as well',
  },
  { argv = { 'help', 'build' }, message = 'help takes no arguments, not \'build\'' },
}

local function scratch(name: string): string
  local root = assert(rawget(_G, 'scratchRoot') :: string?, 'the case needs a scratchRoot')
  return jess.fs.join(root, name)
end

suite.describe('parse', function()
  suite.it('reads build\'s root, and leaves unset the options it wasn\'t given', function()
    local command, message = cli.parse { 'build', 'sw_merged' }
    expect(command).toEqual { action = 'build', options = { root = 'sw_merged' } }
    expect(message).toBeNil()
  end)

  suite.it('maps each option onto build\'s', function()
    local command = cli.parse {
      'build',
      'sw_merged',
      '--output',
      'out dir',
      '--strict',
      '--keep-work',
      '--timings',
    }

    expect(command).toEqual {
      action = 'build',
      options = {
        root = 'sw_merged',
        output = 'out dir',
        strict = true,
        keepWork = true,
        timings = {},
      },
    }
  end)

  suite.it('takes options on either side of the root, the last --output winning', function()
    local command = cli.parse {
      'build',
      '--output',
      'first',
      '--strict',
      'sw_merged',
      '--output',
      'second',
    }

    expect(command).toEqual {
      action = 'build',
      options = { root = 'sw_merged', output = 'second', strict = true },
    }
  end)

  suite.it('takes what follows --output and what follows -- as they are spelled', function()
    expect(cli.parse { 'build', '--', '--strict' }).toEqual {
      action = 'build',
      options = { root = '--strict' },
    }

    expect(cli.parse { 'build', '--keep-work', '--', '-sw_merged' }).toEqual {
      action = 'build',
      options = { root = '-sw_merged', keepWork = true },
    }

    expect(cli.parse { 'build', 'sw_merged', '--output', '--strict' }).toEqual {
      action = 'build',
      options = { root = 'sw_merged', output = '--strict' },
    }
  end)

  suite.it('gives each build its own timings table', function()
    local first = assert(cli.parse { 'build', 'sw_merged', '--timings' })
    local second = assert(cli.parse { 'build', 'sw_merged', '--timings' })
    expect(first.options ~= second.options).toBe(true)
    expect(assert(first.options).timings ~= assert(second.options).timings).toBe(true)
  end)

  suite.it('reads help under each of its spellings', function()
    for _, spelling in { 'help', '--help', '-h' } do
      local command, message = cli.parse { spelling }
      expect(command).toEqual { action = 'help' }
      expect(message).toBeNil()
    end
  end)

  suite.it('refuses what it can\'t read, and says why', function()
    for _, case in Refused do
      local command, message = cli.parse(case.argv)
      expect(command).toBeNil()
      expect(message).toBe(case.message)
    end
  end)

  suite.it('leaves the argument list as it was', function()
    local argv = { 'build', 'sw_merged', '--output', 'out', '--', 'extra' }
    cli.parse(argv)
    expect(argv).toEqual { 'build', 'sw_merged', '--output', 'out', '--', 'extra' }
  end)
end)

suite.describe('run', function()
  suite.it(
    'numbers its exit statuses as vfstool does',
    function() expect(cli.Exit).toEqual { ok = 0, invalidInput = 8, runtime = 9 } end
  )

  suite.it('returns 0 for help', function()
    expect(cli.run { 'help' }).toBe(0)
    expect(cli.run { '--help' }).toBe(0)
    expect(cli.run { '-h' }).toBe(0)
  end)

  suite.it('returns 8 for every command line parse refuses', function()
    for _, case in Refused do
      expect(cli.run(case.argv)).toBe(8)
    end
  end)

  suite.it('returns 8 for a root that isn\'t a folder, and makes nothing there', function()
    local missing = scratch 'starwind-cli-missing-root'
    expect(jess.fs.isDir(missing)).toBe(false)
    expect(cli.run { 'build', missing }).toBe(8)
    expect(cli.run { 'build', missing, '--strict', '--keep-work', '--timings' }).toBe(8)
    expect(jess.fs.isDir(missing)).toBe(false)
  end)

  suite.it('returns 9 when the build raises, having written only under --output', function()
    local root, output = scratch 'starwind-cli-empty-root', scratch 'starwind-cli-output'

    if not jess.fs.isDir(root) then jess.fs.createDir(root) end

    -- The root has no plugins folder, so the build stops at its first source.
    expect(cli.run { 'build', root, '--output', output, '--timings' }).toBe(9)
    expect(jess.fs.isDir(jess.fs.join(root, '.swbuild'))).toBe(false)
    expect(jess.fs.list(root)).toEqual {}
    expect(jess.fs.isDir(output)).toBe(true)
  end)
end)

return suite
