-- Exercise labels: number questions and multiple-choice items in headings.
--
-- A heading becomes an exercise when it is marked explicitly, sits in a
-- conventional exercises section, or opens an exercise include. The filter
-- puts a label such as Q1 or M2 in front of the heading text, gives the heading
-- a stable identifier, and records the label in data attributes that styles
-- and scripts can use. Hierarchical numbering adds visible question groups and
-- numbers their questions Q2.1, Q2.2, and so on.
--
-- Options, under `exercise-labels` in document or project metadata:
--   numbering             flat (default) or hierarchical
--   prefix                prepended to every label: "2.4" gives 2.4.Q1
--   question              letter for open questions (Q)
--   choice                letter for multiple-choice items (M)
--   separator             text between a label and its heading (empty)
--   group-label           word in front of a question group number (Exercise)
--   max-level             deeper exercise headings are raised to it (3)
--   hide-exercise-groups  remove .exercise-group headings (true)

local VERSION = "1.0.1"

-- Level-2 section identifiers whose level-3 headings are exercises.
local SECTION_KINDS = {
  ["exercises"] = "Q",
  ["multiple-choice-exercises"] = "M",
  ["multiple-choice-questions"] = "M",
}

local function fail(message)
  error("exercise-labels: " .. message, 0)
end

local function has_class(element, class_name)
  if element.classes == nil then
    return false
  end
  for _, value in ipairs(element.classes) do
    if value == class_name then
      return true
    end
  end
  return false
end

local function add_class(element, class_name)
  if not has_class(element, class_name) then
    element.classes:insert(class_name)
  end
end

local function remove_class(element, class_name)
  local kept = pandoc.List({})
  for _, value in ipairs(element.classes) do
    if value ~= class_name then
      kept:insert(value)
    end
  end
  element.classes = kept
end

local function contains_class(block, class_name)
  local found = has_class(block, class_name)
  pandoc.walk_block(block, {
    Div = function(div)
      if has_class(div, class_name) then
        found = true
      end
    end,
  })
  return found
end

local function slugify(text)
  local slug = text:lower()
  slug = slug:gsub("[^%w%s%-_]", "")
  slug = slug:gsub("[%s_]+", "-")
  slug = slug:gsub("%-+", "-")
  slug = slug:gsub("^%-", ""):gsub("%-$", "")
  if slug == "" then
    slug = "exercise"
  end
  return slug
end

-- Options

local function meta_value(block, key)
  if type(block) ~= "table" then
    return nil
  end
  return block[key]
end

local function meta_text(value, fallback)
  if value == nil then
    return fallback
  end
  local text = pandoc.utils.stringify(value)
  if text == "" then
    return fallback
  end
  return text
end

local function meta_bool(value, fallback)
  if value == nil then
    return fallback
  end
  if type(value) == "boolean" then
    return value
  end
  local text = pandoc.utils.stringify(value):lower()
  if text == "true" or text == "yes" then
    return true
  end
  if text == "false" or text == "no" then
    return false
  end
  return fallback
end

local function read_options(meta)
  local block = meta["exercise-labels"]

  local numbering = meta_text(meta_value(block, "numbering"), "flat"):lower()
  if numbering ~= "flat" and numbering ~= "hierarchical" then
    fail("numbering must be flat or hierarchical, got " .. numbering)
  end

  local max_level = tonumber(meta_text(meta_value(block, "max-level"), "3"))
  if max_level == nil or max_level < 1 or max_level > 6 or max_level % 1 ~= 0 then
    fail("max-level must be an integer from 1 through 6")
  end

  local separator = meta_value(block, "separator")
  return {
    hierarchical = numbering == "hierarchical",
    prefix = meta_text(meta_value(block, "prefix"), ""),
    letters = {
      Q = meta_text(meta_value(block, "question"), "Q"),
      M = meta_text(meta_value(block, "choice"), "M"),
    },
    separator = separator ~= nil and pandoc.utils.stringify(separator) or "",
    group_label = meta_value(block, "group-label") ~= nil
      and pandoc.utils.stringify(meta_value(block, "group-label")) or "Exercise",
    max_level = max_level,
    hide_groups = meta_bool(meta_value(block, "hide-exercise-groups"), true),
  }
end

-- Heading classification

-- A setup heading opens the shared background of the questions after it and is
-- never labelled. sec-mcq-setup- is the older, multiple-choice-only prefix.
local function is_setup_heading(header)
  local identifier = header.identifier or ""
  return identifier:match("^sec%-setup%-") ~= nil
      or identifier:match("^sec%-mcq%-setup%-") ~= nil
end

