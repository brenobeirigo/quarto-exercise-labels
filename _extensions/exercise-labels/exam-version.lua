-- Exam versions: a new answer key from the same multiple-choice paper.
--
-- Render with `-M exam-version:B` (any label) to move the correct answers of
-- the paper's plain-text questions to new letters. Without `exam-version`, or
-- with `A`, the paper stays as written.
--
-- A question is an `.alpha-list` whose ordered list has four options and one
-- `.correct` marker. Its options rotate together, so the correct option lands on
-- its new letter and the A to D labels stay in order. A question whose options
-- cite a listing, figure or table (@lst-, @fig-, @tbl-) keeps its order, because
-- option A must keep pointing at panel (a).
--
-- The new letters change every movable answer, keep the A to D totals of the
-- paper balanced and avoid the same letter on consecutive questions where
-- possible. The choice depends only on the label and the paper, so the student
-- and the answer renders get the same order.
--
-- Explanation bullets that start with a bold letter, `- **A.** ...`, follow
-- their options: they are relabelled, reordered, and a first word that repeats
-- the bullet's own letter ("**A.** A counts ...") changes with it. Another
-- letter in a bullet, such as "the same mistake as A", cannot be rewritten
-- safely; the render warns about it.
--
-- The cover subtitle gets "Version B". An answer build
-- (`exercise-audience: answers`) ends with the version's key.
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
    if block.t == "OrderedList" then list = block; break end
  end
  if list == nil or #list.content ~= 4 then return nil end
  local correct, panel = {}, false
  for i, item in ipairs(list.content) do
    pandoc.walk_block(pandoc.Div(item), {
      Span = function(span) if has_class(span, "correct") then correct[#correct + 1] = i end end,
      Div = function(inner) if has_class(inner, "correct") then correct[#correct + 1] = i end end,
      Cite = function(cite)
        for _, citation in ipairs(cite.citations) do
          if citation.id:match("^lst%-") or citation.id:match("^fig%-")
              or citation.id:match("^tbl%-") then panel = true end
        end
      end,
    })
  end
  if #correct ~= 1 then return nil end
  return { list = list, correct = correct[1], movable = not panel }
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

local function relabel_bullets(list, shift, question_number)
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
    for k = 4, #inlines do
      local inline = inlines[k]
      if inline.t == "Str" and inline.text:match("^[A-D]%p*$") and INDEX[inline.text:sub(1, 1)] then
        warn("question " .. question_number .. ", explanation " .. entry.letter
          .. " names option " .. inline.text:sub(1, 1) .. "; describe it instead")
      end
    end
    entry.new = new
  end
  table.sort(items, function(a, b) return a.new < b.new end)
  local ordered = {}
  for _, entry in ipairs(items) do ordered[#ordered + 1] = entry.item end
  list.content = ordered
  return list
end

local function audience(meta)
  local value = meta["exercise-audience"]
  return value and pandoc.utils.stringify(value):lower() or ""
end

function Pandoc(doc)
  local value = doc.meta["exam-version"]
  if value == nil then return nil end
  local label = pandoc.utils.stringify(value)
  if not label:match("^[%w%-]+$") then
    fail("exam-version must be a short label such as B, got " .. label)
  end

  -- First pass: every question in page order.
  local questions = {}
  doc:walk({
    traverse = "topdown",
    Div = function(div)
      if has_class(div, "alpha-list") then
        local question = read_question(div)
        if question then questions[#questions + 1] = question end
      end
    end,
  })
  if #questions == 0 then
    warn("no .alpha-list question with one .correct option was found")
    return nil
  end

  local key = {}
  for i, question in ipairs(questions) do key[i] = LETTERS[question.correct] end
  if label:upper() ~= "A" then
    key = choose_key(questions, label)
  end

  -- Second pass: rotate options, then the explanation bullets that follow them.
  local current, shift, number = 0, 0, 0
  doc = doc:walk({
    traverse = "topdown",
    Div = function(div)
      if not has_class(div, "alpha-list") then return nil end
      if read_question(div) == nil then return nil end
      current = current + 1
      local question = questions[current]
      shift = (INDEX[key[current]] - question.correct) % 4
      number = current
      if shift == 0 then return nil end
      local content = pandoc.Blocks(div.content)
      for k, block in ipairs(content) do
        if block.t == "OrderedList" then
          local rotated = {}
          for i, item in ipairs(block.content) do
            rotated[(i - 1 + shift) % 4 + 1] = item
          end
          content[k] = pandoc.OrderedList(rotated, block.listAttributes)
          break
        end
      end
      div.content = content
      return div
    end,
    BulletList = function(list)
      if current == 0 or shift == 0 then return nil end
      return relabel_bullets(list, shift, number)
    end,
  })

  -- The version label on the cover, and the key at the end of an answer build.
  local tag = pandoc.Inlines({ pandoc.Str("Version"), pandoc.Space(), pandoc.Str(label) })
  if doc.meta.subtitle then
    local subtitle = pandoc.Inlines(doc.meta.subtitle)
    subtitle:insert(pandoc.LineBreak())
    subtitle:extend(tag)
    doc.meta.subtitle = subtitle
  else
    doc.meta.subtitle = tag
  end
  if audience(doc.meta) == "answers" then
    local entries = pandoc.Inlines({ pandoc.Strong({ pandoc.Str("Key,"), pandoc.Space(),
      pandoc.Str("version"), pandoc.Space(), pandoc.Str(label .. ":") }) })
    for i, letter in ipairs(key) do
      entries:insert(pandoc.Space())
      entries:insert(pandoc.Str(i .. "\u{00A0}" .. letter .. (i < #key and "," or "")))
    end
    doc.blocks:insert(pandoc.Div({ pandoc.Para(entries) },
      pandoc.Attr("exam-version-key", { "exam-version-key" })))
  end
  return doc
end
