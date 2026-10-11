--!strict
--!native
-- The Starwind port's own cases, on records small enough to read: the tes3cmd and validator
-- corners the Python build depends on. The tool ports' semantics are in their own packages'
-- suites.
local starwind = require '@starwind'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

type Record = { [string | number]: any }

local function header(masters: { { string | number } }?): Record
  return {
    type = 'Header',
    flags = '',
    version = 1.3,
    fileType = 'Esp',
    author = '',
    description = '',
    numObjects = 0,
    masters = masters or {},
  }
end

local function misc(id: string, script: string?): Record
  return {
    type = 'MiscItem',
    flags = '',
    id = id,
    name = id,
    script = script or '',
    mesh = '',
    icon = '',
  }
end

local function dial(id: string, kind: string?): Record
  return { type = 'Dialogue', flags = '', id = id, dialogueType = kind or 'Topic' }
end

local function info(id: string, prev: string?, next: string?, fields: Record?): Record
  local record: Record = {
    type = 'DialogueInfo',
    flags = '',
    id = id,
    prevId = prev or '',
    nextId = next or '',
    speakerId = '',
    speakerRace = '',
    speakerClass = '',
    speakerFaction = '',
    speakerCell = '',
    playerFaction = '',
    soundPath = '',
    text = '',
    scriptText = '',
    filters = {},
    data = {
      dialogueType = 'Topic',
      disposition = 0,
      speakerRank = -1,
      speakerSex = 'Any',
      playerRank = -1,
    },
  }

  for key, value in fields or {} do
    record[key] = value
  end

  return record
end

suite.describe('tes3cmd surgery', function()
  local surgery = starwind.surgery

  local function reference(index: number, id: string, temporary: boolean, fields: Record?): Record
    local value: Record = {
      mastIndex = 0,
      refrIndex = index,
      id = id,
      temporary = temporary,
      translation = { 0, 0, 0 },
      rotation = { 0, 0, 0 },
    }

    for key, item in fields or {} do
      value[key] = item
    end

    return value
  end

  local function cell(references: { Record }): Record
    return {
      type = 'Cell',
      flags = 'PERSISTENT',
      name = 'Lair',
      data = { flags = 'IS_INTERIOR', grid = { 0, 0 } },
      references = references,
    }
  end

  suite.it(
    'matches instances by their dump text, and rebuilds the cell without its header flags',
    function()
      local records = {
        header(),
        cell {
          reference(1, 'SW_SignCantina', false),
          reference(2, 'Bench', true, { owner = 'Adele' }),
          reference(3, 'Rock', true),
        },
      }
      expect(surgery.deleteInstances(records, { instance = 'DELE' })).toBe(1)
      expect(#records[2].references).toBe(2)
      expect(records[2].flags).toBe ''
    end
  )

  suite.it(
    'loses NAM0 with the reference it follows, leaving every reference persistent',
    function()
      local records = {
        header(),
        cell {
          reference(1, 'Door', false),
          reference(2, 'Tombstone', false, { deleted = true }),
          reference(3, 'Rock', true),
          reference(4, 'Tree', true),
        },
      }
      surgery.deleteDeletedInstances(records)
      local persistence = {}

      for _, value in records[2].references do
        persistence[value.id] = value.temporary
      end

      expect(persistence).toEqual { Door = false, Rock = false, Tree = false }

      local kept = {
        header(),
        cell {
          reference(1, 'Tombstone', false, { deleted = true }),
          reference(2, 'Door', false),
          reference(3, 'Rock', true),
        },
      }
      surgery.deleteDeletedInstances(kept)
      expect(kept[2].references[2].temporary).toBe(true)
    end
  )

  suite.it('reads a leveled list\'s orphaned level onto the entry before', function()
    local records = {
      header(),
      {
        type = 'LeveledCreature',
        flags = 'BLOCKED',
        id = 'Sand',
        creatures = { { 'Jawa', 1 }, { 'SW_Rakhoul1', 5 }, { 'Tusken', 3 } },
      },
    }
    surgery.deleteLeveledCreatures(records, 'sand', 'SW_Rakhoul1')
    expect(records[2].creatures).toEqual { { 'Jawa', 5 }, { 'Tusken', 3 } }
    expect(records[2].flags).toBe ''
  end)

  suite.it('ids cells and path grids the way tes3cmd does', function()
    expect(surgery.id {
      type = 'Cell',
      name = '',
      region = 'Tatooine Region',
      data = { flags = '', grid = { -2, 3 } },
    }).toBe 'tatooine region (-2, 3)'
    expect(surgery.id { type = 'PathGrid', cell = 'Hall', data = { grid = { 0, 0 } } }).toBe 'hall'
    expect(surgery.id { type = 'MagicEffect', effectId = 'TurnUndead' }).toBe '101'
  end)
end)

suite.describe('dialogue audit', function()
  local dialogue = starwind.dialogue

  suite.it('doesn\'t move an INFO whose previous INFO is itself', function()
    local replay = dialogue.replay {
      {
        name = 'test',
        records = {
          header(),
          dial 'test',
          info('First', '', ''),
          info('Second', 'First', ''),
          info('First', 'First', ''),
        },
      },
    }
    expect(dialogue.finalizedOrder(replay.dialogues.test)).toEqual { 'first', 'second' }
  end)

  suite.it('erases a deleted topic and keeps adding to the one before it', function()
    local deleted = dial 'Gone'
    deleted.flags = 'DELETED'
    local replay = dialogue.replay {
      {
        name = 'test',
        records = { header(), dial 'Kept', info('A', '', ''), deleted, info('B', 'A', '') },
      },
    }
    expect(replay.dialogues.gone).toBeNil()
    expect(dialogue.finalizedOrder(replay.dialogues.kept)).toEqual { 'a', 'b' }
  end)
end)

suite.describe('split', function()
  suite.it('demotes candidates to a fixed point when what they need is content', function()
    local records = {
      header(),
      { type = 'Script', flags = '', id = 'BagScript', text = '' },
      misc('Bag', 'BagScript'),
      { type = 'Container', flags = '', id = 'Crate', script = '', inventory = { { 1, 'Bag' } } },
      { type = 'Static', flags = '', id = 'Rock' },
    }
    local data, demotions = starwind.split.choose(records)
    expect(data[4]).toBe(true)
    expect(data[2]).toBeNil()
    expect(data[3]).toBeNil()
    expect(#demotions).toBe(2)
  end)
end)

return suite
