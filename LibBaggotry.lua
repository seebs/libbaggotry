--[[ LibBaggotry
     Bag utility functions

     The big thing here is the 'baggish', which is modeled very loosely
     conceptually on git's notion of a commit-ish, which is a thing which
     you could figure out to have been some kind of a commit.

     A baggish is one of a few things:
     1.  A table in which the values all look like item details.
     2.  A "filter" object (more on this later).
     3.  A slot specifier.

     A "filter" object is a special thing that Baggotry uses which
     generates a list of { slot : item_details } pairs similar to
     the results of Inspect.Item.Detail(...).  The difference is that
     a filter limits the list in some way, such as "only items named
     x", or "only stacks of at least 2".

     A filter can include a slot specifier, or can be invoked on any
     other slot specifier; in the absence of a specified one, filters
     default to Utility.Item.Slot.All().

     Various operations then work on a "baggish".  If it's a table, we're
     done.  If it's a slot specifier, it's passed to Inspect.Item.Details().
     If it's a filter, it's invoked (on its default slot specifier).
     If you want to call a filter on a slot specifier other than the one
     you gave it, you should do that and pass the results as your baggish,
     because that'll do what you meant.

]]--

local lbag = {}
Library = Library or {}
Library.LibBaggotry = lbag
lbag.version = "VERSION"

function lbag.variables_loaded(name)
  if name == 'LibBaggotry' then
    LibBaggotryGlobal = LibBaggotryGlobal or {}
    LibBaggotryAccount = LibBaggotryAccount or {}
    -- expose these for debugging convenience.  DO NOT USE THESE.
    lbag.global_vars = LibBaggotryGlobal
    lbag.account_vars = LibBaggotryAccount
  end
end

lbag.color_rarity = { grey = 'trash',
	white = 'common',
	green = 'uncommon',
	blue = 'rare',
	purple = 'epic',
	orange = 'relic',
	yellow = 'quest',
}
lbag.rarity_color_table = { trash = { r = .34375, g = .34375, b = 34375 },
	common = { r = .98, g = .98, b = .98 },
	uncommon = { r = 0, g = .797, b = 0 },
	rare = { r = .148, g = .496, b = .977 },
	epic = { r = .676, g = .281, b = .98 },
	relic = { r = 1, g = .5, b = 0 },
	quest = { r = 1, g = 1, b = 0 },
}

lbag.bestpony = { 'trash', 'common', 'uncommon', 'rare', 'epic', 'relic', 'quest' }

lbag.command_queue = {}

function lbag.printf(fmt, ...)
  print(string.format(fmt or 'nil', ...))
end

-- The filter object/class/whatever
local Filter = {}

function Filter:filter_p(obj)
  if type(obj) == 'table' and getmetatable(obj) == self then
    return true
  else
    return false
  end
end

function Filter:new(args)
  local o = {
  	slotspec = { Utility.Item.Slot.Inventory(), Utility.Item.Slot.Bank() }
  }
  setmetatable(o, self)
  self.__index = self
  if args then
    o:from_args(args)
  end
  return o
end

function Filter:dump()
  lbag.printf("Default slotspec %s", tostring(self.slotspec))
  if self.descr then
    lbag.printf("  Description: %s", tostring(self.descr))
  end
  if self.includes then
    lbag.printf("  Includes:")
    for _, v in ipairs(self.includes) do
      descr = v()
      lbag.printf("    %s", descr)
    end
  end
  if self.requires then
    lbag.printf("  Requires:")
    for _, v in ipairs(self.requires) do
      descr = v()
      lbag.printf("    %s", descr)
    end
  end
  if self.excludes then
    lbag.printf("  Excludes:")
    for _, v in ipairs(self.excludes) do
      descr = v()
      lbag.printf("    %s", descr)
    end
  end
end

function lbag.strsplit(s, p)
  local idx = string.find(s, p)
  if idx then
    return s.sub(s, 1, idx - 1), lbag.strsplit(string.sub(s, idx + 1), p)
  else
    return s
  end
end

function lbag.relation(word)
  if not word then
    return nil, nil
  end
  local relation = Filter.include
  local char = string.sub(word, 1, 1)
  if char == '+' then
    relation = Filter.require
    word = string.sub(word, 2)
  elseif char == '!' then
    relation = Filter.exclude
    word = string.sub(word, 2)
  end
  return relation, word
end

function lbag.filtery(filter, op, ...)
  return op(filter, ...)
end

function Filter:argstring()
  return "bc:+C:eiq:+tw"
end

