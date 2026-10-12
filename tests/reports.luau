--!strict
-- The reports a build that passes never writes, on records small enough to read: the report
-- writer's own corners, a closure audit with something unresolved, a late actor that only link
-- dirt brought in and the cleanup script written for it, and the text tes3cmd's matches read.
local fs = require '@dream/fs'
local starwind = require '@starwind'
local test = require '@jess/test'

local suite, expect = test.new(), test.expect

type Record = { [string | number]: any }

--- An empty folder `name` under the scratch root. The suite runs once from the source and once
--- from the packed package, so what the run before left there is removed first.
local function folder(name: string): string
  local scratch =
    assert(rawget(_G, 'scratchRoot') :: string?, 'the suite needs a host-owned scratchRoot')
  local path = jess.fs.join(scratch, name)

  if jess.fs.exists(path) then assert(fs.remove(path, { recursive = true })) end

  jess.fs.createDir(path)
  return path
end

local function read(path: string): string
  return assert(jess.fs.read(path), `'{path}' isn't there`)
end

--- The package's tests folder, from this file's chunk name: `jess package test` runs the suite
--- from whatever folder it was called in.
local function tests(): string
  local source = debug.info(1, 's')
  local first = string.sub(source, 1, 1)
  local path = if first == '@' or first == '=' then string.sub(source, 2) else source

  return string.match(path, '^(.*)/[^/]*$') or '.'
end

--- What a report held before the code was last changed, kept in `golden`.
local function golden(name: string): string return read(jess.fs.join(tests(), 'golden', name)) end

local function info(id: string, previous: string, following: string, speaker: string): Record
  return {
    type = 'DialogueInfo',
    flags = '',
    id = id,
    prevId = previous,
    nextId = following,
    speakerId = speaker,
    speakerRace = '',
    speakerClass = '',
    speakerFaction = '',
    speakerCell = '',
    playerFaction = '',
    text = `says {id}`,
    filters = {},
    data = { dialogueType = 'Topic', speakerRank = -1, speakerSex = 'Any' },
  }
end

local function npc(id: string): Record
  return {
    type = 'Npc',
    flags = '',
    id = id,
    race = 'Human',
    class = 'Pilot',
    faction = '',
    npcFlags = 'FEMALE',
    script = '',
  }
end

suite.describe('report', function()
  local report = starwind.report

  suite.it('writes what json.dumps(indent=2) writes, keys in the order they were set', function()
    local made = report.object {
      'text',
      'tab\there "quoted" back\\slash\nline\rreturn',
      'accent',
      'caf\u{e9}',
      'astral',
      '\u{1d11e}',
      'control',
      '\1',
      'whole',
      3,
      'negative',
      -0.5,
      'large',
      2 ^ 53,
      'small',
      1e-7,
      'not a number',
      0 / 0,
      'up',
      math.huge,
      'down',
      -math.huge,
      'none',
      nil,
      'null',
      jess.null,
      'yes',
      true,
      'empty array',
      report.array(),
      'empty dict',
      report.dict(),
      'empty object',
      report.object {},
      'unmarked',
      {},
      'list',
      { 1, 'two', false },
      'dict',
      report.dict { beta = 2, alpha = 1 },
      'map',
      { zeta = 1, eta = 2 },
    }
    report.set(made, 'last', 'appended')
    report.set(made, 'none', 'kept its place')
    report.set(made, 'whole', 4)

    expect(report.encode(made)).toBe(golden 'encoded.json')
  end)

  suite.it('spells a record\'s fields as tes3conv does, an empty table a list', function()
    local snaked = report.snake {
      speakerId = 'x',
      aiPackages = { { gameHour = 1 }, {} },
      data = { speakerRank = -1, nested = { deeperStill = true } },
      filters = {},
    }

    expect(report.encode(snaked)).toBe(golden 'snaked.json')
  end)
end)

