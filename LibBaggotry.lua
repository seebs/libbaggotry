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

function Filter:first(func, aux, slotspec)
  all_keys = Inspect.Item.List(slotspec or self.slotspec)
  all_items = Inspect.Item.Detail(slotspec or self.slotspec)
  -- Because I think item ID should be in there somewhere
  for slot, item in pairs(all_items) do
    item.id = all_keys[slot].id
    if self:match(item, slot) then
      if func(item, slot, aux) then
        return { slot = item }
      end
    end
  end
  return nil
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

function lbag.merge_one_item(item_list)
  local count = 0
  local total_capacity = 0
  local total_present = 0
  local stack_size = 0
  local ordered = {}
  for k, v in pairs(item_list) do
    count = count + 1
    total_capacity = total_capacity + (v.stackMax or 1)
    total_present = total_present + (v.stack or 1)
    stack_size = v.stackMax
    table.insert(ordered, k)
  end
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
      Command.Item.Move(backslot, frontslot)
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

function lbag.merge(baggish)
  local item_list = lbag.iterate(baggish, function(item) return item.stack ~= item.stackMax end)
  local item_lists = {}
  for k, v in pairs(item_list) do
    item_lists[v.type] = item_lists[v.type] or {}
    item_lists[v.type][k] = v
  end
  local improved = false
  for k, v in pairs(item_lists) do
    if lbag.merge_one_item(v) then
      improved = true
    end
  end
  if not improved then
    lbag.printf("No room for improving stacking.")
  end
end

lbag.already_filtered = {}

function lbag.expand_baggish(baggish)
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
  else
    return Inspect.Item.Detail(baggish)
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

function lbag.split(item_name, split_into)
  lbag.printf("Unimplemented.")
end

