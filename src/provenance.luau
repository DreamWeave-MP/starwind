--!strict
--!native
-- late_actor_provenance.py: the actors that appear only after dialogue liveness and the second
-- closure, and why each was imported. A diagnostic, never a deletion list.
--
-- The Python report replays dialogue against two legacy defaults (a Solo build under
-- .swbuild/solo, and the canonical vanilla JSON) instead of the Definitive build's own inputs,
-- and a checkout without that Solo build fails here. This one uses the Definitive build's:
-- the projection the dialogue audit already made from the staged masters and the
-- pre-decoupling plugin.

local dialogue = require './dialogue'
local hygiene = require './hygiene'
local report = require './report'
local tes3 = require '@tes3conv/records'

type Record = tes3.Record
type Records = tes3.Records
type Table = tes3.Table
type Value = tes3.Value
type Json = report.Json

local provenance = {}

local ActorTypes = { NPC = true, NPC_ = true, CREA = true, Npc = true, Creature = true }

local function norm(value: Value?): string return string.lower(tes3.string(value)) end

local function afterSnapshot(log: { string }): number
  for index, line in log do
    if line == 'Dialogue liveness population end' then return index + 1 end
  end

  return #log + 1
end

local function snapshot(log: { string }): { [string]: { [string]: string } }
  local actors = {}
  local inside = false

  for _, line in log do
    if line == 'Dialogue liveness population begin' then
      inside = true
    elseif line == 'Dialogue liveness population end' then
      inside = false
    elseif inside and string.sub(line, 1, 24) == 'Dialogue liveness actor\t' then
      local fields = string.split(line, '\t')

      if #fields == 6 then
        actors[string.lower(fields[3])] = {
          id = string.lower(fields[3]),
          type = fields[2],
          race = string.lower(fields[4]),
          class = string.lower(fields[5]),
          sex = string.lower(fields[6]),
        }
      end
    end
  end

  return actors
end

local function copies(log: { string }): { [string]: Json }
  local result: { [string]: Json } = {}

  for index = afterSnapshot(log), #log do
    local line = log[index]

    -- Few lines are a copy's, and the pattern is tried from every place in one that isn't.
    if not string.find(line, 'Copying \'', 1, true) then continue end

    local id, kind, source =
      string.match(line, 'Copying \'(.+)\' %(([^)]+)%) to \'Starwind%.esp\' from \'([^\']+)\'')

    if id and ActorTypes[kind :: string] and result[norm(id)] == nil then
      result[norm(id)] =
        report.object { 'id', id, 'type', kind, 'source_master', source, 'copy_log_line', index }
    end
  end

  return result
end

local function imports(log: { string }): { [string]: { { [string]: Json } } }
  local result: { [string]: { { [string]: Json } } } = {}
  local current: { [string]: Json }? = nil

  for index = afterSnapshot(log), #log do
    local line = log[index]

    if line == 'Dependency import:' then
      current = report.object { 'log_line', index }
      continue
    end

    if not current then continue end

    local entry = current :: { [string]: Json }
    local pass = string.match(line, '^  pass=(.+)$')
    local targetType, targetId = string.match(line, '^  target=([^ ]+) \'(.+)\'$')
    local sourceType, sourceId = string.match(line, '^  source=([^ ]+) \'(.+)\'$')
    local field = string.match(line, '^  field=(.+)$')

    if pass then
      report.set(entry, 'pass', pass)
    elseif targetType then
      report.set(entry, 'target_type', targetType)
      report.set(entry, 'target_id', targetId)
    elseif sourceType then
      report.set(entry, 'source_type', sourceType)
      report.set(entry, 'source_id', sourceId)
    elseif field then
      report.set(entry, 'field', field)
    end

    if entry.target_id ~= nil and entry.field ~= nil then
      local key = norm(entry.target_id :: string)
      result[key] = result[key] or {}
      table.insert(result[key], entry)
      current = nil
    end
  end

  return result
