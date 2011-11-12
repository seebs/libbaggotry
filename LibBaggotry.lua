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

local bag = {}
Library = Library or {}
Library.LibBaggotry = bag
bag.version = "VERSION"

function bag.printf(fmt, ...)
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
  	slotspec = Utility.Item.Slot.All(),
	includes = {},
	excludes = {}
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

function Filter:dump(slotspec)
  bag.printf("Filter: slotspec %s", slotspec or self.slotspec)
  bag.printf("  Includes:")
  for _, v in ipairs(self.includes) do
    matchish, value = v()
    bag.printf("    %s = %s", matchish, value)
  end
  bag.printf("  Excludes:")
  for _, v in ipairs(self.excludes) do
    matchish, value = v()
    bag.printf("    %s = %s", matchish, value)
  end
end

function Filter:find(slotspec)
  all_keys = Inspect.Item.List(slotspec or self.slotspec)
  all_items = Inspect.Item.Detail(slotspec or self.slotspec)
  return_items = {}
  -- Because I think item ID should be in there somewhere
  for slot, item in pairs(all_items) do
    item.id = all_keys[slot].id
    if self:match(item) then
      return_items[slot] = item
    end
  end
  return return_items
end

function Filter:slot(slotspec)
  self.slotspec = slotspec
end

function Filter:match(item)
  if self.excludes then
    for _, v in pairs(self.excludes) do
      if v(item) then
        return false
      end
    end
  end
  if self.includes then
    for _, v in pairs(self.includes) do
      if v(item) then
        return true
      end
    end
  else
    return true
  end
end

-- note:  you can specify other filters!
function Filter:include(matchish, value)
  local newfunc = Filter:make_matcher(matchish, value)
  if newfunc then
    table.insert(self.includes, newfunc)
  end
end

function Filter:exclude(matchish)
  local newfunc = Filter:make_matcher(matchish, value)
  if newfunc then
    table.insert(self.excludes, newfunc)
  end
end

--[[ The actual matching function

  Full of special cases and knowledge...
  ]]
function Filter:matcher(item, matchish, value)
  local contain = false
  if not item then
    return matchish, value
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
    bag.printf("Can't make matchers from tables yet.")
    return nil
  elseif match_type == 'string' then
    -- for now, assume that it's the name of a field, and
    -- that value is the thing to match it to
    if type(value) == 'string' then
      value = string.lower(value)
    end
    -- closure to stash matchish and value
    return function(item)
      return Filter:matcher(item, matchish, value)
    end
  else
    bag.printf("Unknown match specifier, type '%s'", match_type)
    return nil
  end
end

-- and expose a little tiny bit of that:
function bag.filter()
  return Filter:new()
end

function bag.dump_item(item, slotspec)
  local prettyslot = ""
  if slotspec then
    prettyslot = slotspec .. ":" .. Utility.Item.Slot.Parse(slotspec)
  end
  bag.printf("%sItem: %s [%d]", prettyslot, item.name, item.stack or 1)
end

function bag.expand_baggish(baggish)
  if Filter:is_a(baggish) then
    return baggish:find()
  else
    return Inspect.Item.Detail(baggish)
  end
end

function bag.dump(baggish)
  local item_list = bag.expand_baggish(baggish)
  for k, v in pairs(item_list) do
    bag.dump_item(v, k)
  end
end

function bag.find(item_name)
  local found = 0
  local slots = {}
  if not item_name then
    return found, slots
  end
  for slot, v in pairs(Inspect.Item.Detail("si")) do
    if string.match(v['name'], item_name) then
      table.insert(slots, slot)
      if v['stack'] then
        found = found + v['stack']
      else
        found = found + 1
      end
    end
  end
  table.sort(slots)
  return found, slots
end

function bag.scratch_slot()
  for k, v in pairs(Inspect.Item.List("si")) do
    if v == false then
      return k
    end
  end
  return false
end

function bag.merge(item_name, slots)
  -- first, figure out whether we CAN merge them.
  local remove_us = {}
  local details = {}
  local keep_slots = {}
  local stack_size
  local found_items = 0
  local found_slots = 0
  for i, v in ipairs(slots) do
    local this_item = Inspect.Item.Detail(v)
    if this_item then
      if this_item.name == item_name then
	if not stack_size then
	  stack_size = this_item.stackMax or 1
	  if stack_size < 2 then
	    bag.printf("Can't merge items which don't stack.")
	    return
	  end
	end
	local stack = this_item.stack or 1
	-- we ignore full stacks, as they're irrelevant to a merge
	if stack < stack_size then
	  details[v] = this_item
	  table.insert(keep_slots, v)
	  found_slots = found_slots + 1
	  found_items = found_items + stack
	end
      end
    end
  end
  if table.getn(keep_slots) == 0 then
    bag.printf("Ended up with no slots that can be merged.")
    return
  end
  local needed = math.ceil(found_items / stack_size)
  bag.printf("%s: Found %d in %d slot%s (need %d).", item_name, found_items,
  	found_slots,
	(found_slots == 1) and "" or "s",
	needed)
  if needed > found_slots then
    return
  end
  -- if we got here, we think we could eliminate at least one slot.
  -- local scratch = bag.scratch_slot()


  bag.printf("Unimplemented.")
end

function bag.split(item_name, split_into)
  bag.printf("Unimplemented.")
end

