--!strict
--!native
-- JSON reports in the shape build_starwind.py writes them: `json.dumps(value, indent=2)`, keys in
-- the order they were set, non-ASCII escaped. Luau tables don't keep key order, so a report's
-- objects are built with `object`, which records it; arrays with `array`, so an empty one is `[]`.

export type Json = boolean | number | string | JessNull | { [string | number]: Json }

local report = {}

local order: { [{ [string | number]: Json }]: { string } } = {}
setmetatable(order, { __mode = 'k' })
local arrays: { [{ [string | number]: Json }]: boolean } = {}
setmetatable(arrays, { __mode = 'k' })

-- An object whose keys come out in the order given: `object { 'a', 1, 'b', 2 }`. A nil value
-- leaves its key out of the object but not out of the order, as None would be `null`.
function report.object(pairs: { Json? }): { [string]: Json }
  local result: { [string]: Json } = {}
  local keys = {}
  -- A nil value leaves a hole `#` may stop at, so count to the last key instead.
  local last = 0

  for index in pairs do
    if type(index) == 'number' and index > last then last = index end
  end

  for index = 1, last, 2 do
    local key = pairs[index] :: string
    table.insert(keys, key)
    result[key] = pairs[index + 1]
  end

  order[result] = keys
  return result
end

-- Sets `key` on an object made by `object`, appending it to the order when it's new.
function report.set(object: { [string]: Json }, key: string, value: Json?)
  local keys = order[object]

  if keys and object[key] == nil and not table.find(keys, key) then table.insert(keys, key) end

  object[key] = value :: Json
end

function report.array(items: { Json }?): { Json }
  local result = items or {}
  arrays[result :: { [string | number]: Json }] = true
  return result
end

local dicts: { [{ [string | number]: Json }]: boolean } = {}
setmetatable(dicts, { __mode = 'k' })

-- An object whose keys come out sorted, `{}` when it has none.
function report.dict(items: { [string]: Json }?): { [string]: Json }
  local result = items or {}
  dicts[result :: { [string | number]: Json }] = true
  return result
end

local function escape(text: string): string
  -- Most strings are plain ASCII with nothing to escape.
  if not string.find(text, '[%c"\\\128-\255]') then return text end

  local parts = {}

  for _, code in utf8.codes(text) do
    if code == 34 then
      table.insert(parts, '\\"')
    elseif code == 92 then
      table.insert(parts, '\\\\')
    elseif code == 10 then
      table.insert(parts, '\\n')
    elseif code == 13 then
      table.insert(parts, '\\r')
    elseif code == 9 then
      table.insert(parts, '\\t')
    elseif code < 32 or code > 126 then
      if code > 0xFFFF then
        local value = code - 0x10000
        table.insert(
          parts,
          string.format(
            '\\u%04x\\u%04x',
            0xD800 + bit32.rshift(value, 10),
            0xDC00 + bit32.band(value, 0x3FF)
          )
        )
      else
        table.insert(parts, string.format('\\u%04x', code))
      end
    else
      table.insert(parts, utf8.char(code))
    end
  end

  return table.concat(parts)
end

local function number(value: number): string
  if value ~= value then
    return 'NaN'
  elseif value == math.huge then
    return 'Infinity'
  elseif value == -math.huge then
    return '-Infinity'
  elseif value == math.floor(value) and math.abs(value) < 2 ^ 53 then
    return string.format('%d', value)
  end

  return tostring(value)
end

-- What a level of indentation is written with: what its items start with, and what closes it.
type Margin = { inner: string, bracket: string, brace: string }

-- The margins of every depth written so far, by the indentation: a report is a few levels deep.
local margins: { [string]: Margin } = {}

local function marginOf(indent: string): Margin
  local known = margins[indent]

  if known then return known end

  local made = { inner = indent .. '  ', bracket = indent .. ']', brace = indent .. '}' }
  margins[indent] = made
  return made
end