end

local function compactActor(record: Record, source: string, index: number): { [string]: Json }
  local npc = record.type == 'Npc'

  return report.object {
    'id',
    tes3.string(record.id),
    'type',
    record.type :: Json,
    'race',
    if npc then tes3.string(record.race) else '',
    'class',
    if npc then tes3.string(record.class) else '',
    'faction',
    if npc then tes3.string(record.faction) else '',
    'sex',
    if npc
      then (if tes3.hasFlag(string.upper(tes3.string(record.npcFlags)), 'FEMALE')
        then 'female'
        else 'male')
      else '',
    'script',
    tes3.string(record.script),
    'source',
    source,
    'source_record_index',
    index,
  }
end

-- The ids a scan looks for, all lowercase, and what it has learned of the values it has met:
-- for each string and boolean, its text lowercased when that is one of the ids, and false when
-- it isn't. Most of a plugin's strings are ids and types it holds many times over. `numbers` is
-- whether some id is a number's text, which is the only way a number names one.
type Sought = {
  ids: { [string]: boolean },
  known: { [string | boolean]: string | false },
  numbers: boolean,
}

local function seeking(ids: { [string]: boolean }): Sought
  local numbers = false

  for id in ids do
    numbers = numbers or tonumber(id) ~= nil
  end

  return { ids = ids, known = {}, numbers = numbers }
end

-- Which of the ids sought a scalar names, by its text, lowercased, as `record_values` reads
-- every scalar a record holds.
local function sought(seek: Sought, value: Value): string?
  local kind = type(value)

  if kind == 'number' and not seek.numbers then return nil end

  if kind ~= 'string' and kind ~= 'boolean' then
    local text = string.lower(tostring(value))
    return if seek.ids[text] then text else nil
  end

  local key = value :: string | boolean
  local known = seek.known[key]

  if known == nil then
    local text = string.lower(tostring(value))
    known = if seek.ids[text] then text else false
    seek.known[key] = known
  end

  return known or nil
end

-- The dotted path the first `depth` of `steps` lead to, as `record_values` spells one: a list's
-- step is a place, counted from 0, and a record's is a field's name.
local function pathTo(steps: { string | number }, depth: number): string
  local path = ''

  for position = 1, depth do
    local step = steps[position]

    if type(step) == 'number' then
      path = `{path}[{step}]`
    else
      path = if path == '' then step else `{path}.{step}`
    end
  end

  return path
end

type Hits = { [string]: { Json } }

-- One record's part in a scan: what the scan looks for and where its hits go, the record, and
-- the steps from it to the value being read.
type Search = {
  seek: Sought,
  exact: Hits,
  placed: Hits,
  label: string,
  file: string,
  record: Record,
  recordId: string,
  recordIndex: number,
  steps: { string | number },
}

-- Reads every scalar in `value`, which is `depth` steps into the search's record, as
-- `record_values` walks one, and keeps each that names an id sought. Only a hit's path is
-- spelled.
local function search(found: Search, value: Value?, depth: number)
  if type(value) == 'table' then
    local container = value :: Table
    local steps = found.steps

    if #container > 0 then
      for index, item in container do
        steps[depth + 1] = (index :: number) - 1
        search(found, item, depth + 1)
      end

      return
    end

    for key, item in container do
      steps[depth + 1] = report.snakeKey(tostring(key))
      search(found, item, depth + 1)
    end

    return
  end

  if value == nil then return end

  local target = sought(found.seek, value)

  if not target then return end

  local path = pathTo(found.steps, depth)

  -- A record's own id isn't a reference to it.
  if path == 'id' and target == found.recordId then return end

  local record = found.record
  local hit = report.object {
    'source',
    found.label,
    'source_file',
    found.file,
    'record_type',
    record.type :: Json,
    'record_id',
    tes3.string(record.id),
    'record_index',
    found.recordIndex,
    'field',
    path,
  }
  table.insert(found.exact[target], hit)

  if record.type == 'Cell' and string.find(path, 'references', 1, true) then
    table.insert(found.placed[target], hit)
  end