function Filter:from_args(args)
  if self == Filter then
    newfilter = lbag.filter()
  else
    newfilter = self
  end
  local slotspecs = {}

  if args['b'] then
    table.insert(slotspecs, Utility.Item.Slot.Bank())
  end
  if args['e'] then
    table.insert(slotspecs, Utility.Item.Slot.Equipment())
  end
  if args['i'] then
    table.insert(slotspecs, Utility.Item.Slot.Inventory())
  end
  if args['w'] then
    table.insert(slotspecs, Utility.Item.Slot.Wardrobe())
  end

  if args['t'] then
    newfilter.totals = true
  end

  if table.getn(slotspecs) == 0 then
    table.insert(slotspecs, Utility.Item.Slot.Bank())
    table.insert(slotspecs, Utility.Item.Slot.Inventory())
  end

  newfilter:slot(unpack(slotspecs))

  if args['C'] then
    newfilter:char(args['C'])
  end

  local filtery = function(op, ...) return lbag.filtery(newfilter, op, ...) end

  if args['c'] then
    for _, v in ipairs(args['c']) do
      local op, word = lbag.relation(v)
      filtery(op, 'category', word)
    end
  end

  if args['q'] then
    for _, v in ipairs(args['q']) do
      local op, word = lbag.relation(v)
      if lbag.rarity_p(word) then
	filtery(op, 'rarity', '>=', word)
      else
	bag.printf("Error: '%s' is not a valid rarity.", word)
      end
    end
  end

  for idx, v in pairs(args['leftover_args']) do
    local op, word = lbag.relation(v)
    local expanded
    if string.match(word, ':') then
      expanded = filtery(op, lbag.strsplit(word, ':'))
    else
      expanded = filtery(op, 'name', word)
    end
    args['leftover_args'][idx] = expanded
  end
  return newfilter
end

function Filter:find(baggish, disallow_alts)
  local all_items
  if baggish then
    all_items = lbag.expand_baggish(baggish, disallow_alts)
  else
    all_items = {}
    local some_items
    for _, s in ipairs(self.slotspec) do
      for _, char in ipairs(lbag.find_chars(self.charspec or lbag.whoami())) do
        some_items = lbag.expand_baggish(char .. ':' .. s, disallow_alts)
        for k, v in pairs(some_items) do
          all_items[k] = v
        end
      end
    end
  end
  return_items = {}
  for slot, item in pairs(all_items) do
    if self:match(item, slot) then
      return_items[slot] = item
    end
  end
  if self.totals then
    return_items = lbag.merge_items(return_items)
  end
  return return_items
end

function Filter:slot(slotspec, ...)
  if slotspec then
    self.slotspec = { slotspec, ... }
  end
  return self.slotspec
end

function Filter:char(charspec)
  if charspec then
    self.charspec = charspec
  end
  return self.charspec
end

function Filter:describe(descr)
  self.descr = descr
end

function Filter:match(item, slot)
  if self.excludes then
    for _, v in pairs(self.excludes) do
      if v(item, slot) then
        return false
      end
    end
  end
  if self.requires then
    for _, v in pairs(self.requires) do
      if not v(item, slot) then
        return false
      end
    end
  end
  if self.includes then
    for _, v in pairs(self.includes) do
      if v(item, slot) then
        return true
      end
    end
  else
    return true
  end
end

-- helper functions
function Filter:include(matchish, relop, value)
  local newfunc = Filter:make_matcher(matchish, relop, value)
  if newfunc then
    self.includes = self.includes or {}
    table.insert(self.includes, newfunc)
  end
  return newfunc()
end

function Filter:require(matchish, relop, value)
  local newfunc = Filter:make_matcher(matchish, relop, value)
  if newfunc then
    self.requires = self.requires or {}
    table.insert(self.requires, newfunc)
  end
  return '+' .. newfunc()
end

function Filter:exclude(matchish, relop, value)
  local newfunc = Filter:make_matcher(matchish, relop, value)
  if newfunc then
    self.excludes = self.excludes or {}
    table.insert(self.excludes, newfunc)
  end
  return '!' .. newfunc()
end

function Filter:relop(relop, value1, value2)
  if relop == '==' or relop == '=' then
    return value1 == value2
  elseif relop == '~=' or relop == '!=' then
    return value1 ~= value2
  elseif relop == 'match' then
    return string.match(value1, value2)
  else
    -- relationals have extra requirements

    local equal_success = false
    local greater_success = false
    local lessthan_success = false
    if relop == '<=' or relop == '>=' then
      equal_success = true
    end
    if relop == '<=' or relop == '<' then
      lessthan_success = true
    end
    if relop == '>=' or relop == '>' then
      greater_success = true
    end

    if not value1 and not value2 then
      return equal_success
    end
    if not value1 then
      return lessthan_success
    end
    if not value2 then
      return greaterthan_success
    end
    if relop == '<' then
      return value1 < value2
    elseif relop == '<=' then
      return value1 <= value2
    elseif relop == '>=' then
      return value1 >= value2
    elseif relop == '>' then
      return value1 > value2
    else
      lbag.printf("Invalid relational operator '%s'", tostring(relop))
      return false
    end
  end