local function explicit_kind(header)
  local kind = header.attributes["data-kind"]
    or header.attributes["data-exercise-kind"]
    or header.attributes["data-exercise-type"]
  if kind ~= nil then
    kind = kind:upper()
    if kind == "Q" or kind == "M" then
      return kind
    end
  end

  if has_class(header, "mcq") or has_class(header, "multiple-choice") then
    return "M"
  end
  if has_class(header, "exercise") or has_class(header, "question") then
    return "Q"
  end

  if is_setup_heading(header) then
    return nil
  end
  local identifier = header.identifier
  if identifier:match("^exr%-mcq[-_]") or identifier:match("^sec%-mcq[-_]") then
    return "M"
  end
  if identifier:match("^exr%-")
      or identifier:match("^sec%-exercise%-")
      or identifier:match("^sec%-question%-") then
    return "Q"
  end
  return nil
end

local function is_multiple_choice_chapter(header)
  if header.level ~= 1 or not has_class(header, "exercises") then
    return false
  end
  local title = pandoc.utils.stringify(header.content):lower()
  return title:match("multiple[%s%-]choice") ~= nil
end

local function has_label(header)
  for _, inline in ipairs(header.content) do
    if inline.t == "Span"
        and (has_class(inline, "exercise-label") or has_class(inline, "question-group-label")) then
      return true
    end
  end
  return false
end

-- An exercise include moves its headings so the first sits at target-level.
local function shift_include(div)
  local raw = div.attributes["target-level"]
  local target = tonumber(raw or "3")
  if target == nil or target < 1 or target > 6 or target % 1 ~= 0 then
    fail("target-level must be an integer from 1 through 6, got " .. tostring(raw))
  end
  div.attributes["target-level"] = nil

  local first_level = nil
  pandoc.walk_block(div, {
    Header = function(header)
      if first_level == nil then
        first_level = header.level
      end
    end,
  })
  if first_level == nil or first_level == target then
    return div
  end

  local shift = target - first_level
  return pandoc.walk_block(div, {
    Header = function(header)
      header.level = math.max(1, math.min(6, header.level + shift))
      return header
    end,
  })
end

-- Document pass