end

-- Whether `text` names `id` as a whole word: no word character or hyphen on either side.
local function mentions(text: string, id: string): boolean
  local start = 1

  while true do
    local first, last = string.find(text, id, start, true)

    if not first then return false end

    local before = if first > 1 then string.sub(text, first - 1, first - 1) else ''
    local after = string.sub(text, (last :: number) + 1, (last :: number) + 1)

    if not string.find(before, '^[%w_-]$') and not string.find(after, '^[%w_-]$') then
      return true
    end

    start = first + 1
  end
end

local function scan(
  records: Records,
  label: string,
  file: string,
  seek: Sought
): (Hits, Hits, Hits)
  local ids = seek.ids
  local exact, scripts, placed = {}, {}, {}

  for id in ids do
    exact[id], scripts[id], placed[id] = report.array(), report.array(), report.array()
  end

  local found: Search = {
    seek = seek,
    exact = exact,
    placed = placed,
    label = label,
    file = file,
    record = {},
    recordId = '',
    recordIndex = 0,
    steps = {},
  }

  for position, record in records do
    local kind = record.type

    if kind == 'Dialogue' or kind == 'DialogueInfo' then continue end

    found.record, found.recordId, found.recordIndex = record, norm(record.id), position - 1
    search(found, record, 0)

    if kind == 'Script' then
      local text = string.lower(tes3.string(record.text))

      for id in ids do
        if mentions(text, id) then
          table.insert(
            scripts[id],
            report.object {
              'source',
              label,
              'source_file',
              file,
              'record_type',
              kind :: Json,
              'record_id',
              tes3.string(record.id),
              'record_index',
              position - 1,
            }
          )
        end
      end
    end
  end

  return exact, scripts, placed
end

local function classify(
  references: { Json },
  nonDialogue: { Json },
  candidates: { Json },
  causal: { Json }
): (string, string)
  local categories: { [string]: boolean } = {}

  for _, value in references do
    categories[(value :: { [string]: Json }).hygiene_classification :: string] = true
  end

  local onlyDirt = categories.PROBABLE_TESCS_LINK_DIRT == true
    and next(categories, next(categories)) == nil

  if #nonDialogue > 0 then
    return 'D', 'has a surviving non-dialogue dependency in the final standalone'
  elseif #references > 0 and onlyDirt then
    return 'A', 'all surviving speaker_id INFOs are probable TESCS link dirt'
  elseif categories.NEW_INFO then
    return 'C', 'at least one surviving speaker_id INFO is a new Starwind INFO'
  elseif categories.MODIFIED_PARENT then
    return 'B', 'at least one surviving speaker_id INFO semantically modifies its parent'
  elseif #causal > 0 then
    return 'D', 'post-dialogue dependency telemetry identifies the import cause'
  elseif #references == 0 and #candidates > 0 then
    return 'D', 'no surviving dependency found; canonical source has candidate references to trace'
  elseif #references == 0 then
    return 'D', 'not explained solely by probable link dirt or a Starwind semantic INFO'
  end

  return 'D',
    'surviving speaker_id INFO is inherited or otherwise not a classified Starwind modification'
end

export type Inputs = {
  log: { string },
  logPath: string,
  final: Records,
  finalPath: string,
  projection: {
    [string]: {
      order: { string },
      infos: { [string]: { record: Record, source: string, sourceIndex: number } },
    },
  },
  audit: Json,
  -- Read only when there are late actors.
  vanillaSources: () -> { hygiene.Source },
  starwindSources: () -> { hygiene.Source },
}

export type Paths = { report: string, markdown: string, cleanup: string }