end

--[[ The actual matching function

  Full of special cases and knowledge...
  ]]
function Filter:matcher(relop, item, slot, matchish, value)
  if not item then
    return string.format("%s:%s:%s", matchish, relop, value)
  end
  if type(item) ~= 'table' then
    return false
  end
  ivalue = item[matchish]
  -- a stack of 1 is represented as no stack member
  if matchish == 'stack' then
    ivalue = ivalue or 1
  elseif matchish == 'rarity' then
    -- don't try to guess at item rarities, because that would be silly.
    ivalue = lbag.rarity_p(ivalue)
    local calcvalue = lbag.rarity_p(value, true)
    return self:relop(relop, ivalue, calcvalue)
  end
  if type(ivalue) == 'string' then
    ivalue = string.lower(ivalue)
  elseif type(ivalue) == 'number' then
    value = tonumber(value)
  end
  return self:relop(relop, ivalue, value)
end

function Filter:make_matcher(matchish, relop, value)
  if not value then
    value = relop
    if matchish == 'category' or matchish == 'name' then
      relop = 'match'
    else
      relop = '=='
    end
  end
  local match_type = type(matchish)
  if match_type == 'table' then
    lbag.printf("Can't make matchers from tables yet.")
    return nil
  elseif match_type == 'function' then
    -- relop is ignored
    if relop ~= '==' then
      lbag.printf("Warning:  relop ('%s') ignored when matching a function.", relop)
    end
    return function(item, slot)
      matchish(item, slot, value)
    end
  elseif Filter:filter_p(matchish) then
    return function(item, slot) return not matchish:match(item, slot) end
  elseif match_type == 'string' then
    -- for now, assume that it's the name of a field, and
    -- that value is the thing to match it to
    if type(value) == 'string' then
      value = string.lower(value)
    end
    -- closure to stash matchish and value
    return function(item, slot)
      return Filter:matcher(relop, item, slot, matchish, value)
    end
  else
    lbag.printf("Unknown match specifier, type '%s'", match_type)
    return nil
  end
end

-- and expose a little tiny bit of that:
function lbag.filter(...)
  return Filter:new(...)
end

function lbag.dump_item(item, slotspec)
  local prettystack
  if item.stackMax and item.stackMax > 1 then
    prettystack = string.format(" [%d/%d]", item.stack or 1, item.stackMax)
  else
    prettystack = ""
  end
  lbag.printf("%s: %s%s", slotspec, item.name, prettystack)
end

--[[
  a filter editor is a table of various stuff, including UI frames
  galore, that can be bound to a filter and will then let you edit
  the filter.
]]--

local FilterEditor = {}

function lbag.load_filter(name)
  if not LibBaggotryAccount['filters'] then
    LibBaggotryAccount['filters'] = {}
  end
  return LibBaggotryAccount['filters'][name]
end

function lbag.save_filter(name, filter)
  if not LibBaggotryAccount['filters'] then
    LibBaggotryAccount['filters'] = {}
  end
  filter['name'] = name
  LibBaggotryAccount['filters'][name] = filter
end

function lbag.deep_copy(from, visited)
  local to = {}
  for k, v in pairs(from) do
    if type(v) == 'table' then
      if visited[v] then
        lbag.printf("Warning: Deep copy failed due to reference loop.")
      else
        visited[v] = true
	to[k] = lbag.deep_copy(v, visited)
      end
    else
      to[k] = v
    end
  end
  return to
end

function lbag.copy_filter_args(filter)
  local visited = {}
  newfilter = lbag.deep_copy(filter, visited)
  return newfilter
end

function lbag.edit_filter(filter, context, callback, aux)
  if type(filter) == 'string' then
    local name = filter
    filter = lbag.load_filter(name) or {}
    filter['name'] = name
  end
  local closed
  if callback then
    closed = function() callback(filter, aux) end
  end
  local filterwin = lbag.get_filter_editor(filter, context, closed)
end

lbag.filter_editor_stash = {}

