-- Exam versions: a new answer key from the same multiple-choice paper.
--
-- Render with `-M exam-version:B` (any label) to move the correct answers of
-- the paper's plain-text questions to new letters. Without `exam-version`, or
-- with `A`, the paper stays as written.
--
-- A question is an `.alpha-list` whose list (`A) ...` or `- ...`) has four
-- options and one `.correct` marker. Its options rotate together, so the
-- correct option lands on its new letter and the A to D labels stay in order.
-- When the options cite
-- panels (@lst-, @fig-, @tbl-) and the four cited panels are the blocks of one
-- parent, such as `::: {#lst-x layout-ncol="2"}`, the panels rotate by the same
-- step, so every option keeps its panels: "(a)" stays with A, and an option
-- citing "(a) and (b)" at A still cites "(a) and (b)". Other panel questions,
-- such as options that point at lines of one listing, keep their order.
--
-- Explanations enclosed like the options follow them exactly:
--
--   ::: {.alpha-explanations}
--   - Counts all 100 inner passes ...
--   - ...
--   :::
--
-- The list holds one explanation per option, in option order. The filter writes
-- the bold **A.** to **D.** labels in every build, with or without a version.
--
-- The new letters change every movable answer, keep the A to D totals of the
-- paper balanced and avoid the same letter on consecutive questions where
-- possible. The choice depends only on the label and the paper, so the student
-- and the answer renders get the same order.
--
-- Explanation bullets that start with a bold letter, `- **A.** ...`, follow
-- their options: they are relabelled, reordered, and a first word that repeats
-- the bullet's own letter ("**A.** A counts ...") changes with it. A question
-- whose Solution names options by letter in any other way, such as "Option A",
-- "**Answer:** A", a line starting with "B)" or "C ..." or "the same mistake
-- as A", keeps its order, so its explanation stays true; the render reports it.
--
-- `exam-version-label: true` adds "Version B" to the subtitle; by default the
-- paper names no version. An answer build (`exercise-audience: answers`) ends
-- with the version's key.
--
-- Runs at pre-ast, before exercise-labels removes the `.correct` markers from
-- student builds.

local LETTERS = { "A", "B", "C", "D" }
local INDEX = { A = 1, B = 2, C = 3, D = 4 }

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