local function writeMarkdown(path: string, result: { [string]: Json })
  local lines = {
    '# Late Actor Provenance',
    '',
    `Second-closure actors: **{result.late_actor_count}** ({result.snapshot_actor_count} pre-liveness, {result.final_actor_count} final).`,
    '',
    '| Class | Count |',
    '| --- | ---: |',
  }

  local classes = result.late_actor_class_counts :: { [string]: Json }
  local names = {}

  for name in classes do
    table.insert(names, name)
  end

  table.sort(names)

  for _, name in names do
    table.insert(lines, `| {name} | {classes[name]} |`)
  end

  table.insert(lines, '')
  table.insert(lines, '| Actor | Master | Class | Dialogue refs | Other refs | Causal imports |')
  table.insert(lines, '| --- | --- | --- | ---: | ---: | ---: |')

  for _, value in result.actors :: { Json } do
    local row = value :: { [string]: Json }
    local why = row.why_imported_on_second_closure :: { [string]: Json }
    table.insert(
      lines,
      `| \`{(row.actor :: { [string]: Json }).id}\` | \`{row.source_master or '?'}\` | {why.reason_class} | {why.direct_live_dialogue_speaker_id_references} | {why.non_dialogue_exact_references} | {why.causal_dependency_imports} |`
    )
  end

  jess.fs.write(path, table.concat(lines, '\n') .. '\n', { backup = false })
end

local function writeCleanup(path: string, byFile: { [string]: Json })
  local lines = {
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '',
    '# Generated by late_actor_provenance.py. REVIEW BEFORE EXECUTION.',
    '# Run from the sw_merged/plugins directory, or set TES3CMD explicitly.',
    'TES3CMD="${TES3CMD:-../tes3cmd}"',
    '',
  }

  local binaries = {
    ['StarwindRemasteredPatch.json'] = 'StarwindRemasteredPatch.esm',
    ['StarwindRemasteredV1.15.json'] = 'StarwindRemasteredV1.15.esm',
  }
  local sources = {}

  for source in byFile do
    table.insert(sources, source)
  end

  table.sort(sources)

  for _, source in sources do
    local binary = binaries[source]

    if not binary then error(`no binary mapping for {source}`) end

    local ids = byFile[source] :: { Json }
    table.insert(lines, `# {binary}: {#ids} Class-A INFOs`)
    local command = { '"$TES3CMD"', 'delete', '--type', 'INFO' }

    for _, id in ids do
      table.insert(command, '--exact-id')
      table.insert(command, id :: string)
    end

    table.insert(command, binary)
    table.insert(lines, table.concat(command, ' '))
    table.insert(lines, '')
  end

  jess.fs.write(path, table.concat(lines, '\n'), { backup = false })
end

