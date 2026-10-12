--!strict
--!native
-- motherjungle_audit.dependencies: the typed references the closure audit and the split follow,
-- one entry per field occurrence, kinds and all.

local tes3 = require '@tes3conv/records'

type Table = tes3.Table
type Value = tes3.Value
type Record = tes3.Record

export type Dependency = {
  target: string,
  target_original: string,
  source_type: string,
  source_id: string,
  kind: string,
}

local dependencies = {}

dependencies.HardKinds = {} :: { [string]: boolean }

local HardKindNames = {
  'race.spells',
  'soundgen.creature',
  'soundgen.sound',
  'magic_effect.bolt_sound',
  'magic_effect.cast_sound',
  'magic_effect.hit_sound',
  'magic_effect.area_sound',
  'magic_effect.cast_visual',
  'magic_effect.bolt_visual',
  'magic_effect.hit_visual',
  'magic_effect.area_visual',
  'region.sleep_creature',
  'region.sounds',
  'birthsign.spells',
  'door.script',
  'door.open_sound',
  'door.close_sound',
  'miscitem.script',
  'weapon.script',
  'weapon.enchanting',
  'container.script',
  'container.inventory',
  'creature.script',
  'creature.inventory',
  'creature.spells',
  'creature.ai.activate',
  'creature.sound',
  'bodypart.race',
  'light.script',
  'light.sound',
  'npc.script',
  'npc.inventory',
  'npc.spells',
  'npc.ai.activate',
  'npc.race',
  'npc.class',
  'npc.faction',
  'npc.head',
  'npc.hair',
  'armor.script',
  'armor.enchanting',
  'armor.male_bodypart',
  'armor.female_bodypart',
  'clothing.script',
  'clothing.enchanting',
  'clothing.male_bodypart',
  'clothing.female_bodypart',
  'repairitem.script',
  'activator.script',
  'apparatus.script',
  'lockpick.script',
  'probe.script',
  'ingredient.script',
  'book.script',
  'book.enchanting',
  'alchemy.script',
  'leveled_item.items',
  'leveled_creature.creatures',
  'cell.region',
  'cell.reference.id',
  'cell.reference.owner',
  'cell.reference.owner_global',
  'cell.reference.owner_faction',
  'cell.reference.key',
  'cell.reference.trap',
  'cell.reference.soul',
  'info.speaker_id',
  'info.speaker_race',
  'info.speaker_class',
  'info.speaker_faction',
  'info.player_faction',
  'faction.reaction',
}

for _, kind in HardKindNames do
  dependencies.HardKinds[kind] = true
end

-- TES3/TESCS's "-NO FACTION-" sentinel in dialogue faction fields.
local NoFaction = 'ffff'

-- The types whose one dependency is a script, and the kind each is.
local ScriptOnly: { [string]: string } = {
  MiscItem = 'miscitem.script',
  RepairItem = 'repairitem.script',
  Activator = 'activator.script',
  Apparatus = 'apparatus.script',
  Lockpick = 'lockpick.script',
  Probe = 'probe.script',
  Ingredient = 'ingredient.script',
  Alchemy = 'alchemy.script',
}

-- Fields read one after another, each with the kind of dependency it is.
local MagicEffectFields = {
  { 'boltSound', 'magic_effect.bolt_sound' },
  { 'castSound', 'magic_effect.cast_sound' },
  { 'hitSound', 'magic_effect.hit_sound' },
  { 'areaSound', 'magic_effect.area_sound' },
  { 'castVisual', 'magic_effect.cast_visual' },
  { 'boltVisual', 'magic_effect.bolt_visual' },
  { 'hitVisual', 'magic_effect.hit_visual' },
  { 'areaVisual', 'magic_effect.area_visual' },
}

local ReferenceFields = {
  { 'owner', 'cell.reference.owner' },
  { 'ownerGlobal', 'cell.reference.owner_global' },
  { 'ownerFaction', 'cell.reference.owner_faction' },
  { 'key', 'cell.reference.key' },
  { 'trap', 'cell.reference.trap' },
  { 'soul', 'cell.reference.soul' },
}

local NpcFields = {
  { 'race', 'npc.race' },
  { 'class', 'npc.class' },
  { 'faction', 'npc.faction' },
  { 'head', 'npc.head' },
  { 'hair', 'npc.hair' },
}

local FactionFields = {
  { 'speakerFaction', 'info.speaker_faction' },
  { 'playerFaction', 'info.player_faction' },
}

-- What armor and clothing name, each under its own kinds.
local Worn = {
  Armor = {
    script = 'armor.script',
    enchanting = 'armor.enchanting',
    male = 'armor.male_bodypart',
    female = 'armor.female_bodypart',
  },
  Clothing = {
    script = 'clothing.script',
    enchanting = 'clothing.enchanting',
    male = 'clothing.male_bodypart',
    female = 'clothing.female_bodypart',
  },
}

-- The types that name anything. A record of any other has no dependencies.
local Naming: { [string]: boolean } = {
  Race = true,
  SoundGen = true,
  MagicEffect = true,
  Region = true,
  Birthsign = true,
  Door = true,
  Weapon = true,
  Container = true,
  Creature = true,
  Bodypart = true,
  Light = true,
  Npc = true,
  Armor = true,
  Clothing = true,
  Book = true,
  LeveledItem = true,
  LeveledCreature = true,
  Cell = true,
  DialogueInfo = true,
  Faction = true,
}

-- What a record that names nothing depends on. Nothing is ever added to it.
local None: { Dependency } = table.freeze {}