local function label_document(doc, options)
  local title = doc.meta.title and pandoc.utils.stringify(doc.meta.title):lower() or ""
  local chapter_kind = title:match("multiple[%s%-]choice") and "M" or nil
  local section_kind = nil
  local counters = { Q = 0, M = 0 }
  local group_counter = 0
  local group_question_counter = 0
  local current_group = nil
  local current_group_level = nil

  -- Know every existing identifier before generating new ones.
  local used_anchors = {}
  pandoc.walk_block(pandoc.Div(doc.blocks), {
    Header = function(header)
      if header.identifier ~= "" then
        used_anchors[header.identifier] = true
      end
    end,
  })

  local function next_exercise_id(kind)
    local label
    if options.hierarchical and current_group ~= nil then
      group_question_counter = group_question_counter + 1
      label = options.letters[kind] .. tostring(current_group) .. "."
        .. tostring(group_question_counter)
    else
      counters[kind] = counters[kind] + 1
      label = options.letters[kind] .. tostring(counters[kind])
    end
    if options.prefix ~= "" then
      return options.prefix .. "." .. label
    end
    return label
  end

  local function ensure_anchor(header, exercise_id)
    if header.identifier ~= "" then
      return
    end
    local base = "exr-" .. slugify(pandoc.utils.stringify(header.content))
    local candidate = base
    local suffix = 2
    while used_anchors[candidate] do
      candidate = base .. "-" .. tostring(suffix)
      suffix = suffix + 1
    end
    used_anchors[candidate] = true
    header.identifier = candidate
    header.attributes["data-generated-anchor"] = exercise_id
  end

  local function prepend(header, label, trailing)
    local content = pandoc.Inlines({ label })
    if trailing ~= "" then
      content:insert(pandoc.Str(trailing))
    end
    content:insert(pandoc.Space())
    content:extend(header.content)
    header.content = content
  end

  local function mark_exercise(header, kind, keep_level)
    if has_label(header) then
      return header
    end

    local grouped = options.hierarchical and current_group ~= nil
    local exercise_id = next_exercise_id(kind)
    ensure_anchor(header, exercise_id)

    if not keep_level and not options.hierarchical then
      header.level = math.min(header.level, options.max_level)
    end

    add_class(header, "exercise-heading")
    add_class(header, "exercise")
    if grouped then
      add_class(header, "unlisted")
    else
      remove_class(header, "unlisted")
    end
    header.attributes["data-exercise-id"] = exercise_id
    header.attributes["data-exercise-kind"] = kind

    prepend(header, pandoc.Span(
      { pandoc.Str(exercise_id) },
      pandoc.Attr("", { "exercise-label" }, {
        ["data-exercise-id"] = exercise_id,
        ["data-exercise-type"] = kind,
      })
    ), options.separator)
    return header
  end

  local function mark_group(header)
    group_counter = group_counter + 1
    group_question_counter = 0
    current_group = group_counter
    current_group_level = header.level

    local group_id = tostring(group_counter)
    local text = group_id
    if options.group_label ~= "" then
      text = options.group_label .. " " .. group_id
    end

    add_class(header, "question-group-heading")
    header.attributes["data-question-group-id"] = group_id
    prepend(header, pandoc.Span(
      { pandoc.Str(text) },
      pandoc.Attr("", { "question-group-label" }, { ["data-question-group-id"] = group_id })
    ), ":")
    return header
  end

  local function label_include(div)
    div = shift_include(div)
    local default_kind = contains_class(div, "alpha-list") and "M" or "Q"
    local is_bank = has_class(div, "exercise-bank")
    local first = true
    local bank_level = nil

    -- A case-study question starts with its setup, a .exercise-setup block of
    -- shared background: set it aside so the question heading gets the label.
    local setups = pandoc.List()
    local rest = pandoc.List()
    for _, block in ipairs(div.content) do
      if block.t == "Div" and has_class(block, "exercise-setup") then
        setups:insert(block)
      else
        rest:insert(block)
      end
    end
    div.content = rest

    local labelled = pandoc.walk_block(div, {
      Header = function(header)
        if is_bank then
          if bank_level == nil then
            bank_level = header.level
            return header
          end
          if header.level == bank_level + 1 then
            return mark_exercise(header, explicit_kind(header) or default_kind, true)
          end
          return header
        end
        if not first then
          return header
        end
        first = false
        if is_setup_heading(header) then
          return header
        end
        return mark_exercise(header, explicit_kind(header) or default_kind, true)
      end,
    })
    setups:extend(labelled.content)
    labelled.content = setups
    return labelled
  end

  local function walk_blocks(blocks)
    local result = pandoc.Blocks({})
    for _, block in ipairs(blocks) do
      if block.t == "Header" then
        if options.hierarchical and current_group_level ~= nil
            and block.level <= current_group_level
            and not has_class(block, "question-group") then
          current_group = nil
          current_group_level = nil
        end
        if block.level == 2 then
          section_kind = SECTION_KINDS[block.identifier]
        end
        if is_multiple_choice_chapter(block) then
          chapter_kind = "M"
        end

        if options.hierarchical and has_class(block, "question-group") then
          result:insert(mark_group(block))
        elseif has_class(block, "exercise-group") then
          if not options.hide_groups then
            result:insert(block)
          end
        else
          local kind = explicit_kind(block)
          if kind ~= nil then
            block = mark_exercise(block, kind)
          elseif chapter_kind ~= nil and block.level == 2 then
            block = mark_exercise(block, chapter_kind)
          elseif section_kind ~= nil and block.level == 3
              and not has_class(block, "exercise-tier") then
            block = mark_exercise(block, section_kind)
          end
          result:insert(block)
        end
      elseif block.t == "Div" then
        if has_class(block, "exercise-include") then
          result:insert(label_include(block))
        else
          block.content = walk_blocks(block.content)
          result:insert(block)
        end
      elseif block.t == "BlockQuote" then
        block.content = walk_blocks(block.content)
        result:insert(block)
      else
        result:insert(block)
      end
    end
    return result
  end

  doc.blocks = walk_blocks(doc.blocks)
  return doc
end

local function add_stylesheet()
  if quarto == nil or quarto.doc == nil then
    return
  end
  if quarto.doc.is_format("html") then
    quarto.doc.add_html_dependency({
      name = "exercise-labels",
      version = VERSION,
      stylesheets = { "exercise-labels.css" },
    })
  end
end

-- Keep only the first copy of each setup on the page: every question of a
-- case study includes its setup, and a page may hold several of them.
local function remove_repeated_setups(blocks, seen)
  local kept = pandoc.List()
  for _, block in ipairs(blocks) do
    if block.t == "Div" and has_class(block, "exercise-setup") then
      local key = block.attributes["setup"] or block.identifier
      if not seen[key] then
        seen[key] = true
        kept:insert(block)
      end
    else
      if block.t == "Div" then
        block.content = remove_repeated_setups(block.content, seen)
      end
      kept:insert(block)
    end
  end
  return kept
end

function Pandoc(doc)
  local options = read_options(doc.meta)
  add_stylesheet()
  doc.blocks = remove_repeated_setups(doc.blocks, {})
  return label_document(doc, options)
end