function lbag.get_filter_editor(filter, context, callback)
  local editor
  if not context then
    if not lbag.ui_context then
      lbag.ui_context = UI.CreateContext("LibBaggotry")
    end
    context = lbag.ui_context
  end
  if not lbag.filter_editor_stash[context] then
    lbag.filter_editor_stash[context] = {}
  end
  if lbag.filter_editor_stash[context][1] then
    editor = lbag.filter_editor_stash[context][1]
    table.remove(lbag.filter_editor_stash[context], 1)
  else
    editor = FilterEditor:new(context)
  end
  editor.filter = filter
  lbag.printf("lbag: editor.filter is:")
  dump(editor.filter)
  editor.callback = callback
  editor:refresh()
end

function lbag.make_label(window, text, x, y)
  local l, t, r, b = window:GetTrimDimensions()
  local dummy = UI.CreateFrame("Text", "LibBaggotry", window)
  dummy:SetText(text)
  dummy:SetPoint("TOPLEFT", window, "TOPLEFT", l + x, t + y)
end

function lbag.make_checkbox(window, text, x, y)
  local l, t, r, b = window:GetTrimDimensions()
  if text then
    lbag.make_label(window, text, x + 15, y - 2)
  end
  local dummy = UI.CreateFrame("RiftCheckbox", "LibBaggotry", window)
  dummy:SetPoint("TOPLEFT", window, "TOPLEFT", l + x, t + y)
  return dummy
end

function FilterEditor:new(context)
  lbag.printf("Making new FilterEditor.")
  local o = { }
  setmetatable(o, self)
  self.__index = self
  o.window = UI.CreateFrame("RiftWindow", "LibBaggotry", context)
  o.window:SetWidth(300)
  o.window:SetHeight(400)
  o.window:SetTitle("Filter")
  Library.LibDraggable.draggify(o.window)
  o.context = context

  local l, t, r, b = o.window:GetTrimDimensions()

  o.closebutton = UI.CreateFrame("RiftButton", "LibBaggotry", o.window)
  o.closebutton:SetSkin("close")
  o.closebutton:SetPoint("TOPRIGHT", o.window, "TOPRIGHT", -4, 15)
  o.closebutton.Event.LeftPress = function() o:close() end

  lbag.make_label(o.window, "Name:", 8, 5);
  o.namebox = UI.CreateFrame("RiftTextfield", "LibBaggotry", o.window)
  o.namebox:SetWidth(100)
  o.namebox:SetPoint("TOPLEFT", o.window, "TOPLEFT", 70, t + 5)
  o.namebox:SetText('')
  o.namebox:SetBackgroundColor(0.25, 0.25, 0.25, 0.4)

  lbag.make_label(o.window, "Includes:", 8, 25)
  o.bank = lbag.make_checkbox(o.window, "Bank", 10, 45)
  o.inventory = lbag.make_checkbox(o.window, "Inven", 70, 45)
  o.equip = lbag.make_checkbox(o.window, "Equip", 130, 45)
  o.wardrobe = lbag.make_checkbox(o.window, "Ward", 190, 45)

  o.savebutton = UI.CreateFrame("RiftButton", "LibBaggotry", o.window)
  o.savebutton:SetText('SAVE')
  o.savebutton:SetPoint("BOTTOMLEFT", o.window, "BOTTOMLEFT", l + 5, (b * -1) -5)
  o.savebutton:SetWidth(125)
  o.savebutton.Event.LeftPress = function() o:save() end

  o.applybutton = UI.CreateFrame("RiftButton", "LibBaggotry", o.window)
  o.applybutton:SetText('APPLY')
  o.applybutton:SetPoint("BOTTOMRIGHT", o.window, "BOTTOMRIGHT", (-1 * r) - 18, (b * -1) -5)
  o.applybutton:SetWidth(125)
  o.applybutton.Event.LeftPress = function() o:apply() end

  o.scrollbar = UI.CreateFrame("RiftScrollbar", "LibBaggotry", o.window)
  o.scrollbar:SetPoint("TOPRIGHT", o.window, "TOPRIGHT", (-1 * r) - 2, t + 40)
  o.scrollbar:SetPoint("BOTTOMRIGHT", o.window, "BOTTOMRIGHT", (-1 * r) - 2, (-1 * b) - 2)
  o.scrollbar:SetEnabled(false)
  o.scrollbar:SetRange(0, 1)
  o.scrollbar:SetPosition(0)
  o.scrollbar.Event.ScrollbarChange = function() o:scroll() end
  o.window.Event.WheelBack = function() o.scrollbar:Nudge(3) end
  o.window.Event.WheelForward = function() o.scrollbar:Nudge(-3) end

  o.items = {}
  for i = 1, 10 do
    local f = o:makeitem(i)
    o.items[i] = f
    f.frame:SetPoint("TOPLEFT", o.window, "TOPLEFT", l + 2, t + 60 + (20 * i))
    f.frame:SetPoint("BOTTOMRIGHT", o.window, "TOPRIGHT", -2 + (r * -1) - 15, t + 78 + (20 * i))
    f.frame:SetBackgroundColor(0.25, 0.25, 0.25, 0.4)
  end

  return o