-- What one `encode` is writing: the pieces of its text, each string it has spelled so far in its
-- quotes, and each key it has opened a line with at each depth. A report says the same field
-- names, types, and ids thousands of times over, and each is spelled once.
type Writing = {
  parts: { string },
  quoted: { [string]: string },
  opened: { [string]: { [string]: string } },
}

local function quoted(writing: Writing, text: string): string
  local known = writing.quoted[text]

  if known then return known end

  local made = '"' .. escape(text) .. '"'
  writing.quoted[text] = made
  return made
end

local function encode(value: Json?, indent: string, writing: Writing)
  local parts = writing.parts
  local kind = type(value)

  if value == nil or value == jess.null then
    table.insert(parts, 'null')
  elseif kind == 'boolean' then
    table.insert(parts, if value then 'true' else 'false')
  elseif kind == 'number' then
    table.insert(parts, number(value :: number))
  elseif kind == 'string' then
    table.insert(parts, quoted(writing, value :: string))
  else
    local container = value :: { [string | number]: Json }
    local margin = marginOf(indent)
    local inner = margin.inner
    local keys = order[container]

    if
      not keys
      and not dicts[container]
      and (arrays[container] or #container > 0 or next(container) == nil)
    then
      if #container == 0 then
        table.insert(parts, '[]')
        return
      end

      table.insert(parts, '[\n')

      for index, item in container :: { Json } do
        table.insert(parts, inner)
        encode(item, inner, writing)
        table.insert(parts, if index < #container then ',\n' else '\n')
      end

      table.insert(parts, margin.bracket)
      return
    end

    if not keys then
      local sorted = {}

      for key in container do
        table.insert(sorted, tostring(key))
      end

      table.sort(sorted)
      keys = sorted
    end

    if #(keys :: { string }) == 0 then
      table.insert(parts, '{}')
      return
    end

    table.insert(parts, '{\n')

    local opened = writing.opened[inner]

    if not opened then
      opened = {}
      writing.opened[inner] = opened
    end

    for index, key in keys :: { string } do
      local opening = opened[key]

      if not opening then
        opening = inner .. quoted(writing, key) .. ': '
        opened[key] = opening
      end

      table.insert(parts, opening)
      encode(container[key], inner, writing)
      table.insert(parts, if index < #(keys :: { string }) then ',\n' else '\n')
    end

    table.insert(parts, margin.brace)
  end
end

function report.encode(value: Json): string
  local writing: Writing = { parts = {}, quoted = {}, opened = {} }
  encode(value, '', writing)
  return table.concat(writing.parts)
end

-- Writes `value` to `path` as Python's report writers do: indented, with a final newline.
function report.write(path: string, value: Json, finalNewline: boolean?)
  local parent = jess.fs.parent(path)

  if parent and parent ~= '' and not jess.fs.isDir(parent) then jess.fs.createDir(parent) end

  jess.fs.write(
    path,
    report.encode(value) .. (if finalNewline == false then '' else '\n'),
    { backup = false }
  )
end

-- Each field name `snakeKey` has spelled, by the name: a record's fields are named once for
-- every record, and there are few names.
local snakeKeys: { [string]: string } = {}

-- A record's field name as tes3conv spells it: `speakerId` is `speaker_id`.
function report.snakeKey(key: string): string
  local known = snakeKeys[key]

  if known then return known end

  local spelled = string.gsub(
    key,
    '(%u)',
    function(letter: string) return '_' .. string.lower(letter) end
  )
  snakeKeys[key] = spelled
  return spelled
end

-- A record as a report shows it: tes3conv's snake_case field names.
function report.snake(value: Json): Json
  if type(value) ~= 'table' then return value end

  local container = value :: { [string | number]: Json }

  -- An empty record table is almost always an empty list (`filters`, `spells`).
  if #container > 0 or next(container) == nil then
    local items = {}

    for index, item in container :: { Json } do
      items[index] = report.snake(item)
    end

    return report.array(items)
  end

  local result: { [string]: Json } = {}

  for key, item in container do
    result[report.snakeKey(tostring(key))] = report.snake(item)
  end

  return report.dict(result)
end

return report