suite.describe('closure audit', function()
  suite.it('counts what nothing resolves, by kind, and says where each came from', function()
    local records: { Record } = {
      { type = 'Header', flags = '', fileType = 'Esp', masters = { { 'Morrowind.esm', 7 } } },
      { type = 'Static', flags = '', id = 'Rock' },
      { type = 'Container', flags = '', id = 'Crate', script = 'Gone', inventory = { { 1, 'Ghost' } } },
      {
        type = 'Npc',
        flags = '',
        id = 'Pilot',
        race = 'Human',
        class = 'Nobody',
        inventory = { { 1, 'GHOST' }, { 2, 'Rock' }, { 1, 'Phantom' } },
        spells = { 'ghost' },
        aiPackages = { { type = 'Activate', target = 'Lever' }, { type = 'Wander' } },
      },
      { type = 'Race', flags = '', id = 'Human', spells = {} },
      { type = 'Cell', flags = '', name = 'Bay', region = 'Nowhere', data = { flags = 'IS_INTERIOR' } },
    }
    local path = jess.fs.join(folder 'starwind-closure', 'closure.json')
    local asked = 0

    local closure = starwind.audit.closure(records, path, function()
      asked += 1
      return { { { type = 'Header' }, { type = 'Container', id = 'CRATE' } } }
    end)

    expect(asked).toBe(1)
    expect(closure.hard).toBe(8)
    expect(read(path)).toBe(golden 'closure.json')
  end)

  suite.it('asks for no source when everything resolves', function()
    local records: { Record } = {
      { type = 'Header', flags = '', fileType = 'Esp', masters = {} },
      { type = 'Static', flags = '', id = 'Rock' },
      { type = 'Container', flags = '', id = 'Crate', inventory = { { 1, 'ROCK' } } },
    }
    local path = jess.fs.join(folder 'starwind-closure-clean', 'closure.json')
    local closure = starwind.audit.closure(records, path, function() error 'asked' end)

    expect(closure.hard).toBe(0)
    expect(starwind.report.encode(closure.counts)).toBe(
      '{\n  "records_including_header": 3,\n  "masters": 0,\n  "hard_unresolved_occurrences": 0,\n'
        .. '  "hard_unresolved_unique_ids": 0,\n  "hard_unresolved_source_records": 0,\n'
        .. '  "hard_unresolved_sources_likely_imported": 0\n}'
    )
  end)
end)

suite.describe('late actors', function()
  suite.it('classes an actor only link dirt brought in, and writes its cleanup', function()
    local out = folder 'starwind-late-actors'
    local paths = {
      report = jess.fs.join(out, 'late.json'),
      markdown = jess.fs.join(out, 'late.md'),
      cleanup = jess.fs.join(out, 'cleanup.sh'),
    }
    local parent = info('100', '', '200', 'Old_Pilot')
    local dirt = info('100', '', '400', 'Old_Pilot')
    local fresh = info('400', '100', '', 'Late_Smuggler')
    local topic: Record = { type = 'Dialogue', flags = '', id = 'Ships', dialogueType = 'Topic' }
    local own = npc 'SW_Mechanic'
    local old, late = npc 'Old_Pilot', npc 'Late_Smuggler'
    late.npcFlags = ''

    local log = {
      'Dialogue liveness population begin',
      'Dialogue liveness actor\tNpc\tSW_Mechanic\tHuman\tPilot\tfemale',
      'Dialogue liveness actor\tNpc\ttoo\tfew',
      'Dialogue liveness population end',
      'Copying \'Old_Pilot\' (NPC_) to \'Starwind.esp\' from \'Morrowind.esm\'',
      'Copying \'Rock\' (STAT) to \'Starwind.esp\' from \'Morrowind.esm\'',
      'Dependency import:',
      '  pass=post-dialogue',
      '  target=NPC_ \'Old_Pilot\'',
      '  source=INFO \'100\'',
      '  field=speaker_id',
      'Dependency import:',
      '  pass=post-dialogue',
      '  target=NPC_ \'Late_Smuggler\'',
      '  source=CELL \'Bay\'',
      '  field=reference',
    }

    local vanilla = {
      {
        path = 'Morrowind.json',
        binary = 'Morrowind.esm',
        label = 'Morrowind',
        records = { { type = 'Header' }, old, late, topic, parent },
      },
    }

    local patch = {
      {
        path = 'StarwindRemasteredPatch.json',
        binary = 'StarwindRemasteredPatch.esm',
        label = 'RemasteredPatch',
        records = { { type = 'Header' }, topic, dirt, fresh },
      },
    }

    local bay: Record = {
      type = 'Cell',
      flags = '',
      name = 'Bay',
      references = { { id = 'Late_Smuggler', refrIndex = 1 } },
    }
    local mention: Record =
      { type = 'Script', flags = '', id = 'Hail', text = 'if ( GetDistance, "Late_Smuggler" < 9 )' }

    local result = starwind.provenance.report({
      log = log,
      logPath = 'decoupleLog.txt',
      final = { { type = 'Header' }, own, old, late, bay, mention, topic, dirt, fresh },
      finalPath = 'Starwind.omwaddon',
      projection = {
        ships = {
          order = { '100', '400' },
          infos = {
            ['100'] = { record = dirt, source = 'StarwindRemasteredPatch.json', sourceIndex = 2 },
            ['400'] = { record = fresh, source = 'StarwindRemasteredPatch.json', sourceIndex = 3 },
          },
        },
      },
      audit = starwind.report.object { 'live_topics', 1 },
      vanillaSources = function() return vanilla end,
      starwindSources = function() return patch end,
    }, paths)

    expect(result.late_actor_count).toBe(2)
    expect(read(paths.markdown)).toBe(golden 'late-actors.md')
    expect(read(paths.cleanup)).toBe(golden 'late-actors-cleanup.sh')
    expect(read(paths.report)).toBe(golden 'late-actors.json')
  end)

  suite.it('writes no cleanup when nothing came in late', function()
    local out = folder 'starwind-late-none'
    local paths = {
      report = jess.fs.join(out, 'late.json'),
      markdown = jess.fs.join(out, 'late.md'),
      cleanup = jess.fs.join(out, 'cleanup.sh'),
    }

    local result = starwind.provenance.report({
      log = {
        'Dialogue liveness population begin',
        'Dialogue liveness actor\tNpc\tSW_Mechanic\tHuman\tPilot\tfemale',
        'Dialogue liveness population end',
      },
      logPath = 'decoupleLog.txt',
      final = { { type = 'Header' }, npc 'SW_Mechanic' },
      finalPath = 'Starwind.omwaddon',
      projection = {},
      audit = starwind.report.object {},
      vanillaSources = function() error 'asked for the vanilla sources' end,
      starwindSources = function() error 'asked for the Starwind sources' end,
    }, paths)

    expect(result.late_actor_count).toBe(0)
    expect(jess.fs.exists(paths.cleanup)).toBe(false)
    expect(read(paths.markdown)).toBe(golden 'no-late-actors.md')
  end)
end)