end

function FilterEditor:makeitem(i)
  return { frame = UI.CreateFrame("Text", "LibBaggotry", self.window) }
end


function FilterEditor:refresh()
  lbag.printf("FilterEditor: refresh")
  if not self.filter then
    self.filter = lbag.filter()
  end
  self.window:SetVisible(true)
  self.namebox:SetText(self.filter.name or '<name goes here>')
  self.bank:SetChecked(self.filter['b'] or false)
  self.equip:SetChecked(self.filter['e'] or false)
  self.inventory:SetChecked(self.filter['i'] or false)
  self.wardrobe:SetChecked(self.filter['w'] or false)
  for idx, value in ipairs(self.filter['leftover_args']) do
    if idx <= 10 then
      self.items[idx].frame:SetText(value)
    end
  end
end

function FilterEditor:apply()
  if self.callback then
    self.callback()
  end
end

function FilterEditor:save()
  if self.callback then
    self.callback()
  end
  if not self.filter then
    lbag.printf("Oops, got save request with no filter to save!")
    return
  end
  if self.filter['name'] then
    lbag.save_filter(self.filter['name'], self.filter)
    lbag.printf("Saved filter: %s", self.filter['name'])
  end
  self:close()
end

function FilterEditor:close()
  self.filter = nil
  self.callback = nil
  self.window:SetVisible(false)
  local context = self.context
  if not lbag.filter_editor_stash[context] then
    lbag.filter_editor_stash[context] = {}
  end
  table.insert(lbag.filter_editor_stash[context], self)
end

function lbag.slot_updated()
  local whoami = lbag.whoami()
  local global_or_account
  local shard = lbag.shard()
  if lbag.share_inventory_p() then
    global_or_account = LibBaggotryGlobal
  else
    global_or_account = LibBaggotryAccount
  end
  if not global_or_account[shard] then
    global_or_account[shard] = {}
  end
  if not global_or_account[shard][whoami] then
    global_or_account[shard][whoami] = {}
  end
  global_or_account[shard][whoami]['inventory'] = Inspect.Item.Detail(Utility.Item.Slot.All())
end

function lbag.stack_one_item(item_list, stack_size)
  local count = 0
  did_something = false
  local match_us_up = {}
  local matches_left = 0
  local ordered = {}
  local max_stack
  local stacks = 0
  local total_items = 0
  stack_size = stack_size or 0
  for k, v in pairs(item_list) do
    max_stack = max_stack or v.stackMax or 1
    stacks = stacks + 1
    total_items = total_items + (v.stack or 1)
    if stack_size < 1 then
      stack_size = max_stack + stack_size
      if stack_size < 1 then
        lbag.printf("Seriously, splitting to a stack size of <1?  No.")
        return false
      end
    end
  end
  -- nothing to do; don't need to split, and only have one stack
  if stacks < 2 and total_items < stack_size then
    return false
  end
  for k, v in pairs(item_list) do
    local stack = v.stack or 1
    max_stack = max_stack or v.stackMax or 1
    while stack > stack_size do
      lbag.queue(Command.Item.Split, k, stack_size)
      stack = stack - stack_size
      did_something = true
    end
    if stack > 0 and stack ~= stack_size then
      v.stack = stack
      match_us_up[k] = v
      matches_left = matches_left + stack
      table.insert(ordered, k)
    end
    while table.getn(ordered) >= 2 do
      local removed = false
      count = count + 1
      if count > 100 then
	lbag.printf("Over a hundred steps, giving up.")
	return did_something
      end
      --[[ note:  "ordered" isn't a specific order; rather, it's ANY
	order at all so that we can do "the first one". ]]
      local first = ordered[1]
      local second = ordered[2]
      if not match_us_up[first] then
        lbag.printf("error, match_us_up1[%s] is nil", first)
      end
      if not match_us_up[second] then
        lbag.printf("error, match_us_up2[%s] is nil", second)
      end
      lbag.queue(Command.Item.Move, first, second)
      did_something = true
      local s1 = match_us_up[first].stack
      local s2 = match_us_up[second].stack
      if match_us_up[first].stack + match_us_up[second].stack > max_stack then
	moved = max_stack - match_us_up[second].stack
	match_us_up[first].stack = match_us_up[first].stack - moved
	match_us_up[second].stack = match_us_up[second].stack + moved
      else
	match_us_up[second].stack = match_us_up[second].stack + match_us_up[first].stack
	match_us_up[first] = nil
	table.remove(ordered, 1)
	removed = true
      end
      while match_us_up[second].stack > stack_size do
	lbag.queue(Command.Item.Split, second, stack_size)
	match_us_up[second].stack = match_us_up[second].stack - stack_size
	matches_left = matches_left - stack_size
      end
      -- and this might be an empty stack now, or a full stack
      if match_us_up[second].stack == 0 or match_us_up[second].stack == stack_size then
	match_us_up[second] = nil
	table.remove(ordered, removed and 1 or 2)
      end
    end
  end
  -- we may have things which were left over
  return did_something