function provenance.report(inputs: Inputs, paths: Paths): { [string]: Json }
  local before = snapshot(inputs.log)
  local copied = copies(inputs.log)
  local causes = imports(inputs.log)
  local final: { [string]: { [string]: Json } } = {}

  for position, record in inputs.final do
    if (record.type == 'Npc' or record.type == 'Creature') and not tes3.isDeleted(record) then
      final[norm(record.id)] = compactActor(record, inputs.finalPath, position - 1)
    end
  end

  local infoTopics: { [string]: string } = {}
  local topic = ''

  for _, record in inputs.final do
    if record.type == 'Dialogue' then
      topic = tes3.string(record.id)
    elseif record.type == 'DialogueInfo' and tes3.string(record.id) ~= '' then
      infoTopics[norm(record.id)] = topic
    end
  end

  local lateIds = {}

  for id in final do
    if not before[id] then table.insert(lateIds, id) end
  end

  table.sort(lateIds)
  local rows = report.array()
  local classes: { [string]: number } = {}
  local classA: { [string]: { [string]: boolean } } = {}

  if #lateIds > 0 then
    local lateSet = {}

    for _, id in lateIds do
      lateSet[id] = true
    end

    -- The layered hygiene classification of V1.15 and the Patch, by topic and INFO.
    local hygieneRows: { [string]: { [string]: Json } } = {}
    local state = hygiene.vanillaState(inputs.vanillaSources())

    for _, source in inputs.starwindSources() do
      local classified = hygiene.classify(source, state)

      for _, value in classified.records :: { Json } do
        local row = value :: { [string]: Json }
        hygieneRows[`{row.topic}\0{row.info_id}`] = row
      end

      hygiene.apply(state, source.records, source.label)
    end

    local seek = seeking(lateSet)
    local exact, scripts, placed =
      scan(inputs.final, 'Starwind-Standalone.omwaddon', inputs.finalPath, seek)
    local sourceExact, sourceScripts, sourcePlaced = {}, {}, {}

    for id in lateSet do
      sourceExact[id], sourceScripts[id], sourcePlaced[id] =
        report.array(), report.array(), report.array()
    end

    local vanillaActors: { [string]: { [string]: Json } } = {}
    local sourceList = table.clone(inputs.vanillaSources())

    for _, source in inputs.starwindSources() do
      table.insert(sourceList, source)
    end

    for _, source in sourceList do
      local foundExact, foundScripts, foundPlaced =
        scan(source.records, source.label, source.path, seek)

      for id in lateSet do
        table.move(foundExact[id], 1, #foundExact[id], #sourceExact[id] + 1, sourceExact[id])
        table.move(
          foundScripts[id],
          1,
          #foundScripts[id],
          #sourceScripts[id] + 1,
          sourceScripts[id]
        )
        table.move(foundPlaced[id], 1, #foundPlaced[id], #sourcePlaced[id] + 1, sourcePlaced[id])
      end
    end

    -- Bloodmoon, Tribunal, Morrowind: addVanillaRefs's lookup order.
    local vanilla = inputs.vanillaSources()

    for position = #vanilla, 1, -1 do
      local source = vanilla[position]

      for index, record in source.records do
        if (record.type == 'Npc' or record.type == 'Creature') and not tes3.isDeleted(record) then
          local id = norm(record.id)

          if lateSet[id] and vanillaActors[id] == nil then
            vanillaActors[id] = compactActor(record, source.binary or source.label, index - 1)
          end
        end
      end
    end

    -- The live INFOs each late actor says, with the topic each is in, in the projection's order.
    type Said = { topic: string, record: Record, source: string, sourceIndex: number }
    local said: { [string]: { Said } } = {}

    for topicId, item in inputs.projection do
      for _, entry in item.infos do
        local speaker = norm(entry.record.speakerId)

        if not lateSet[speaker] then continue end

        local lines = said[speaker] or {}
        said[speaker] = lines
        table.insert(lines, {
          topic = topicId,
          record = entry.record,
          source = entry.source,
          sourceIndex = entry.sourceIndex,
        })
      end
    end

    for _, id in lateIds do
      local actor = final[id]
      local direct = report.array()

      for _, entry in said[id] or {} do
        local topicId, record = entry.topic, entry.record
        local key = `{topicId}\0{norm(record.id)}`
        local row = hygieneRows[key]
        local data = (record.data or {}) :: Table
        table.insert(
          direct,
          report.object {
            'dial',
            topicId,
            'info_id',
            tes3.string(record.id),
            'source',
            entry.source,
            'source_record_index',
            entry.sourceIndex,
            'hygiene_classification',
            if row then row.category else 'INHERITED_VANILLA',
            'tescs_dirt_confidence',
            if row then row.tescs_dirt_confidence else nil,
            'changed_links',
            if row then row.changed_links else report.object {},
            'parent_source',
            if row then row.parent_source else nil,
            'parent_record_index',
            if row then row.parent_record_index else nil,
            'speaker_id',
            tes3.string(record.speakerId),
            'speaker_race',
            tes3.string(record.speakerRace),
            'speaker_class',
            tes3.string(record.speakerClass),
            'speaker_faction',
            tes3.string(record.speakerFaction),
            'speaker_cell',
            tes3.string(record.speakerCell),
            'speaker_sex',
            (data.speakerSex or '') :: Json,
            'speaker_rank',
            (data.speakerRank or -1) :: Json,
            'player_faction',
            tes3.string(record.playerFaction),
            'text',
            tes3.string(record.text),
            'result',
            '',
            'filters',
            report.snake((record.filters or report.array()) :: Json),
          }
        )
      end

      local hits = exact[id] :: { { [string]: Json } }
      local nonDialogue = report.array(
        [for hit in hits if hit.record_type ~= 'Npc' and hit.record_type ~= 'Creature' => hit]
      )

      local causal = report.array()

      for _, entry in causes[id] or {} do
        if string.lower(tes3.string(entry.source_type :: string)) == 'info' then
          report.set(entry, 'source_topic', infoTopics[norm(entry.source_id :: string)] or '')
        end

        table.insert(causal, entry)
      end

      local class, rationale = classify(direct, nonDialogue, sourceExact[id], causal)
      classes[class] = (classes[class] or 0) + 1
      local copy = copied[id] :: { [string]: Json }?
      local vanillaActor = vanillaActors[id]

      if class == 'A' then
        for _, value in direct do
          local reference = value :: { [string]: Json }

          if reference.hygiene_classification ~= 'PROBABLE_TESCS_LINK_DIRT' then continue end

          local source = reference.source :: string
          classA[source] = classA[source] or {}
          classA[source][norm(reference.info_id :: string)] = true
        end
      end

      table.insert(
        rows,
        report.object {
          'actor',
          actor,
          'source_master',
          (copy and copy.source_master) or (vanillaActor and vanillaActor.source) or nil,
          'source_record_index',
          vanillaActor and vanillaActor.source_record_index or nil,
          'copy_log_line',
          copy and copy.copy_log_line or nil,
          'why_imported_on_second_closure',
          report.object {
            'direct_live_dialogue_speaker_id_references',
            #direct,
            'non_dialogue_exact_references',
            #nonDialogue,
            'source_reference_candidates',
            #sourceExact[id],
            'causal_dependency_imports',
            #causal,
            'reason_class',
            class,
            'classification_rationale',
            rationale,
          },
          'surviving_info_references',
          direct,
          'non_dialogue_references',
          nonDialogue,
          'script_text_mentions',
          scripts[id],
          'placed_references',
          placed[id],
          'source_reference_candidates',
          sourceExact[id],
          'source_script_text_mentions',
          sourceScripts[id],
          'source_placed_references',
          sourcePlaced[id],
          'causal_dependency_imports',
          causal,
        }
      )
    end
  end

  local classNames = {}

  for name in classes do
    table.insert(classNames, name)
  end

  table.sort(classNames)
  local classPairs = {}

  for _, name in classNames do
    table.insert(classPairs, name)
    table.insert(classPairs, classes[name])
  end

  local byFile = report.dict()

  for source, ids in classA do
    local list = {}

    for id in ids do
      table.insert(list, id)
    end

    table.sort(list)
    byFile[source] = report.array(list)
  end

  local snapshotCount, finalCount = 0, 0

  for _ in before do
    snapshotCount += 1
  end

  for _ in final do
    finalCount += 1
  end

  local result = report.object {
    'version',
    1,
    'log',
    inputs.logPath,
    'standalone',
    inputs.finalPath,
    'snapshot_actor_count',
    snapshotCount,
    'final_actor_count',
    finalCount,
    'late_actor_count',
    #rows,
    'late_actor_class_counts',
    report.object(classPairs),
    'class_a_info_ids_by_source',
    byFile,
    'dialogue_liveness_audit',
    inputs.audit,
    'actors',
    rows,
  }

  report.write(paths.report, result)
  writeMarkdown(paths.markdown, result)

  if next(byFile) ~= nil then writeCleanup(paths.cleanup, byFile) end

  return result
end

return provenance
