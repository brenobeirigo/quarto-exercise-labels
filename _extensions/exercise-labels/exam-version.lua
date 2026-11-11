-- Exam versions: a new answer key from the same multiple-choice paper.
--
-- Render with `-M exam-version:B` (any short label) to move the correct answers
-- of the paper's questions to new letters. Without `exam-version`, or with
-- `false`, the paper renders as written. `A` keeps the written order but, like
-- any version, can print its label and its key.
--
-- A question is the block that holds one `.alpha-list`: its `.exercise-include`
-- or, in a paper without includes, the section under its heading. Everything
-- the filter changes stays inside that block, so one question never affects
-- another.
--
-- The `.alpha-list` holds four options (`A) ...` or `- ...`) and one `.correct`
-- marker. The options are reordered so the correct one lands on its new letter.
-- When options cite panels (@lst-, @fig-, @tbl-) and the four cited panels are
-- the blocks of one parent in the question, such as
-- `::: {#lst-x layout-ncol="2"}`, the panels are reordered too, so every letter
-- keeps exactly the panels it named before, in the same order: if A named
-- "(a) and (b)", the option at A still names "(a) and (b)". A letter the
-- question cannot reach this way is not used for it.
--
-- Explanations follow their options when they are written like the options:
--
--   ::: {.alpha-explanations}
--   A) Counts all 100 inner passes ...
--   B) ...
--   C) [Resets c2 at each outer pass ...]{.correct}
--   D) ...
--   :::
--
-- A bullet list in that block gets bold **A.** to **D.** labels. In a Solution
-- without the block, a list of four bullets labelled **A.** to **D.** follows
-- too; a first word that repeats each bullet's own letter ("**A.** A counts")
-- changes only when all four bullets start that way.
--
-- When in doubt, a question keeps its order and the render reports why. That
-- happens when anything else in the question names a letter A to D: in the
-- statement, a hint or the Solution, in plain text, bold, headings, tables or
-- definition lists. Letters that are clearly data do not count: after or
-- before a word such as "column", "grade" or "band", in a list of single
-- values such as "A, D, 1, C", or the article "A" before a word that is not a
-- verb. It also happens when an option refers to the others ("None of the
-- above"), when the panels cannot move with the options, and when the block
-- holds more than one answer list or explanation list.
--
-- The new key changes every question that can move, keeps the A to D totals of
-- the paper balanced and avoids the same letter on consecutive questions where
-- possible. It depends only on the label and the paper, so the student and the
-- answer renders always agree.
--
-- `exam-version-label: true` adds "Version B" to the subtitle; by default the
-- paper names no version. An answer build (`exercise-audience: answers`) ends
-- with the version's key, numbered by each answer list's place on the page.
--
-- Runs at pre-ast, before exercise-labels removes the `.correct` markers from
-- student builds.

local LETTERS = { "A", "B", "C", "D" }

local function fail(message)
  io.stderr:write("exam-version: " .. message .. "\n")
  os.exit(1)
end

local function warn(message)
  if quarto ~= nil and quarto.log ~= nil then
    quarto.log.warning("exam-version: " .. message)
  else
    io.stderr:write("WARNING exam-version: " .. message .. "\n")
  end
end

local function has_class(element, name)
  for _, value in ipairs(element.classes or {}) do
    if value == name then return true end
  end
  return false
end

local function set(list)
  local out = {}
  for _, value in ipairs(list) do out[value] = true end
  return out
end

-- A small seeded generator, so every platform draws the same sequence.
local function generator(label)
  local state = 2166136261
  for i = 1, #label do
    state = ((state ~ label:byte(i)) * 16777619) % 4294967296
  end
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return state % n + 1
  end
end

-- Every order of four items, as maps from old place to new place.
local PERMUTATIONS = {}
do
  local function build(prefix, rest)
    if #rest == 0 then
      PERMUTATIONS[#PERMUTATIONS + 1] = prefix
      return
    end
    for i = 1, #rest do
      local next_prefix = { table.unpack(prefix) }
      next_prefix[#next_prefix + 1] = rest[i]
      local next_rest = { table.unpack(rest) }
      table.remove(next_rest, i)
      build(next_prefix, next_rest)
    end
  end
  build({}, { 1, 2, 3, 4 })
end

local function rotation(step)
  local map = {}
  for i = 1, 4 do map[i] = (i - 1 + step) % 4 + 1 end
  return map
end

local function is_identity(map)
  for i = 1, 4 do
    if map[i] ~= i then return false end
  end
  return true
end

local function count_lists(block)
  local n = 0
  pandoc.walk_block(pandoc.Div({ block }), {
    Div = function(div) if has_class(div, "alpha-list") then n = n + 1 end end,
  })
  return n
end

------------------------------------------------------------------------------
-- Words and letters

local DATA_NOUNS = set({
  "column", "columns", "col", "cols", "cell", "cells", "row", "rows", "range", "ranges",
  "band", "bands", "grade", "grades", "letter", "letters", "mark", "marks", "score", "scores",
  "sheet", "sheets", "worksheet", "type", "types", "class", "classes", "category",
  "categories", "group", "groups", "team", "teams", "zone", "zones", "level", "levels",
  "block", "blocks", "gate", "gates", "plan", "plans", "size", "sizes", "vitamin",
  "building", "buildings", "room", "rooms", "wing", "floor", "sector", "unit", "units",
  "player", "players", "product", "products", "item", "items", "machine", "machines",
  "shop", "shops", "store", "stores", "site", "sites", "node", "nodes", "city", "cities",
  "point", "points", "route", "routes", "customer", "customers", "student", "students",
  "model", "models", "warehouse", "warehouses", "depot", "depots", "truck", "trucks",
  "location", "locations", "station", "stations", "line", "lines", "code", "codes",
})
local CONNECTORS = set({ "and", "or", "&", "to", "-", "--", "/", "through", "until" })
local VERBS = set({
  "is", "was", "has", "had", "does", "did", "can", "could", "will", "would", "should",
  "must", "may", "might", "gets", "got", "makes", "made", "keeps", "kept", "goes", "went",
})

local CODE = "\1code"
local CITE = "\1cite"

-- The words of some inlines, looking inside bold, italics, spans and links.
-- Code and maths stand as one placeholder word, a citation as another.
local function words_of(inlines)
  local out = {}
  local function add(list)
    for _, el in ipairs(list) do
      local t = el.t
      if t == "Str" then
        out[#out + 1] = el.text
      elseif t == "Code" or t == "Math" or t == "RawInline" then
        out[#out + 1] = CODE
      elseif t == "Cite" then
        out[#out + 1] = CITE
      elseif t == "Space" or t == "SoftBreak" or t == "LineBreak" or t == "Note" or t == "Image" then
        -- a separator, or content that is not part of the sentence
      elseif type(el.content) == "table" then
        add(el.content)
      end
    end
  end
  add(inlines)
  return out
end

local function bare(word)
  return (word:lower():gsub("^%p+", ""):gsub("%p+$", ""))
end

-- "B", "B.", "(B)", "B):", "B," name the letter B.
local function letter_word(word)
  return word:match("^%(?([A-D])%)?[%.,;:!?%)]*$")
end

local function verbish(word)
  local w = bare(word)
  if VERBS[w] then return true end
  return w:match("^%l+s$") ~= nil and not w:match("ss$") and not w:match("us$")
    and not w:match("is$")
end

local function single_value(word)
  return word:match("^%(?[%w]%)?[,;.]?$") ~= nil
end

-- True when the words name an option by letter, from word `first` on.
local function names_letter(words, first)
  local data = {}
  for i = first or 1, #words do
    local word = words[i]
    if letter_word(word) then
      local is_data = false
      local j = i - 1
      while j >= 1 and CONNECTORS[bare(words[j])] do j = j - 1 end
      local before = j >= 1 and words[j] or nil
      local after = words[i + 1]
      if before and (DATA_NOUNS[bare(before)] or data[j]) then is_data = true end
      if after and DATA_NOUNS[bare(after)] then is_data = true end
      -- A run of single values with commas, such as "A, D, 1, C".
      local from, to = i, i
      while from > 1 and single_value(words[from - 1]) do from = from - 1 end
      while to < #words and single_value(words[to + 1]) do to = to + 1 end
      if to - from >= 2 then
        for k = from, to do
          if words[k]:find(",", 1, true) then is_data = true end
        end
      end
      -- The article: "A temporary variable", "A `Sub` performs".
      if word == "A" and after and after ~= CITE and not letter_word(after) and not verbish(after) then
        is_data = true
      end
      if not is_data then return true end
      data[i] = true
    end
  end
  return false
end

------------------------------------------------------------------------------
-- Explanation lists

-- The letter of a bullet that starts with a bold label such as **A.**.
local function label_of(item)
  local first = item[1]
  if first == nil or (first.t ~= "Plain" and first.t ~= "Para") then return nil end
  local strong = first.content[1]
  if strong == nil or strong.t ~= "Strong" then return nil end
  return pandoc.utils.stringify(strong):match("^([A-D])%.$")
end

-- Four bullets labelled A. to D. in order.
local function labelled_list(list)
  if list.t ~= "BulletList" or #list.content ~= 4 then return false end
  for i, item in ipairs(list.content) do
    if label_of(item) ~= LETTERS[i] then return false end
  end
  return true
end

-- True when each of the four bullets starts with its own letter after the label.
local function own_letters(list)
  for i, item in ipairs(list.content) do
    local words = words_of(item[1].content)
    if letter_word(words[2] or "") ~= LETTERS[i] then return false end
  end
  return true
end

------------------------------------------------------------------------------
-- Finding letters in a question

local function table_blocks(tbl)
  local blocks = {}
  local function rows(list)
    for _, row in ipairs(list or {}) do
      for _, cell in ipairs(row.cells) do
        for _, block in ipairs(cell.contents) do blocks[#blocks + 1] = block end
      end
    end
  end
  rows(tbl.head and tbl.head.rows)
  for _, body in ipairs(tbl.bodies or {}) do
    rows(body.head)
    rows(body.body)
  end
  rows(tbl.foot and tbl.foot.rows)
  if tbl.caption and tbl.caption.long then
    for _, block in ipairs(tbl.caption.long) do blocks[#blocks + 1] = block end
  end
  return blocks
end

-- True when the blocks name an option by letter. Inside a Solution (a
-- `.callout-note`) tables and definition lists count too; elsewhere they hold
-- data. The options themselves are skipped.
local scan
scan = function(blocks, solution)
  for _, block in ipairs(blocks) do
    local t = block.t
    if t == "Para" or t == "Plain" or t == "Header" then
      if names_letter(words_of(block.content)) then return true end
    elseif t == "Div" then
      if has_class(block, "alpha-list") then
        -- the options; read_question checks them
      elseif has_class(block, "alpha-explanations") then
        for _, inner in ipairs(block.content) do
          if inner.t == "BulletList" or inner.t == "OrderedList" then
            for _, item in ipairs(inner.content) do
              local first = item[1]
              if first and (first.t == "Para" or first.t == "Plain") then
                local words = words_of(first.content)
                local start = (words[1] and words[1]:match("^[A-D]%.$")) and 2 or 1
                if names_letter(words, start) then return true end
                if scan({ table.unpack(item, 2) }, true) then return true end
              elseif scan(item, true) then
                return true
              end
            end
          elseif scan({ inner }, true) then
            return true
          end
        end
      elseif scan(block.content, solution or has_class(block, "callout-note")) then
        return true
      end
    elseif t == "BulletList" and labelled_list(block) then
      local skip = own_letters(block) and 2 or 1
      for _, item in ipairs(block.content) do
        if names_letter(words_of(item[1].content), 1 + skip) then return true end
        if scan({ table.unpack(item, 2) }, solution) then return true end
      end
    elseif t == "BulletList" or t == "OrderedList" then
      -- "* A) No trimming ...": a lettered list in a Solution names options.
      if t == "OrderedList" and solution and block.listAttributes.style == "UpperAlpha" then
        return true
      end
      for _, item in ipairs(block.content) do
        if scan(item, solution) then return true end
      end
    elseif t == "BlockQuote" then
      if scan(block.content, solution) then return true end
    elseif t == "Figure" then
      if scan(block.content, solution) then return true end
      if block.caption and block.caption.long and scan(block.caption.long, solution) then return true end
    elseif t == "Table" and solution then
      if scan(table_blocks(block), solution) then return true end
    elseif t == "DefinitionList" and solution then
      for _, entry in ipairs(block.content) do
        if names_letter(words_of(entry[1])) then return true end
        for _, definition in ipairs(entry[2]) do
          if scan(definition, solution) then return true end
        end
      end
    end
  end
  return false
end

------------------------------------------------------------------------------
-- Questions

local RELATIONAL = { "of the above", "the above", "of these", "of the others", "other options",
  "other alternatives", "previous option", "options above" }

-- The options of an .alpha-list, or nil and a reason.
local function read_question(div)
  local list = nil
  for _, block in ipairs(div.content) do
    if block.t == "OrderedList" or block.t == "BulletList" then list = block; break end
  end
  if list == nil or #list.content ~= 4 then
    return nil, "it needs four options and one .correct marker"
  end
  local correct, cites, relational = {}, {}, false
  for i, item in ipairs(list.content) do
    cites[i] = {}
    pandoc.walk_block(pandoc.Div(item), {
      Span = function(span) if has_class(span, "correct") then correct[#correct + 1] = i end end,
      Div = function(inner) if has_class(inner, "correct") then correct[#correct + 1] = i end end,
      Cite = function(cite)
        for _, citation in ipairs(cite.citations) do
          if citation.id:match("^lst%-") or citation.id:match("^fig%-") or citation.id:match("^tbl%-") then
            cites[i][#cites[i] + 1] = citation.id
          end
        end
      end,
    })
    local text = " " .. pandoc.utils.stringify(pandoc.Div(item)):lower() .. " "
    for _, phrase in ipairs(RELATIONAL) do
      if text:find(phrase, 1, true) then relational = true end
    end
    if text:match("[%s(]both [a-d] and [a-d][%s.,)]") or text:match("[%s(][a-d] and [a-d][%s.,)]")
        or text:match("[%s(]neither [a-d] nor [a-d][%s.,)]") or text:match("[%s(][a-d] or [a-d][%s.,)]") then
      relational = true
    end
  end
  if #correct ~= 1 then return nil, "it needs four options and one .correct marker" end
  local panel = false
  for i = 1, 4 do
    if #cites[i] > 0 then panel = true end
  end
  return { correct = correct[1], cites = cites, panel = panel, relational = relational }
end

-- A block that can be a panel: an identified Div, Figure or Table.
local function panel_id(block)
  if block.t == "Div" or block.t == "Figure" or block.t == "Table" then
    local id = block.identifier or ""
    if id ~= "" then return id end
  end
  return nil
end

local function panel_children(div)
  local ids = {}
  for _, block in ipairs(div.content) do
    local id = panel_id(block)
    if id then ids[#ids + 1] = id end
  end
  return ids
end

local function id_key(ids)
  local sorted = { table.unpack(ids) }
  table.sort(sorted)
  return table.concat(sorted, "|")
end

local function same_slots(a, b)
  if #a ~= #b then return false end
  local seen = {}
  for _, s in ipairs(a) do seen[s] = (seen[s] or 0) + 1 end
  for _, s in ipairs(b) do
    if not seen[s] or seen[s] == 0 then return false end
    seen[s] = seen[s] - 1
  end
  return true
end

-- The moves of a panel question: for each new letter of the correct option,
-- an option order and a panel order under which every letter keeps its slots.
local function panel_moves(question)
  local moves = {}
  local slots = question.slots
  for target = 1, 4 do
    local candidates = { rotation(target - question.correct) }
    for _, perm in ipairs(PERMUTATIONS) do
      if perm[question.correct] == target then candidates[#candidates + 1] = perm end
    end
    for _, sigma in ipairs(candidates) do
      if sigma[question.correct] == target and not moves[target] then
        for _, pi in ipairs(PERMUTATIONS) do
          local ok = true
          for i = 1, 4 do
            local moved = {}
            for k, s in ipairs(slots[i]) do moved[k] = pi[s] end
            if not same_slots(moved, slots[sigma[i]]) then ok = false; break end
          end
          if ok then
            moves[target] = { sigma = sigma, pi = pi }
            break
          end
        end
      end
    end
  end
  return moves
end

-- Read one question block: its answer list, panels and explanations.
local function analyse(blocks, position, count, panel_use)
  local record = { position = position }
  if count ~= 1 then
    record.reason = "its question block holds " .. count .. " answer lists"
    return record
  end
  local alpha = nil
  pandoc.walk_block(pandoc.Div(blocks), {
    Div = function(div) if has_class(div, "alpha-list") then alpha = div end end,
  })
  local question, why = read_question(alpha)
  if question == nil then
    record.reason = why
    return record
  end
  record.correct = question.correct
  record.moves = { [question.correct] = { sigma = rotation(0), pi = rotation(0) } }
  for i = 1, 4 do
    for _, id in ipairs(question.cites[i]) do
      panel_use[id] = panel_use[id] or {}
      panel_use[id][position] = true
    end
  end
  if question.relational then
    record.reason = "an option refers to the other options"
    return record
  end
  if scan(blocks, false) then
    record.reason = "it names options by letter"
    return record
  end
  -- Explanations: at most one enclosed list of four, or one labelled list in
  -- a Solution.
  local enclosed, labelled, bad = 0, 0, false
  pandoc.walk_block(pandoc.Div(blocks), {
    Div = function(div)
      if has_class(div, "alpha-explanations") then
        enclosed = enclosed + 1
        local lists = 0
        for _, inner in ipairs(div.content) do
          if inner.t == "BulletList" or inner.t == "OrderedList" then
            lists = lists + 1
            if #inner.content ~= 4 then bad = true end
          end
        end
        if lists ~= 1 then bad = true end
      elseif has_class(div, "callout-note") then
        pandoc.walk_block(div, {
          BulletList = function(list) if labelled_list(list) then labelled = labelled + 1 end end,
        })
      end
    end,
  })
  if enclosed > 1 or bad or (enclosed == 0 and labelled > 1) then
    record.reason = "its explanations are not one list of four"
    return record
  end
  record.labelled = enclosed == 0 and labelled == 1
  if not question.panel then
    for target = 1, 4 do
      record.moves[target] = { sigma = rotation(target - question.correct) }
    end
    return record
  end
  -- Panels: the four cited panels must be the blocks of one parent.
  local ids, seen, every = {}, {}, true
  for i = 1, 4 do
    if #question.cites[i] == 0 then every = false end
    for _, id in ipairs(question.cites[i]) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  local children = nil
  if every and #ids == 4 then
    pandoc.walk_block(pandoc.Div(blocks), {
      Div = function(div)
        local found = panel_children(div)
        if #found == 4 and id_key(found) == id_key(ids) then children = found end
      end,
    })
  end
  if children == nil then
    record.reason = "its options point at panels it cannot move together"
    return record
  end
  local slot_of = {}
  for s, id in ipairs(children) do slot_of[id] = s end
  local slots = {}
  for i = 1, 4 do
    slots[i] = {}
    for k, id in ipairs(question.cites[i]) do slots[i][k] = slot_of[id] end
  end
  record.children = children
  record.slots = slots
  record.parent_key = id_key(children)
  record.moves = panel_moves({ correct = question.correct, slots = slots })
  local reachable = 0
  for _ in pairs(record.moves) do reachable = reachable + 1 end
  if reachable == 1 then record.reason = "its panels cannot move with its options" end
  return record
end

------------------------------------------------------------------------------
-- The new key

local function choose_key(records, label)
  local draw = generator(label)
  local n = #records
  local low, high = n // 4, (n + 3) // 4
  local allowed = {}
  for i, record in ipairs(records) do
    allowed[i] = {}
    for target = 1, 4 do
      if record.moves[target] then allowed[i][#allowed[i] + 1] = target end
    end
  end
  local function score(key)
    local count = { 0, 0, 0, 0 }
    local unchanged, repeats, imbalance = 0, 0, 0
    for i, record in ipairs(records) do
      count[key[i]] = count[key[i]] + 1
      if #allowed[i] > 1 and key[i] == record.correct then unchanged = unchanged + 1 end
      if i > 1 and key[i] == key[i - 1] then repeats = repeats + 1 end
    end
    for letter = 1, 4 do
      imbalance = imbalance + math.max(0, count[letter] - high) + math.max(0, low - count[letter])
    end
    return imbalance * 10000 + unchanged * 100 + repeats
  end
  local best, best_score = nil, nil
  for _ = 1, 30 do
    local key = {}
    for i, record in ipairs(records) do
      local options = {}
      for _, target in ipairs(allowed[i]) do
        if target ~= record.correct then options[#options + 1] = target end
      end
      if #options == 0 then options = allowed[i] end
      key[i] = options[draw(#options)]
    end
    local current = score(key)
    local improved = true
    while improved do
      improved = false
      for i = 1, n do
        for _, target in ipairs(allowed[i]) do
          if target ~= key[i] then
            local old = key[i]
            key[i] = target
            local s = score(key)
            if s < current then current, improved = s, true else key[i] = old end
          end
        end
      end
      for i = 1, n do
        for j = i + 1, n do
          if key[i] ~= key[j] and records[i].moves[key[j]] and records[j].moves[key[i]] then
            key[i], key[j] = key[j], key[i]
            local s = score(key)
            if s < current then current, improved = s, true else key[i], key[j] = key[j], key[i] end
          end
        end
      end
    end
    if best_score == nil or current < best_score then
      best, best_score = { table.unpack(key) }, current
    end
  end
  return best
end

------------------------------------------------------------------------------
-- Moving one question

local function reorder_list(list, sigma, fix)
  local items = {}
  for i, item in ipairs(list.content) do
    items[sigma[i]] = fix and fix(i, item) or item
  end
  if list.t == "OrderedList" then return pandoc.OrderedList(items, list.listAttributes) end
  return pandoc.BulletList(items)
end

local function transform(blocks, record, move)
  local sigma, pi = move.sigma, move.pi
  -- After the move, slot p shows the panel that was in slot s with pi[s] = p.
  local now_at = {}
  if record.children then
    for s, id in ipairs(record.children) do now_at[pi[s]] = id end
  end
  -- An option names its panels in the slot order its new letter used before.
  local function fix_cites(i, item)
    if not record.children then return item end
    local wanted = {}
    for k, s in ipairs(record.slots[sigma[i]]) do wanted[k] = now_at[s] end
    local by_id, count = {}, 0
    pandoc.walk_block(pandoc.Div(item), {
      Cite = function(cite)
        count = count + 1
        by_id[cite.citations[1].id] = cite
      end,
    })
    if count ~= #wanted then return item end
    local k = 0
    return pandoc.walk_block(pandoc.Div(item), {
      Cite = function()
        k = k + 1
        return by_id[wanted[k]]
      end,
    }).content
  end
  local function relabel(list)
    local own = own_letters(list)
    local items = {}
    for i, item in ipairs(list.content) do
      local new = LETTERS[sigma[i]]
      local inlines = item[1].content
      inlines[1] = pandoc.Strong({ pandoc.Str(new .. ".") })
      if own and inlines[2] and inlines[2].t == "Space" and inlines[3] and inlines[3].t == "Str" then
        inlines[3] = pandoc.Str((inlines[3].text:gsub("^(%(?)[A-D]", "%1" .. new, 1)))
      end
      items[sigma[i]] = item
    end
    return pandoc.BulletList(items)
  end
  return pandoc.walk_block(pandoc.Div(blocks), {
    traverse = "topdown",
    Div = function(div)
      if has_class(div, "alpha-list") or has_class(div, "alpha-explanations") then
        local fix = has_class(div, "alpha-list") and fix_cites or nil
        local content = pandoc.Blocks(div.content)
        for k, block in ipairs(content) do
          if block.t == "OrderedList" or block.t == "BulletList" then
            content[k] = reorder_list(block, sigma, fix)
            break
          end
        end
        div.content = content
        return div, false
      end
      if record.children then
        local found = panel_children(div)
        if #found == 4 and id_key(found) == record.parent_key then
          local by_id = {}
          for _, block in ipairs(div.content) do
            local id = panel_id(block)
            if id then by_id[id] = block end
          end
          local content, slot = pandoc.Blocks({}), 0
          for _, block in ipairs(div.content) do
            if panel_id(block) then
              slot = slot + 1
              content:insert(by_id[now_at[slot]])
            else
              content:insert(block)
            end
          end
          div.content = content
          return div
        end
      end
      if record.labelled and has_class(div, "callout-note") then
        return pandoc.walk_block(div, {
          BulletList = function(list) if labelled_list(list) then return relabel(list) end end,
        }), false
      end
    end,
  }).content
end

------------------------------------------------------------------------------
-- Question blocks in page order

local function has_include(blocks)
  local found = false
  pandoc.walk_block(pandoc.Div(blocks), {
    Div = function(div) if has_class(div, "exercise-include") then found = true end end,
  })
  return found
end

-- Calls visit(blocks, first_position, count) for every question block in page
-- order and returns the blocks with each replaced by what visit returns.
-- loose(position) is called for each answer list outside any question block.
local function each_block(doc_blocks, visit, loose)
  local seen = 0
  if has_include(doc_blocks) then
    local function walk(blocks)
      local out = pandoc.Blocks({})
      for _, block in ipairs(blocks) do
        if block.t == "Div" and has_class(block, "exercise-include") then
          local n = count_lists(block)
          if n > 0 then
            block = pandoc.Div(visit(block.content, seen + 1, n), block.attr)
          end
          seen = seen + n
        elseif block.t == "Div" and not has_class(block, "alpha-list") and has_include(block.content) then
          block.content = walk(block.content)
        else
          local n = count_lists(block)
          for k = 1, n do loose(seen + k, "it is not inside an .exercise-include") end
          seen = seen + n
        end
        out:insert(block)
      end
      return out
    end
    return walk(doc_blocks)
  end
  -- A paper without includes: each question is the widest section under a
  -- heading that holds exactly one answer list.
  local blocks = { table.unpack(doc_blocks) }
  local counts, total = {}, 0
  for b, block in ipairs(blocks) do
    counts[b] = count_lists(block)
    total = total + counts[b]
  end
  local function section_end(h)
    local level = blocks[h].level
    for k = h + 1, #blocks do
      if blocks[k].t == "Header" and blocks[k].level <= level then return k - 1 end
    end
    return #blocks
  end
  local function lists_in(from, to)
    local n = 0
    for k = from, to do n = n + counts[k] end
    return n
  end
  local ranges = {}
  for b = 1, #blocks do
    if counts[b] == 1 then
      local range = nil
      for h = b - 1, 1, -1 do
        if blocks[h].t == "Header" then
          local stop = section_end(h)
          if stop >= b then
            if lists_in(h, stop) == 1 then range = { h, stop } else break end
          end
        end
      end
      if range == nil and total == 1 then range = { 1, #blocks } end
      if range then ranges[#ranges + 1] = { range[1], range[2], b } end
    end
  end
  local out = pandoc.Blocks({})
  local r, b = 1, 1
  while b <= #blocks do
    local range = ranges[r]
    if range and b == range[1] then
      local slice = { table.unpack(blocks, range[1], range[2]) }
      local position = seen + lists_in(range[1], range[3] - 1) + 1
      for _, block in ipairs(visit(slice, position, 1)) do out:insert(block) end
      seen = seen + lists_in(range[1], range[2])
      b = range[2] + 1
      r = r + 1
    else
      -- No section of its own: say how many answer lists share its section.
      local reason = "it has no section of its own under a heading"
      for h = b - 1, 1, -1 do
        if blocks[h].t == "Header" then
          local shared = lists_in(h, section_end(h))
          if shared > 1 then reason = "its section holds " .. shared .. " answer lists" end
          break
        end
      end
      for k = 1, counts[b] do loose(seen + k, reason) end
      seen = seen + counts[b]
      out:insert(blocks[b])
      b = b + 1
    end
  end
  return out
end

------------------------------------------------------------------------------
-- Labels and the key

-- Bold **A.** to **D.** labels on enclosed bullet explanations; a lettered
-- list is labelled by Pandoc, and labels already there are put right.
local function label_explanations(doc)
  return doc:walk({
    Div = function(div)
      if not has_class(div, "alpha-explanations") then return nil end
      local content = pandoc.Blocks(div.content)
      for k, block in ipairs(content) do
        if block.t == "OrderedList" then break end
        if block.t == "BulletList" then
          local items = {}
          for i, item in ipairs(block.content) do
            local first = item[1]
            if first and (first.t == "Para" or first.t == "Plain") then
              local label = pandoc.Strong({ pandoc.Str((LETTERS[i] or "?") .. ".") })
              if label_of(item) then
                first.content[1] = label
              else
                local inlines = pandoc.Inlines({ label, pandoc.Space() })
                inlines:extend(first.content)
                first.content = inlines
              end
            end
            items[i] = item
          end
          content[k] = pandoc.BulletList(items)
          break
        end
      end
      div.content = content
      return div
    end,
  })
end

local function audience(meta)
  local value = meta["exercise-audience"]
  return value and pandoc.utils.stringify(value):lower() or ""
end

local function truthy(value)
  if value == nil or value == false then return false end
  if value == true then return true end
  local text = pandoc.utils.stringify(value):lower()
  return text == "true" or text == "yes"
end

function Pandoc(doc)
  local value = doc.meta["exam-version"]
  local label = (value ~= nil and value ~= false and value ~= true) and pandoc.utils.stringify(value) or ""
  if value == nil or value == false or ({ [""] = true, ["false"] = true, ["no"] = true,
      ["off"] = true })[label:lower()] then
    return label_explanations(doc)
  end
  if value == true or not label:match("^[%w%-]+$") then
    fail("exam-version must be a short label such as B, got " .. label)
  end

  -- First pass: read every question block.
  local records, panel_use = {}, {}
  local loose_positions = {}
  each_block(doc.blocks, function(blocks, position, count)
    records[#records + 1] = analyse(blocks, position, count, panel_use)
    return blocks
  end, function(position, reason)
    loose_positions[#loose_positions + 1] = { position, reason }
  end)
  for _, entry in ipairs(loose_positions) do
    warn("question " .. entry[1] .. " keeps its order: " .. entry[2])
  end

  -- Panels that another question also cites stay where they are.
  for _, record in ipairs(records) do
    if record.children then
      for _, id in ipairs(record.children) do
        for other in pairs(panel_use[id] or {}) do
          if other ~= record.position and not record.shared then
            record.moves = { [record.correct] = record.moves[record.correct] }
            record.reason = "another question uses the same panels"
            record.shared = true
          end
        end
      end
    end
  end
  local keyed = {}
  for _, record in ipairs(records) do
    if record.reason then warn("question " .. record.position .. " keeps its order: " .. record.reason) end
    if record.correct then keyed[#keyed + 1] = record end
  end
  if #keyed == 0 then
    warn("no question with four options and one .correct marker was found")
    return label_explanations(doc)
  end

  local key = {}
  for i, record in ipairs(keyed) do key[i] = record.correct end
  if label:upper() ~= "A" then key = choose_key(keyed, label) end
  local chosen = {}
  for i, record in ipairs(keyed) do chosen[record] = record.moves[key[i]] end

  -- Second pass: move each question inside its own block.
  local index = 0
  doc.blocks = each_block(doc.blocks, function(blocks)
    index = index + 1
    local record = records[index]
    local move = record.correct and chosen[record] or nil
    if move == nil or is_identity(move.sigma) then return blocks end
    return transform(blocks, record, move)
  end, function() end)

  -- The version label on the cover, only when asked for, and the key at the end
  -- of an answer build.
  if truthy(doc.meta["exam-version-label"]) then
    local tag = pandoc.Inlines({ pandoc.Str("Version"), pandoc.Space(), pandoc.Str(label) })
    if doc.meta.subtitle then
      local subtitle = pandoc.Inlines(doc.meta.subtitle)
      subtitle:insert(pandoc.LineBreak())
      subtitle:extend(tag)
      doc.meta.subtitle = subtitle
    else
      doc.meta.subtitle = tag
    end
  end
  if audience(doc.meta) == "answers" then
    local entries = pandoc.Inlines({ pandoc.Strong({ pandoc.Str("Key,"), pandoc.Space(),
      pandoc.Str("version"), pandoc.Space(), pandoc.Str(label .. ":") }) })
    for i, letter in ipairs(key) do
      entries:insert(pandoc.Space())
      entries:insert(pandoc.Str(keyed[i].position .. "\u{00A0}" .. LETTERS[letter]
        .. (i < #key and "," or "")))
    end
    doc.blocks:insert(pandoc.Div({ pandoc.Para(entries) },
      pandoc.Attr("exam-version-key", { "exam-version-key" })))
  end
  return label_explanations(doc)
end