suite.describe('dialogue audit', function()
  suite.it('names the fields a written INFO differs from the expected one in', function()
    local topic: Record = { type = 'Dialogue', flags = '', id = 'Ships', dialogueType = 'Topic' }
    local written = table.clone(topic)
    written.flags, written.dialogueType = 'BLOCKED', 'Voice'

    local function filter(comparison: string, value: number): Record
      return {
        index = 0,
        filterType = 'Global',
        id = 'Rent',
        comparison = comparison,
        value = { type = 'Integer', data = value },
      }
    end

    -- A number a plugin holds as an f32 is the same number.
    local rounded = info('100', '', '200', '')
    rounded.data.disposition = 0.1
    local held = info('100', 'elsewhere', 'again', '')
    held.data.disposition = string.unpack('<f', string.pack('<f', 0.1))

    local plain = info('200', '100', '300', '')
    plain.questState = 'Name'
    local changed = info('200', '100', '300', '')
    changed.text, changed.soundPath = 'says otherwise', 'vo\\ships.mp3'
    changed.data.speakerRank, changed.data.disposition = 3, 0.5
    changed.filters = { filter('Equal', 1) }

    local asked = info('300', '200', '', '')
    asked.filters = { filter('Equal', 1), filter('Less', 4) }
    local answered = info('300', '200', '', '')
    answered.filters = { filter('NotEqual', 2), filter('Less', 4.5) }

    local header: Record = { type = 'Header', flags = '', masters = {} }
    local path = jess.fs.join(folder 'starwind-audit-content', 'audit.json')

    local report = starwind.dialogue.audit {
      final = { name = 'final', records = { header, written, held, changed, answered } },
      starwind = { name = 'Starwind', records = { header, topic, rounded, plain, asked } },
      bases = { { name = 'Morrowind.esm', records = { header } } },
      log = {},
      logPath = 'decoupleLog.txt',
      provenance = function() return {} end,
      provenanceNames = {},
      reportPath = path,
    }

    expect(report.dialogue_content_mismatches).toEqual { { dialogue_id = 'ships' } }
    expect(report.info_content_mismatches).toEqual {
      {
        dialogue_id = 'ships',
        info_id = '200',
        differing_fields = {
          'data.disposition',
          'data.speaker_rank',
          'filters.length',
          'quest_state',
          'sound_path',
          'text',
        },
      },
      {
        dialogue_id = 'ships',
        info_id = '300',
        differing_fields = { 'filters[0].comparison', 'filters[0].value.data', 'filters[1].value.data' },
      },
    }
    expect(report.actor_population_source).toBe 'final (fallback; no Rust snapshot found)'
    expect(read(path)).toBe(golden 'content-audit.json')
  end)
end)