end

function lbag.stack_full_p(item, slotspec, stack_size)
  if stack_size then
    return (item.stack or 1) >= stack_size
  else
    return item.stack == item.stackMax
  end
end

function lbag.stack(baggish, stack_size)
  local item_list = lbag.expand_baggish(baggish, true)
  local item_lists = {}
  for k, v in pairs(item_list) do
    item_lists[v.type] = item_lists[v.type] or {}
    item_lists[v.type][k] = v
  end
  local improved = false
  for k, v in pairs(item_lists) do
    if lbag.stack_one_item(v, stack_size) then
      improved = true
    end
  end
  if not improved then
    lbag.printf("No room for improving stacking.")
  end
end

function lbag.move_items(baggish, slotspec, swap_items)
  -- the items we'd like to move...
  local item_list = lbag.expand_baggish(baggish, true)
  if not item_list then
    lbag.printf("Error, couldn't find any items to move.")
  end
  if not lbag.slotspec_p(slotspec) then
    lbag.printf("Error, got invalid slotspec '%s', can't move things to it.", slotspec)
    return
  end
  local target_slots = Inspect.Item.List(slotspec)
  local items_to_move = {}
  local items_to_replace = {}
  local empty_slots = {}
  -- find items which are not in "baggish"
  for slot, item in pairs(target_slots) do
    if string.sub(slot, 3, 2) ~= 'bg' then
      if item then
        if swap_items and (not item_list[slot]) then
	  table.insert(items_to_replace, slot)
        end
      else
        table.insert(empty_slots, slot)
      end
    end
  end
  local anchored = "^" .. slotspec
  local moving_any = false
  for slot, item in pairs(item_list) do
    if not string.match(slot, anchored) and string.sub(slot, 3, 2) ~= 'bg' then
      moving_any = true
      table.insert(items_to_move, slot)
    end
  end

  if not moving_any then
    return
  end

  -- now, we have some items to replace, and some items to move.
  while items_to_move[1] and (items_to_replace[1] or empty_slots[1]) do
    local this_item = items_to_move[1]
    table.remove(items_to_move, 1)
    local that_item
    if items_to_replace[1] then
      that_item = items_to_replace[1]
      table.remove(items_to_replace, 1)
    else
      that_item = empty_slots[1]
      table.remove(empty_slots, 1)
    end
    lbag.queue(Command.Item.Move, this_item, that_item)
  end
end

function lbag.merge_items(baggish)
  local item_list = lbag.expand_baggish(baggish)
  local item_stacks = {}
  for k, v in pairs(item_list) do
    if item_stacks[v.type] then
      local exist = item_stacks[v.type]
      local where1
      if lbag.slotspec_p(exist._slotspec) then
	where1 = Utility.Item.Slot.Parse(exist._slotspec)
      else
        where1 = exist._slotspec
      end
      local where2 = Utility.Item.Slot.Parse(v._slotspec)
      if where1 ~= where2 then
        exist._slotspec = '(Mixed)'
      else
	-- if exist._slotspec were previously something like si01.002,
	-- it will now be 'inventory'
        exist._slotspec = where1
      end
      if exist._character ~= v._character then
        exist._character = '(Mixed)'
      end
      exist._stacks = exist._stacks + 1
      exist.stack = exist.stack + (v.stack or 1)
    else
      v._stacks = 1
      v.stack = v.stack or 1
      item_stacks[v.type] = v
    end
  end
  return item_stacks
end

lbag.already_filtered = {}

function lbag.rarity_p(rarity, permissive)
  -- handle nil, because .rarity isn't set when it's 'common'
  rarity = rarity or 'common'
  if permissive then
    -- translate colors because people are lazy
    rarity = lbag.color_rarity[rarity] or rarity
  end
  for i, v in ipairs(lbag.bestpony) do
    if rarity == v then
      return i, rarity, lbag.rarity_color_table[rarity]
    end
  end
  return false
end