-- Options and the correct position of an .alpha-list, or nil when it is not a
-- four-option question with one correct option.
local function read_question(div)
  local list = nil
  for _, block in ipairs(div.content) do
    if block.t == "OrderedList" or block.t == "BulletList" then list = block; break end
  end
  if list == nil or #list.content ~= 4 then return nil end
  local correct, cites, panel = {}, {}, false
  for i, item in ipairs(list.content) do
    cites[i] = {}
    pandoc.walk_block(pandoc.Div(item), {
      Span = function(span) if has_class(span, "correct") then correct[#correct + 1] = i end end,
      Div = function(inner) if has_class(inner, "correct") then correct[#correct + 1] = i end end,
      Cite = function(cite)
        for _, citation in ipairs(cite.citations) do
          if citation.id:match("^lst%-") or citation.id:match("^fig%-")
              or citation.id:match("^tbl%-") then
            panel = true
            cites[i][#cites[i] + 1] = citation.id
          end
        end
      end,
    })
  end
  if #correct ~= 1 then return nil end
  return { list = list, correct = correct[1], movable = not panel, panel = panel, cites = cites }
end

-- A block that can be a panel: an identified Div, Figure or Table.
local function panel_id(block)
  if block.t == "Div" or block.t == "Figure" or block.t == "Table" then
    local id = block.identifier or ""
    if id ~= "" then return id end
  end
  return nil
end

-- The panels directly inside a block, in order.
local function panel_children(div)
  local ids = {}
  for _, block in ipairs(div.content) do
    local id = panel_id(block)
    if id then ids[#ids + 1] = id end
  end
  return ids
end

local function id_set(ids)
  local sorted = {}
  for i, id in ipairs(ids) do sorted[i] = id end
  table.sort(sorted)
  return table.concat(sorted, "|")
end

local function letter_token(inline)
  return inline ~= nil and inline.t == "Str" and inline.text:match("^([A-D])%p*$") or nil
end

local REFERRING = { option = true, options = true, alternative = true, choice = true,
  as = true, than = true, like = true, unlike = true, from = true }

-- "explained in C", "the error in B": "in" marks an option only after these.
local BEFORE_IN = { explained = true, described = true, shown = true, discussed = true,
  error = true, errors = true, mistake = true, mistakes = true }

-- True when a Solution names an option by letter in a way the bullets cannot
-- carry along: "Option A", "**Answer:** A", a line starting with "B)" or "C",
-- or "as A". Data such as "the C band", "A, D, 1, C" or "in column B" does not
-- count ("in" names cells too often to mark an option), and an
-- opening article "A" ("A temporary variable") is read as a word.
local function names_letters(callout)
  local found = false
  -- own: the letter of the option this text explains, when known.
  local function scan(inlines, own)
    local start = 1
    if inlines[1] and inlines[1].t == "Strong" then
      own = pandoc.utils.stringify(inlines[1]):match("^([A-D])%.$") or own
      if own then start = 3 end
    end
    if own then
      if letter_token(inlines[start]) == own then start = start + 2 end
    else
      local first = inlines[1]
      if first and first.t == "Str" and (first.text:match("^[A-D][.)]$")
          or first.text:match("^[B-D]%p*$")) then found = true end
    end
    for k = start, #inlines do
      if letter_token(inlines[k]) and k > 2 and inlines[k - 1].t == "Space" then
        local before = inlines[k - 2]
        if before.t == "Str" and REFERRING[before.text:lower()] then found = true end
        if before.t == "Str" and before.text:lower() == "in" and k > 4
            and inlines[k - 4].t == "Str" and BEFORE_IN[inlines[k - 4].text:lower()] then
          found = true
        end
        if before.t == "Strong" and pandoc.utils.stringify(before):match("^Answer") then found = true end
      end
    end
  end
  local visit
  local function visit_item(item, own)
    for n, block in ipairs(item) do
      if n == 1 and (block.t == "Para" or block.t == "Plain") then
        scan(block.content, own)
      else
        visit({ block })
      end
    end
  end
  visit = function(blocks)
    for _, block in ipairs(blocks) do
      if block.t == "Para" or block.t == "Plain" then
        scan(block.content, nil)
      elseif block.t == "Div" and has_class(block, "alpha-explanations") then
        for _, inner in ipairs(block.content) do
          if inner.t == "BulletList" or inner.t == "OrderedList" then
            for i, item in ipairs(inner.content) do visit_item(item, LETTERS[i]) end
          end
        end
      elseif block.t == "OrderedList" then
        -- "* A) No trimming ...": Pandoc reads the letters as a lettered list.
        if block.listAttributes.style == "UpperAlpha" then found = true end
        for _, item in ipairs(block.content) do visit_item(item, nil) end
      elseif block.t == "BulletList" then
        for _, item in ipairs(block.content) do visit_item(item, nil) end
      elseif block.t == "Div" or block.t == "BlockQuote" then
        visit(block.content)
      end
    end
  end
  visit(callout.content)
  return found
end

local function count_repeats(key)
  local repeats = 0
  for i = 2, #key do
    if key[i] == key[i - 1] then repeats = repeats + 1 end
  end
  return repeats
end

-- New correct letters for the movable questions.
local function choose_key(questions, label)
  local draw = generator(label)
  local total = #questions
  local target = {}
  local base, extra = total // 4, total % 4
  -- The remainder goes to A and C first, then B, so 30 gives A 8, B 7, C 8, D 7.
  for _, letter in ipairs(LETTERS) do target[letter] = base end
  for i, letter in ipairs({ "A", "C", "B", "D" }) do
    if i <= extra then target[letter] = target[letter] + 1 end
  end

  local fixed, movable = {}, {}
  for _, letter in ipairs(LETTERS) do fixed[letter] = 0 end
  for i, question in ipairs(questions) do
    if question.movable then
      movable[#movable + 1] = i
    else
      local letter = LETTERS[question.correct]
      fixed[letter] = fixed[letter] + 1
    end
  end

  -- The letters the movable questions must supply to reach the targets.
  local pool = {}
  for _, letter in ipairs(LETTERS) do
    for _ = 1, math.max(0, target[letter] - fixed[letter]) do pool[#pool + 1] = letter end
  end
  while #pool < #movable do pool[#pool + 1] = LETTERS[draw(4)] end
  while #pool > #movable do table.remove(pool) end

  local best, best_score = nil, nil
  for _ = 1, 4000 do
    for i = #pool, 2, -1 do
      local j = draw(i)
      pool[i], pool[j] = pool[j], pool[i]
    end
    local key, unchanged = {}, 0
    for i, question in ipairs(questions) do key[i] = LETTERS[question.correct] end
    for n, i in ipairs(movable) do
      if pool[n] == key[i] then unchanged = unchanged + 1 end
      key[i] = pool[n]
    end
    local score = unchanged * 1000 + count_repeats(key)
    if best_score == nil or score < best_score then
      best, best_score = key, score
      if score == 0 then break end
    end
  end

  -- Swap pairs of new letters while a swap removes a repeat or an unchanged answer.
  local function score_of(key)
    local unchanged = 0
    for _, i in ipairs(movable) do
      if key[i] == LETTERS[questions[i].correct] then unchanged = unchanged + 1 end
    end
    return unchanged * 1000 + count_repeats(key)
  end
  local improved = best_score > 0
  while improved do
    improved = false
    for a = 1, #movable do
      for b = a + 1, #movable do
        local i, j = movable[a], movable[b]
        if best[i] ~= best[j] then
          best[i], best[j] = best[j], best[i]
          local score = score_of(best)
          if score < best_score then
            best_score, improved = score, true
          else
            best[i], best[j] = best[j], best[i]
          end
        end
      end
    end
  end
  return best
end

-- A bullet that starts with a bold option letter, such as **A.**.
local function bullet_letter(item)
  local first = item[1]
  if first == nil or (first.t ~= "Plain" and first.t ~= "Para") then return nil end
  local strong = first.content[1]
  if strong == nil or strong.t ~= "Strong" or #strong.content ~= 1 then return nil end
  local text = strong.content[1].text or ""
  return text:match("^([A-D])%.$")
end

local function relabel_bullets(list, shift)
  local items = {}
  for _, item in ipairs(list.content) do
    local letter = bullet_letter(item)
    if letter == nil then return list end
    items[#items + 1] = { item = item, letter = letter }
  end
  if #items ~= 4 then return list end
  for _, entry in ipairs(items) do
    local new = LETTERS[(INDEX[entry.letter] - 1 + shift) % 4 + 1]
    local inlines = entry.item[1].content
    inlines[1] = pandoc.Strong({ pandoc.Str(new .. ".") })
    -- "**A.** A counts ...": the first word is the bullet's own letter.
    if inlines[2] ~= nil and inlines[2].t == "Space" and inlines[3] ~= nil and inlines[3].t == "Str" then
      local word, rest = inlines[3].text:match("^([A-D])(%p*)$")
      if word == entry.letter then inlines[3] = pandoc.Str(new .. rest) end
    end
    entry.new = new
  end
  table.sort(items, function(a, b) return a.new < b.new end)
  local ordered = {}
  for _, entry in ipairs(items) do ordered[#ordered + 1] = entry.item end
  list.content = ordered
  return list
end

-- Rotate an enclosed explanation list by shift; a first word that is the
-- item's own letter ("A counts ...") changes with it.
local function rotate_explanations(div, shift)
  local content = pandoc.Blocks(div.content)
  for k, block in ipairs(content) do
    if (block.t == "BulletList" or block.t == "OrderedList") and #block.content == 4 then
      local rotated = {}
      for i, item in ipairs(block.content) do
        local new = (i - 1 + shift) % 4 + 1
        local first = item[1]
        if first and (first.t == "Para" or first.t == "Plain") then
          local word, rest = (first.content[1] and first.content[1].t == "Str"
            and first.content[1].text or ""):match("^([A-D])(%p*)$")
          if word == LETTERS[i] then first.content[1] = pandoc.Str(LETTERS[new] .. rest) end
        end
        rotated[new] = item
      end
      content[k] = pandoc.BulletList(rotated)
      break
    end
  end
  div.content = content
  return div
end

-- Write **A.** to **D.** in front of enclosed explanations.
local function label_explanations(doc)
  return doc:walk({
    Div = function(div)
      if not has_class(div, "alpha-explanations") then return nil end
      local content = pandoc.Blocks(div.content)
      for k, block in ipairs(content) do
        if block.t == "BulletList" or block.t == "OrderedList" then
          local items = {}
          for i, item in ipairs(block.content) do
            local first = item[1]
            if first and (first.t == "Para" or first.t == "Plain") then
              local inlines = pandoc.Inlines({ pandoc.Strong({ pandoc.Str((LETTERS[i] or "?") .. ".") }),
                pandoc.Space() })
              inlines:extend(first.content)
              first.content = inlines
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

function Pandoc(doc)
  local value = doc.meta["exam-version"]
  if value == nil then return label_explanations(doc) end
  local label = pandoc.utils.stringify(value)
  if not label:match("^[%w%-]+$") then
    fail("exam-version must be a short label such as B, got " .. label)
  end

  -- First pass: every question in page order, and every block of panels.
  local questions = {}
  local parents = {}
  local position = 0
  doc:walk({
    traverse = "topdown",
    Div = function(div)
      local children = panel_children(div)
      if #children == 4 then parents[id_set(children)] = children end
      if has_class(div, "alpha-list") then
        position = position + 1
        local question = read_question(div)
        if question then
          question.position = position
          questions[#questions + 1] = question
        else
          warn("question " .. position .. " keeps its order: it needs four options and one .correct marker")
        end
      elseif has_class(div, "callout-note") and #questions > 0 then
        local question = questions[#questions]
        if not question.pinned and names_letters(div) then
          question.movable = false
          question.pinned = true
          warn("question " .. question.position .. " keeps its order: its Solution names options by letter")
        end
      end
    end,
  })
  if #questions == 0 then
    warn("no .alpha-list question with one .correct option was found")
    return label_explanations(doc)
  end

  -- A panel question moves when every option cites panels and the four cited
  -- panels are the only identified blocks of one parent.
  local panel_sets = {}
  for _, question in ipairs(questions) do
    if question.panel and not question.pinned then
      local ids, seen, every = {}, {}, true
      for i = 1, 4 do
        if #question.cites[i] == 0 then every = false end
        for _, id in ipairs(question.cites[i]) do
          if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
      end
      local children = every and #ids == 4 and parents[id_set(ids)] or nil
      if children then
        question.movable = true
        panel_sets[id_set(ids)] = question
        -- Each option's panels by slot, in the order the option names them.
        local slot_of = {}
        for s, id in ipairs(children) do slot_of[id] = s end
        question.children = children
        question.slots = {}
        for i = 1, 4 do
          question.slots[i] = {}
          for k, id in ipairs(question.cites[i]) do question.slots[i][k] = slot_of[id] end
        end
      end
    end
  end

  local key = {}
  for i, question in ipairs(questions) do key[i] = LETTERS[question.correct] end
  if label:upper() ~= "A" then
    key = choose_key(questions, label)
  end

  for i, question in ipairs(questions) do
    question.shift = (INDEX[key[i]] - question.correct) % 4
  end

  -- Second pass: rotate options, their panels and the explanation bullets.
  local current, shift = 0, 0
  doc = doc:walk({
    traverse = "topdown",
    Div = function(div)
      if has_class(div, "alpha-explanations") then
        if current == 0 or shift == 0 then return nil end
        return rotate_explanations(div, shift)
      end
      if not has_class(div, "alpha-list") then
        local children = panel_children(div)
        local question = #children == 4 and panel_sets[id_set(children)] or nil
        if question == nil or question.shift == 0 then return nil end
        -- The panels rotate by the options' step, so each option keeps its panels.
        local panels = {}
        for _, block in ipairs(div.content) do
          if panel_id(block) then panels[#panels + 1] = block end
        end
        local content, slot = pandoc.Blocks({}), 0
        for _, block in ipairs(div.content) do
          if panel_id(block) then
            slot = slot + 1
            content:insert(panels[(slot - 1 - question.shift) % 4 + 1])
          else
            content:insert(block)
          end
        end
        div.content = content
        return div
      end
      if read_question(div) == nil then return nil end
      current = current + 1
      local question = questions[current]
      shift = (INDEX[key[current]] - question.correct) % 4
      if shift == 0 then return nil end
      local content = pandoc.Blocks(div.content)
      for k, block in ipairs(content) do
        if block.t == "OrderedList" or block.t == "BulletList" then
          local rotated = {}
          for i, item in ipairs(block.content) do
            rotated[(i - 1 + shift) % 4 + 1] = item
          end
          if question.children then
            -- The option at letter p names its panels in the slot order that
            -- option p used, so "(a) and (b)" never reads "(b) and (a)".
            for position = 1, 4 do
              local wanted = {}
              for k, slot in ipairs(question.slots[position]) do
                wanted[k] = question.children[(slot - 1 - shift) % 4 + 1]
              end
              local by_id, count = {}, 0
              pandoc.walk_block(pandoc.Div(rotated[position]), {
                Cite = function(cite)
                  count = count + 1
                  by_id[cite.citations[1].id] = cite
                end,
              })
              if count == #wanted then
                local k = 0
                rotated[position] = pandoc.walk_block(pandoc.Div(rotated[position]), {
                  Cite = function()
                    k = k + 1
                    return by_id[wanted[k]]
                  end,
                }).content
              end
            end
          end
          if block.t == "OrderedList" then
            content[k] = pandoc.OrderedList(rotated, block.listAttributes)
          else
            content[k] = pandoc.BulletList(rotated)
          end
          break
        end
      end
      div.content = content
      return div
    end,
    BulletList = function(list)
      if current == 0 or shift == 0 then return nil end
      return relabel_bullets(list, shift)
    end,
  })

  -- The version label on the cover, only when asked for, and the key at the end
  -- of an answer build.
  local write_label = doc.meta["exam-version-label"]
  if write_label == true or (write_label ~= nil and write_label ~= false
      and pandoc.utils.stringify(write_label):lower() == "true") then
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
      entries:insert(pandoc.Str(questions[i].position .. "\u{00A0}" .. letter .. (i < #key and "," or "")))
    end
    doc.blocks:insert(pandoc.Div({ pandoc.Para(entries) },
      pandoc.Attr("exam-version-key", { "exam-version-key" })))
  end
  return label_explanations(doc)
end