suite.describe('tes3cmd\'s text', function()
  local surgery = starwind.surgery

  suite.it('prints a reference as tes3cmd does, subrecord by subrecord', function()
    local text = surgery.instanceText {
      mastIndex = 2,
      refrIndex = 7,
      id = 'SW_Door',
      scale = 1.5,
      owner = 'Adele',
      ownerGlobal = 'Rent',
      ownerFaction = 'Hutts',
      soul = 'Rancor',
      chargeLeft = 12,
      healthLeft = 40,
      objectCount = 3,
      destination = { translation = { 1, 2.5, -3 }, rotation = { 0, 0.25, 1 }, cell = 'Bay' },
      lockLevel = 50,
      key = 'SW_Key',
      trap = 'SW_Trap',
      deleted = true,
      translation = { 9336, 12.125, -40 },
      rotation = { 0, 1.5, 3.14159 },
    }

    expect(text).toBe(
      'ObjIdx:7  MastIdx:2Name:SW_DoorScale:1.50Owner_Actor:AdeleGlobal:RentOwner_Faction:Hutts'
        .. 'Soul:RancorEnchant_Charge:12.00Health_Left:40Owned:3'
        .. 'X:1.00  Y:2.50  Z:-3.00  X_Angle:0.00  Y_Angle:0.25  Z_Angle:1.00Destination:Bay'
        .. 'Lock_Level:50Key:SW_KeyTrap_Spell:SW_TrapDELETED:0'
        .. 'X:9336.000  Y:12.125  Z:-40.000  X_Angle:0.0000  Y_Angle:1.5000  Z_Angle:3.1416'
    )
    expect(surgery.instanceText { mastIndex = 0, refrIndex = 1, id = 'Rock', key = jess.null }).toBe(
      'ObjIdx:1  MastIdx:0Name:Rock'
    )
  end)

  suite.it('reads a cell by its names and references, and any other record by its strings', function()
    local cell = surgery.recordText {
      type = 'Cell',
      name = 'Bay',
      region = 'Taris Region',
      references = {
        { mastIndex = 0, refrIndex = 1, id = 'Rock' },
        { mastIndex = 0, refrIndex = 2, id = 'Tree' },
      },
    }

    expect(cell).toBe 'Bay\nTaris Region\nObjIdx:1  MastIdx:0Name:Rock\nObjIdx:2  MastIdx:0Name:Tree'
    -- A record's fields come in no order of their own; a list's items in theirs.
    local static = surgery.recordText { type = 'Static', id = 'Rock' }
    expect(static == 'Static\nRock' or static == 'Rock\nStatic').toBe(true)

    local armor = surgery.recordText { type = 'Armor', parts = { { 'Left', 7 }, { 'Right' } } }
    expect(armor).toContain 'Left\nRight'
  end)

  suite.it('reads and writes a bytes field as tes3conv spells one', function()
    expect(surgery.toBytesField '').toBe 'AAAAAA=='
    expect(surgery.bytesField 'BAAAAF8RAQE=').toBe '\x5f\x11\x01\x01'
    expect(surgery.base64Encode 'a').toBe 'YQ=='
    expect(surgery.base64Encode 'ab').toBe 'YWI='
    expect(surgery.base64Encode 'abc').toBe 'YWJj'
    expect(surgery.base64Decode 'YW Jj\nZA==').toBe 'abcd'

    local every = {}

    for byte = 0, 255 do
      every[byte + 1] = string.char(byte)
    end

    local all = table.concat(every)
    expect(surgery.bytesField(surgery.toBytesField(all))).toBe(all)
  end)
end)

return suite