function lbag.rarity_color(rarity)
  _, _, rgb = lbag.rarity_p(rarity, true)
  if rgb then
    return rgb.r, rgb.g, rgb.b
  else
    return 0.8, 0.8, 0.8
  end
end

function lbag.slotspec_p(spec)
  if type(spec) ~= 'string' then
    return false
  end
  local character, slotspec = string.match(spec, '([%a*]+):(.*)')
  if not slotspec then
    slotspec = spec
  else
    character = string.lower(character)
  end
  val, err = pcall(function() Utility.Item.Slot.Parse(slotspec) end)
  if err then
    return false
  end
  return slotspec, character
end

function lbag.empty(slotspec)
  local retval = {}
  if lbag.slotspec_p(slotspec) then
    local list = Inspect.Item.List(slotspec)
    for s, i in pairs(list) do
      if not i then
        retval[s] = false
      end
    end
  else
    return {}
  end
end

function lbag.expand_baggish(baggish, disallow_alts)
  local retval = {}
  if baggish == false then
    return {}
  end
  if baggish == true then
    baggish = Utility.Item.Slot.All()
  end
  local whoami = lbag.whoami()
  if Filter:filter_p(baggish) then
    if lbag.already_filtered[baggish] then
      lbag.printf("Encountered filter loop, returning empty set.")
      return {}
    else
      lbag.already_filtered[baggish] = true
      retval = baggish:find(nil, disallow_alts)
      lbag.already_filtered[baggish] = false
    end
  elseif type(baggish) == 'table' then
    -- could be a few things
    for k, v in pairs(baggish) do
      if Filter:filter_p(k) then
	lbag.already_filtered[k] = true
        local item_list = k:find(lbag.slotspec_p(v) and v or nil, disallow_alts)
	lbag.already_filtered[k] = false
	for k2, v2 in pairs(item_list) do
	  retval[k2] = v2
	end
      elseif lbag.slotspec_p(k) and type(v) == 'table' then
        -- a slotspec:table pair is probably already good
	retval[k] = v
      elseif lbag.slotspec_p(v) then
        local some_items = lbag.expand_baggish(v)
	for k2, v2 in pairs(some_items) do
	  retval[k2] = v2
	end
      else
        lbag.printf("Unknown table item %s => %s", tostring(k), tostring(v))
      end
    end
  elseif lbag.slotspec_p(baggish) then
    local slotspec, character = lbag.slotspec_p(baggish)
    if character and character ~= whoami then
      if disallow_alts then
        lbag.printf("No can do:  Can't use alts with this function.")
	retval = {}
      else
        retval = lbag.char_item_details(character, slotspec)
      end
    else
      retval = Inspect.Item.Detail(slotspec)
    end
  elseif type(baggish) == 'function' then
    local filter = lbag:filter()
    filter:include(baggish)
    lbag.already_filtered[filter] = true
    local retval = filter:find(nil, disallow_alts)
    lbag.already_filtered[filter] = false
  else
    lbag.printf("Couldn't figure out what %s was.", tostring(baggish))
    return {}
  end
  for k, v in pairs(retval) do
    v.stack = v.stack or 1
    v.rarity = v.rarity or 'common'
    if not v._slotspec then
      v._slotspec = k
    end
    if not v._character then
      v._character = whoami
    end
  end
  return retval
end

function lbag.dump(baggish)
  local item_list = lbag.expand_baggish(baggish)
  local dumped_any = false
  for k, v in pairs(item_list) do
    lbag.dump_item(v, k)
    dumped_any = true
  end
  if not dumped_any then
    lbag.printf("No matches.")
  end
end

function lbag.iterate(baggish, func, value, aux)
  local item_list = lbag.expand_baggish(baggish)
  local count = 0
  for slot, details in pairs(item_list) do
    value = func(details, slot, value, aux)
    count = count + 1
  end
  return value, count
end

function lbag.select(baggish, func, aux)
  local item_list = lbag.expand_baggish(baggish)
  local return_list = {}
  for slot, details in pairs(item_list) do
    if func(details, slot, aux) then
      return_list[slot] = details
    end
  end
  return return_list
end

function lbag.reject(baggish, func, aux)
  local item_list = lbag.expand_baggish(baggish)
  local return_list = {}
  for slot, details in pairs(item_list) do
    if not func(details, slot, aux) then
      return_list[slot] = details
    end
  end
  return return_list
end

function lbag:first(baggish, func, aux)
  all_items = expand_baggish(aux)
  -- Because I think item ID should be in there somewhere
  for slot, item in pairs(all_items) do
    if func(item, slot, aux) then
      return { slot = item }
    end
  end
  return nil
