-- Neutral answer ids: a student page never names an answer in an id.
--
-- Questions often label their options with ids such as lst-fee-correct1,
-- fig-cellphone-wrong2 or tbl-trace-incorrect. An id is in the page source, and
-- a reader sees it in the status bar when hovering a link to that listing. In a
-- student build, each listing, figure or table id that contains "correct" or
-- "wrong" becomes <prefix>-option-<n>, numbered in the order the page shows
-- them, so neither the name nor the number gives the answer away. Every
-- reference follows: cross-references, links, code cell labels (#| label: and
-- %%| label:) and raw HTML.
--
-- The build is for answers when the top-level `exercise-audience` metadata is
-- `answers`, which the exercise-labels filter reads too. Without that option, a
-- build is for answers when its Quarto profiles include `answers`. An answer
-- build keeps the authored ids.
--
-- The extension runs at pre-ast, before Quarto turns labeled blocks into
-- cross-reference targets.

local function answers_build(meta)
  local audience = meta["exercise-audience"]
  if audience ~= nil then
    local value = pandoc.utils.stringify(audience):lower()
    if value ~= "student" and value ~= "answers" then
      error("neutral-answer-ids: exercise-audience must be student or answers, got " .. value, 0)
    end
    return value == "answers"
  end
  local project = quarto and quarto.project or {}
  for _, profile in ipairs(project.profile or {}) do
    if profile == "answers" then return true end
  end
  return false
end

-- The cross-reference ids that name options; section ids stay, so links into a chapter keep working.
local function reveals_answer(id)
  local lower = (id or ""):lower()
  if not (lower:match("^lst%-") or lower:match("^fig%-") or lower:match("^tbl%-")) then return false end
  return lower:find("correct", 1, true) ~= nil or lower:find("wrong", 1, true) ~= nil
end

local CELL_LABEL = "(|%s*label:%s*)([%w_%-]+)"

function Pandoc(doc)
  if answers_build(doc.meta) then
    return doc
  end

  -- First pass, in document order: every id, and the revealing ones in order.
  local taken, order = {}, {}
  local function note(id)
    if id == nil or id == "" then return end
    if not taken[id] then
      taken[id] = true
      if reveals_answer(id) then order[#order + 1] = id end
    end
  end
  local function note_element(e)
    note(e.identifier)
    if e.t == "CodeBlock" then
      for _, label in e.text:gmatch(CELL_LABEL) do note(label) end
    end
  end
  doc:walk({
    traverse = "topdown",
    Div = note_element, Span = note_element, Header = note_element, CodeBlock = note_element,
    Image = note_element, Table = note_element, Figure = note_element,
  })
  if #order == 0 then
    return doc
  end

  local neutral, count = {}, {}
  for _, id in ipairs(order) do
    local prefix = id:match("^(%a+)%-") or "item"
    local n = count[prefix] or 0
    local candidate
    repeat
      n = n + 1
      candidate = prefix .. "-option-" .. n
    until not taken[candidate]
    count[prefix] = n
    taken[candidate] = true
    neutral[id] = candidate
  end

  local function rename(e)
    if neutral[e.identifier] then e.identifier = neutral[e.identifier] end
    return e
  end
  -- Whole ids only, longest first, so lst-a-correct never rewrites lst-a-correct1.
  local by_length = {}
  for original in pairs(neutral) do by_length[#by_length + 1] = original end
  table.sort(by_length, function(a, b) return #a > #b end)
  local function rename_text(text)
    for _, original in ipairs(by_length) do
      local pattern = "%f[%w_%-]" .. original:gsub("%p", "%%%0") .. "%f[^%w_%-]"
      text = text:gsub(pattern, neutral[original])
    end
    return text
  end

  return doc:walk({
    Div = rename, Span = rename, Header = rename, Image = rename, Table = rename, Figure = rename,
    CodeBlock = function(e)
      e = rename(e)
      e.text = e.text:gsub(CELL_LABEL, function(lead, label)
        return lead .. (neutral[label] or label)
      end)
      return e
    end,
    Cite = function(e)
      for _, citation in ipairs(e.citations) do
        if neutral[citation.id] then citation.id = neutral[citation.id] end
      end
      return e
    end,
    Link = function(e)
      local id = e.target:match("^#(.+)$")
      if id and neutral[id] then e.target = "#" .. neutral[id] end
      return e
    end,
    Str = function(e)
      -- A reference Pandoc did not read as a citation, such as @id at a line end.
      local at, id, rest = e.text:match("^(%[?@)([%w_%-]+)(.*)$")
      if id and neutral[id] then e.text = at .. neutral[id] .. rest end
      return e
    end,
    RawInline = function(e) e.text = rename_text(e.text); return e end,
    RawBlock = function(e) e.text = rename_text(e.text); return e end,
  })
end
