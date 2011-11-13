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

lbag.command_queue = {}

function lbag.printf(fmt, ...)
  print(string.format(fmt or 'nil', ...))
end

-- The filter object/class/whatever
local Filter = {}

function Filter:is_a(obj)
  if type(obj) == 'table' and getmetatable(obj) == self then
    return true
  else
    return false
  end
end

function Filter:new()
  local o = {
  	slotspec = Utility.Item.Slot.All()
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function Filter:dump(slotspec)
  lbag.printf("Filter: slotspec %s", slotspec or self.slotspec)
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

function Filter:find(baggish)
  if baggish then
    all_items = lbag.expand_baggish(baggish)
  else
    all_items = Inspect.Item.Detail(self.slotspec)
  end
  return_items = {}
  for slot, item in pairs(all_items) do
    if self:match(item, slot) then
      return_items[slot] = item
    end
  end
  return return_items
end

function Filter:slot(slotspec)
  self.slotspec = slotspec
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

function Filter:include(matchish, value)
  local newfunc = Filter:make_matcher(matchish, value)
  if newfunc then
    self.includes = self.includes or {}
    table.insert(self.includes, newfunc)
  end
end

function Filter:require(matchish, value)
  local newfunc = Filter:make_matcher(matchish, value)
  if newfunc then
    self.requires = self.requires or {}
    table.insert(self.requires, newfunc)
  end
end

function Filter:exclude(matchish)
  local newfunc = Filter:make_matcher(matchish, value)
  if newfunc then
    self.excludes = self.excludes or {}
    table.insert(self.excludes, newfunc)
  end
end

--[[ The actual matching function

  Full of special cases and knowledge...
  ]]
function Filter:matcher(item, slot, matchish, value)
  local contain = false
  if not item then
    return string.format("%s = %s", matchish, value)
  end
  if type(item) ~= 'table' then
    return false
  end
  ivalue = item[matchish]
  -- a stack of 1 is represented as no stack member
  if matchish == 'stack' then
    ivalue = ivalue or 1
  elseif matchish == 'category' or matchish == 'name' then
    contain = true
  end
  if ivalue then
    if type(ivalue) == 'string' then
      ivalue = string.lower(ivalue)
    end
    if contain then
      if string.match(ivalue, value) then
        return true
      else
        return false
      end
    elseif value ~= ivalue then
      return false
    end
  elseif value then
    return false
  end
  return true
end

function Filter:make_matcher(matchish, value)
  local match_type = type(matchish)
  if match_type == 'table' then
    lbag.printf("Can't make matchers from tables yet.")
    return nil
  elseif match_type == 'function' then
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
      return Filter:matcher(item, slot, matchish, value)
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
  lbag.printf("%s: %s [%d]", slotspec, item.name, item.stack or 1)
end

-- doesn't yet try to merge to stack size.
function lbag.split_one_item(item_list, stack_size)
  local count = 0
  did_something = false
  if stack_size < 1 then
    lbag.printf("Seriously, splitting to a stack size of <1?  No.")
    return false
  end
  local match_us_up = {}
  local matches_left = 0
  local ordered = {}
  local max_stack
  for k, v in pairs(item_list) do
    local stack = v.stack or 1
    max_stack = max_stack or v.stackMax
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
      count = count + 1
      if count > 100 then
	lbag.printf("Over a hundred steps, giving up.")
	return did_something
      end
      --[[ note:  "ordered" isn't a specific order; rather, it's ANY
	order at all so that we can do "the first one". ]]
      local first = ordered[1]
      local second = ordered[2]
      lbag.queue(Command.Item.Move, first, second)
      if match_us_up[first].stack + match_us_up[second].stack > max_stack then
	moved = max_stack - match_us_up[second].stack
	match_us_up[first].stack = match_us_up[first].stack - moved
	match_us_up[second].stack = match_us_up[second].stack + moved
      else
	match_us_up[second].stack = match_us_up[second].stack + match_us_up[first].stack
	match_us_up[first] = nil
	table.remove(ordered, 1)
      end
      while match_us_up[second].stack > stack_size do
	lbag.queue(Command.Item.Split, second, stack_size)
	did_something = true
	match_us_up[second].stack = match_us_up[second].stack - stack_size
	matches_left = matches_left - stack_size
      end
      -- and this might be an empty stack now
      if match_us_up[second].stack == 0 then
	match_us_up[second] = nil
	table.remove(ordered, 2)
      end
    end
  end
  -- we may have things which were left over
  return did_something
end

function lbag.merge_one_item(item_list, stack_size)
  local count = 0
  local total_capacity = 0
  local total_present = 0
  local ordered = {}
  for k, v in pairs(item_list) do
    count = count + 1
    total_capacity = total_capacity + (v.stackMax or 1)
    total_present = total_present + (v.stack or 1)
    stack_size = stack_size or v.stackMax
    table.insert(ordered, k)
  end
  stack_size = stack_size or 0
  if count < 2 then
    return false
  end
  lbag.printf("%d slot(s), %d items, %d total capacity, stack size %d",
  	count, total_present, total_capacity, stack_size)
  --[[
    If we got here, we now have a table containing at least two slots,
    all of which have extra room.
  ]]
  local front = 1
  local back = count
  local steps = 0
  while back > front and steps < 25 do
    local backslot = ordered[back]
    local frontslot = ordered[front]
    local backitem = item_list[backslot]
    local frontitem = item_list[frontslot]
    local to_move = backitem.stack or 1
    while to_move > 0 and back > front and steps < 25 do
      moving = stack_size - (frontitem.stack or 1)
      if moving > to_move then
        moving = to_move
      end
      lbag.queue(Command.Item.Move, backslot, frontslot)
      steps = steps + 1
      to_move = to_move - moving
      frontitem.stack = (frontitem.stack or 1) + moving
      backitem.stack = (backitem.stack or 1) - moving
      if frontitem.stack >= frontitem.stackMax then
        front = front + 1
	frontslot = ordered[front]
	frontitem = item_list[frontslot]
      end
      if backitem.stack < 1 then
        back = back - 1
	backslot = ordered[back]
	backitem = item_list[backslot]
      end
    end
  end
  return true
end

function lbag.stack_full_p(item, slotspec, stack_size)
  if stack_size then
    return (item.stack or 1) >= stack_size
  else
    return item.stack == item.stackMax
  end
end

function lbag.split(baggish, stack_size)
  local item_list = lbag.expand_baggish(baggish)
  local item_lists = {}
  -- splitting to stackMax would be unrewarding
  stack_size = stack_size or 10
  for k, v in pairs(item_list) do
    item_lists[v.type] = item_lists[v.type] or {}
    item_lists[v.type][k] = v
  end
  local improved = false
  for k, v in pairs(item_lists) do
    if lbag.split_one_item(v, stack_size) then
      improved = true
    end
  end
  if not improved then
    lbag.printf("No room for improving stacking.")
  end
end

function lbag.merge(baggish, stack_size)
  local item_list = lbag.reject(baggish, lbag.stack_full_p, stack_size)
  local item_lists = {}
  for k, v in pairs(item_list) do
    item_lists[v.type] = item_lists[v.type] or {}
    item_lists[v.type][k] = v
  end
  local improved = false
  for k, v in pairs(item_lists) do
    if lbag.merge_one_item(v, stack_size) then
      improved = true
    end
  end
  if not improved then
    lbag.printf("No room for improving stacking.")
  end
end

lbag.already_filtered = {}

function lbag.slotspec_p(slotspec)
  if type(slotspec) ~= 'string' then
    return false
  end
  val, err = pcall(function() Utility.Item.Slot.Parse(slotspec) end)
  if err then
    return false
  end
  return true
end

function lbag.expand_baggish(baggish)
  if baggish == false then
    return {}
  end
  if baggish == true then
    baggish = Utility.Item.Slot.All()
  end
  if Filter:is_a(baggish) then
    if lbag.already_filtered[baggish] then
      lbag.printf("Encountered filter loop, returning empty set.")
      return {}
    else
      lbag.already_filtered[baggish] = true
      local retval = baggish:find()
      lbag.already_filtered[baggish] = false
      return retval
    end
  elseif type(baggish) == 'table' then
    -- could be a few things
    local retval = {}
    for k, v in pairs(table) do
      if Filter:is_a(k) then
	lbag.already_filtered[k] = true
        local item_list = k:find(lbag.slotspec_p(v) and v or nil)
	lbag.already_filtered[k] = false
	for k2, v2 in pairs(item_list) do
	  retval[k2] = v2
	end
      elseif lbag.slotspec_p('k') and type(v) == 'table' then
        -- a slotspec:table pair is probably already good
	retval[k] = v
      end
    end
    return retval
  elseif lbag.slotspec_p(baggish) then
    return Inspect.Item.Detail(baggish)
  elseif type(baggish) == 'function' then
    local filter = lbag:filter()
    filter:include(baggish)
    lbag.already_filtered[filter] = true
    local retval = filter:find()
    lbag.already_filtered[filter] = false
    return retval
  else
    lbag.printf("Couldn't figure out what %s was.", tostring(baggish))
    return {}
  end
end

function lbag.dump(baggish)
  local item_list = lbag.expand_baggish(baggish)
  for k, v in pairs(item_list) do
    lbag.dump_item(v, k)
  end
end

function lbag.iterate(baggish, func, aux)
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

table.insert(Event.System.Update.Begin, { lbag.runqueue, "LibBaggotry", "command queue hook" })