local function list(value: Value?): { Value } return (value or {}) :: { Value } end

-- One record's dependencies as they are found: the list, and what each is reported from.
type Found = { out: { Dependency }, kind: string, sourceId: string }

-- Most of what is offered is no id at all, and is turned away before the record is read.
local function add(found: Found, value: Value?, dependency: string)
  if type(value) ~= 'string' or value == '' then return end

  table.insert(found.out, {
    target = string.lower(value),
    target_original = value,
    source_type = found.kind,
    source_id = found.sourceId,
    kind = dependency,
  })
end

local function inventory(found: Found, record: Record, dependency: string)
  for _, pair in list(record.inventory) do
    local item = pair :: Table

    if #item > 1 then add(found, item[2], dependency) end
  end
end

local function spells(found: Found, record: Record, dependency: string)
  for _, spell in list(record.spells) do
    add(found, spell, dependency)
  end
end

local function activate(found: Found, record: Record, dependency: string)
  for _, package in list(record.aiPackages) do
    local ai = package :: Table

    if ai.type == 'Activate' then add(found, ai.target, dependency) end
  end
end

-- The dependencies of `record`, the `ordinal`th record of its plugin.
function dependencies.of(record: Record, ordinal: number): { Dependency }
  local kind = tes3.string(record.type)

  if not Naming[kind] and not ScriptOnly[kind] then return None end

  local sourceId = tes3.auditId(record)

  if sourceId == '' then sourceId = tes3.string(record.name) end

  if sourceId == '' then sourceId = `#{ordinal}` end

  local out: { Dependency } = {}
  local found: Found = { out = out, kind = kind, sourceId = sourceId }

  if kind == 'Race' then
    spells(found, record, 'race.spells')
  elseif kind == 'SoundGen' then
    add(found, record.creature, 'soundgen.creature')
    add(found, record.sound, 'soundgen.sound')
  elseif kind == 'MagicEffect' then
    for _, field in MagicEffectFields do
      add(found, record[field[1]], field[2])
    end
  elseif kind == 'Region' then
    add(found, record.sleepCreature, 'region.sleep_creature')

    for _, pair in list(record.sounds) do
      local sound = pair :: Table

      if #sound > 0 then add(found, sound[1], 'region.sounds') end
    end
  elseif kind == 'Birthsign' then
    spells(found, record, 'birthsign.spells')
  elseif kind == 'Door' then
    add(found, record.script, 'door.script')
    add(found, record.openSound, 'door.open_sound')
    add(found, record.closeSound, 'door.close_sound')
  elseif ScriptOnly[kind] then
    add(found, record.script, ScriptOnly[kind])
  elseif kind == 'Weapon' then
    add(found, record.script, 'weapon.script')
    add(found, record.enchanting, 'weapon.enchanting')
  elseif kind == 'Container' then
    add(found, record.script, 'container.script')
    inventory(found, record, 'container.inventory')
  elseif kind == 'Creature' then
    add(found, record.script, 'creature.script')
    inventory(found, record, 'creature.inventory')
    spells(found, record, 'creature.spells')
    activate(found, record, 'creature.ai.activate')
    add(found, record.sound, 'creature.sound')
  elseif kind == 'Bodypart' then
    add(found, record.race, 'bodypart.race')
  elseif kind == 'Light' then
    add(found, record.script, 'light.script')
    add(found, record.sound, 'light.sound')
  elseif kind == 'Npc' then
    add(found, record.script, 'npc.script')
    inventory(found, record, 'npc.inventory')
    spells(found, record, 'npc.spells')
    activate(found, record, 'npc.ai.activate')

    for _, field in NpcFields do
      add(found, record[field[1]], field[2])
    end
  elseif kind == 'Armor' or kind == 'Clothing' then
    local kinds = Worn[kind]
    add(found, record.script, kinds.script)
    add(found, record.enchanting, kinds.enchanting)

    for _, part in list(record.bipedObjects) do
      add(found, (part :: Table).maleBodypart, kinds.male)
      add(found, (part :: Table).femaleBodypart, kinds.female)
    end
  elseif kind == 'Book' then
    add(found, record.script, 'book.script')
    add(found, record.enchanting, 'book.enchanting')
  elseif kind == 'LeveledItem' then
    for _, pair in list(record.items) do
      local item = pair :: Table

      if #item > 0 then add(found, item[1], 'leveled_item.items') end
    end
  elseif kind == 'LeveledCreature' then
    for _, pair in list(record.creatures) do
      local creature = pair :: Table

      if #creature > 0 then add(found, creature[1], 'leveled_creature.creatures') end
    end
  elseif kind == 'Cell' then
    add(found, record.region, 'cell.region')

    for _, value in list(record.references) do
      local reference = value :: Table
      add(found, reference.id, 'cell.reference.id')

      for _, field in ReferenceFields do
        add(found, reference[field[1]], field[2])
      end
    end
  elseif kind == 'DialogueInfo' then
    add(found, record.speakerId, 'info.speaker_id')
    add(found, record.speakerRace, 'info.speaker_race')
    add(found, record.speakerClass, 'info.speaker_class')

    for _, field in FactionFields do
      local value = record[field[1]]

      if tes3.lower(value) ~= NoFaction then add(found, value, field[2]) end
    end
  elseif kind == 'Faction' then
    for _, reaction in list(record.reactions) do
      add(found, (reaction :: Table).faction, 'faction.reaction')
    end
  end

  return out
end

return dependencies
