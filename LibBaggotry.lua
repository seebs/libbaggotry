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

function Filter:new()
  local o = {
  	slotspec = { Utility.Item.Slot.Inventory(), Utility.Item.Slot.Bank() }
  }
  setmetatable(o, self)
  self.__index = self
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
  local args = { ... }
  last = table.getn(args)
  op(filter, ...)
end

function Filter:argstring()
  return "bc:+C:eiq:+w"
end

function Filter:from_args(args)
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

  if args['C'] then
    local newspec = {}
    if string.match(args['C'], '/') then
      charspec = args['C']
    else
      charspec = lbag.char_identifier(args['C'])
    end
    for i, v in ipairs(slotspecs) do
      local slotspec, _ = lbag.slotspec_p(v)
      if slotspec then
        table.insert(newspec, string.format("%s:%s", charspec, slotspec))
      else
        ls.printf("Huh?  Got invalid slotspec '%s'.", v)
      end
    end
    self:slot(unpack(newspec))
  else
    self:slot(unpack(slotspecs))
  end
  local filtery = function(op, ...) lbag.filtery(self, op, ...) end

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

  for _, v in pairs(args['leftover_args']) do
    local op, word = lbag.relation(v)
    if string.match(word, ':') then
      filtery(op, lbag.strsplit(word, ':'))
    else
      filtery(op, 'name', word)
    end
  end
end

function Filter:find(baggish, disallow_alts)
  local all_items
  if baggish then
    all_items = lbag.expand_baggish(baggish, disallow_alts)
  else
    all_items = {}
    local some_items
    for _, s in ipairs(self.slotspec) do
      some_items = lbag.expand_baggish(s, disallow_alts)
      for k, v in pairs(some_items) do
        all_items[k] = v
      end
    end
  end
  return_items = {}
  for slot, item in pairs(all_items) do
    if self:match(item, slot) then
      return_items[slot] = item
    end
  end
  return return_items
end

function Filter:slot(slotspec, ...)
  if slotspec then
    self.slotspec = { slotspec, ... }
  end
  return self.slotspec
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
end

function Filter:require(matchish, relop, value)
  local newfunc = Filter:make_matcher(matchish, relop, value)
  if newfunc then
    self.requires = self.requires or {}
    table.insert(self.requires, newfunc)
  end
end

function Filter:exclude(matchish, relop, value)
  local newfunc = Filter:make_matcher(matchish, relop, value)
  if newfunc then
    self.excludes = self.excludes or {}
    table.insert(self.excludes, newfunc)
  end
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
    return string.format("%s %s %s", matchish, relop, value)
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
function lbag.filter()
  return Filter:new()
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

function lbag.slot_updated()
  local whoami = lbag.char_identifier()
  local global_or_account
  if lbag.share_inventory_p() then
    global_or_account = LibBaggotryGlobal
  else
    global_or_account = LibBaggotryAccount
  end
  if not global_or_account[whoami] then
    global_or_account[whoami] = {}
  end
  global_or_account[whoami]['inventory'] = Inspect.Item.Detail(Utility.Item.Slot.All())
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
      if exist._charspec ~= v._charspec then
        exist._charspec = '(Mixed)'
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
  local charspec, slotspec = string.match(spec, '([%a/*]+):(.*)')
  if not slotspec then
    slotspec = spec
  else
    -- an invalid charspec means this isn't a valid fancy slotspec
    if not lbag.char_identifier_p(charspec) then
      return false
    end
  end
  val, err = pcall(function() Utility.Item.Slot.Parse(slotspec) end)
  if err then
    return false
  end
  return slotspec, charspec
end

function lbag.expand_baggish(baggish, disallow_alts)
  local retval = {}
  if baggish == false then
    return {}
  end
  if baggish == true then
    baggish = Utility.Item.Slot.All()
  end
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
    local slotspec, charspec = lbag.slotspec_p(baggish)
    if charspec then
      if disallow_alts then
        lbag.printf("No can do:  Can't use alts with this function.")
	retval = {}
      else
        retval = lbag.char_item_details(charspec, slotspec)
      end
    else
      retval = Inspect.Item.Detail(baggish)
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

function lbag.char_identifier_p(char_identifier)
  if type(char_identifier) ~= 'string' then
    return false
  end
  shard, faction, char = string.match(char_identifier, '^([%a*]+)/([%a*]+)/([%a*]+)$')
  if not char then
    -- what if it's just a single word?
    char = string.match(char_identifier, '^([%a*]+)$')
    if not char then
      return false
    else
      shard = Inspect.Shard()
      shard = shard and (shard.name or "Unknown") or "Unknown"
    end
    local me = Inspect.Unit.Detail("player")
    if not faction then
      faction = me and (me.faction or "Unknown") or "Unknown"
    end
  end
  return shard, faction, char
end

function lbag.char_identifier(character, faction, shard)
  local me = Inspect.Unit.Detail("player")
  if not shard then
    shard = Inspect.Shard()
    shard = shard and (shard.name or "Unknown") or "Unknown"
  end
  if not character then
    character = me and (me.name or "Unknown") or "Unknown"
  end
  if not faction then
    faction = me and (me.faction or "Unknown") or "Unknown"
  end
  return string.format("%s/%s/%s", tostring(shard), tostring(faction), tostring(character))
end

function lbag.match_charspecs(charspec1, charspec2)
  local shard1, faction1, char1 = lbag.char_identifier_p(charspec1)
  if not shard1 then
    return false
  end
  local shard2, faction2, char2 = lbag.char_identifier_p(charspec2)
  if not shard2 then
    return false
  end
  if shard1 ~= shard2 and shard1 ~= '*' then
    return false
  end
  if faction1 ~= faction2 and faction1 ~= '*' then
    return false
  end
  if string.lower(char1) ~= string.lower(char2) and char1 ~= '*' then
    return false
  end
  return true
end

function lbag.find_chars(char, faction, shard)
  local chars = {}
  local charspec = string.format("%s/%s/%s", shard, faction, char)
  local c, f, s
  for k, v in pairs(LibBaggotryAccount) do
    if lbag.match_charspecs(charspec, k) then
      table.insert(chars, k)
    end
  end
  for k, v in pairs(LibBaggotryGlobal) do
    if lbag.match_charspecs(charspec, k) then
      table.insert(chars, k)
    end
  end
  return chars
end

-- you gotta caaaaaaare, you gotta shaaaaaaaare
function lbag.share_inventory_p()
  if LibBaggotryAccount[whoami] then
    return LibBaggotryAccount[whoami]['share_inventory']
  else
    return false
  end
end

function lbag.share_inventory(sharing)
  local whoami = lbag.char_identifier()
  local was_sharing
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

function lbag.char_inventory(character, faction, shard)
  local char_list = lbag.find_chars(character, faction, shard)
  local all_look_same_faction = true
  local found_faction = nil
  local all_look_same_shard = true
  local found_shard = nil
  local retval = {}
  for _, charname in ipairs(char_list) do
    local more_items = {}
    if LibBaggotryAccount[charname] then
      more_items = LibBaggotryAccount[charname]['inventory'] or {}
    elseif LibBaggotryGlobal[charname] then
      more_items = LibBaggotryGlobal[charname]['inventory'] or {}
    end
    for k, v in pairs(more_items) do
      v._charspec = charname
      v._slotspec = k
      retval[charname .. ":" .. k] = v
    end
  end
  return retval
end

function lbag.char_item_details(charspec, slotspec)
  local retval = {}
  local shard, faction, char = lbag.char_identifier_p(charspec)
  if not shard then
    return retval
  end
  items = lbag.char_inventory(char, faction, shard)
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