end

function lbag.queue(func, ...)
  local func_and_args = { func, ... }
  table.insert(lbag.command_queue, func_and_args)
end

function lbag.runqueue()
  if lbag.command_queue[1] then
    local func_args = lbag.command_queue[1]
    local func = func_args[1]
    if not func then
      lbag.printf("Huh?  Got nil func.  Ignoring it.")
    else
      table.remove(func_args, 1)
      func(unpack(func_args))
    end
    table.remove(lbag.command_queue, 1)
  end
end

function lbag.find(baggish)
  local item_list = lbag.expand_baggish(baggish)
  return item_list
end

function lbag.scratch_slot()
  for k, v in pairs(Inspect.Item.List(Utility.Item.Slot.Inventory())) do
    if v == false then
      return k
    end
  end
  return false
end

function lbag.find_chars(char)
  local chars = {}
  local shard = lbag.shard()
  char = string.lower(char)
  if LibBaggotryAccount[shard] then
    for k, v in pairs(LibBaggotryAccount[shard]) do
      if k == char or (char == '*' and Library.LibAccounts.available_p(k)) then
        table.insert(chars, k)
      end
    end
  end
  if LibBaggotryGlobal[shard] then
    for k, v in pairs(LibBaggotryGlobal[shard]) do
      if k == char or (char == '*' and Library.LibAccounts.available_p(k)) then
	table.insert(chars, k)
      end
    end
  end
  return chars
end

-- you gotta caaaaaaare, you gotta shaaaaaaaare
function lbag.share_inventory_p()
  local whoami = lbag.whoami()
  local shard = lbag.shard()
  if LibBaggotryAccount[shard] and LibBaggotryAccount[shard][whoami] then
    return LibBaggotryAccount[shard][whoami]['share_inventory']
  else
    return false
  end
end

function lbag.shard()
  if not lbag.shard_name then
    local ishard = Inspect.Shard()
    if ishard then
      lbag.shard_name = ishard.name
    end
  end
  return lbag.shard_name or "Unknown"
end

function lbag.whoami()
  local whoami
  local me = Inspect.Unit.Detail("player")
  if me then
    whoami = string.lower(me.name)
  end
  return whoami or "Unknown"
end

function lbag.share_inventory(sharing)
  local was_sharing
  local whoami = lbag.whoami()
  if LibBaggotryAccount[whoami] then
    was_sharing = LibBaggotryAccount[whoami]['share_inventory']
  else
    LibBaggotryAccount[whoami] = {}
    was_sharing = false
  end
  LibBaggotryAccount[whoami]['share_inventory'] = sharing
  if sharing ~= was_sharing then
    if was_sharing then
      LibBaggotryAccount[whoami][inventory] = Inspect.Item.Detail()
      LibBaggotryGlobal[whoami][inventory] = nil
    else
      LibBaggotryGlobal[whoami][inventory] = Inspect.Item.Detail()
      LibBaggotryAccount[whoami][inventory] = nil
    end
  end
end

function lbag.char_inventory(character)
  -- this is useful because 'character' might have been '*'
  local char_list = lbag.find_chars(character)
  local shard = lbag.shard()
  local retval = {}
  for _, charname in ipairs(char_list) do
    local more_items = {}
    if LibBaggotryAccount[shard] and LibBaggotryAccount[shard][charname] then
      more_items = LibBaggotryAccount[shard][charname]['inventory'] or {}
    elseif LibBaggotryGlobal[shard] and LibBaggotryGlobal[shard][charname] then
      more_items = LibBaggotryGlobal[shard][charname]['inventory'] or {}
    end
    for k, v in pairs(more_items) do
      v._character = charname
      v._slotspec = k
      retval[charname .. ":" .. k] = v
    end
  end
  return retval
end

function lbag.char_item_details(character, slotspec)
  local retval = {}
  items = lbag.char_inventory(character)
  if items then
    pat = "^[%a/]-:?" .. slotspec
    for k, v in pairs(items) do
      if string.match(k, pat) then
	-- dup table since some operations assume it's safe to mess with
	-- bag contents
	local newtable = {}
	for k2, v2 in pairs(v) do
	  newtable[k2] = v2
	end
        retval[k] = newtable
      end
    end
  end
  return retval
end

table.insert(Event.Item.Slot, { lbag.slot_updated, "LibBaggotry", "slot update hook" })
table.insert(Event.Addon.SavedVariables.Load.End, { lbag.variables_loaded, "LibBaggotry", "variable loaded hook" })
table.insert(Event.System.Update.Begin, { lbag.runqueue, "LibBaggotry", "command queue hook" })
