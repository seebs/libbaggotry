--[[ LibBaggotry
     Bag utility functions

     The big thing here is the 'baggish', which is modeled very loosely
     conceptually on git's notion of a commit-ish, which is a thing which
     you could figure out to have been some kind of a commit.

     A baggish is one of a few things:
     1.  A table in which the values all look like item details.
     2.  A filter object (from LibEnfiltrate)
     3.  A slot specifier.

     Filters are inherited from LibEnfiltrate.

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
local filt = Library.LibEnfiltrate

function lbag.variables_loaded(name)
  if name == 'LibBaggotry' then
    LibBaggotryGlobal = LibBaggotryGlobal or {}
    LibBaggotryAccount = LibBaggotryAccount or {}
  end
end

lbag.color_rarity = {
	trash = 'sellable',
	grey = 'sellable',
	white = 'common',
	green = 'uncommon',
	blue = 'rare',
	purple = 'epic',
	orange = 'relic',
	yellow = 'quest',
}
lbag.rarity_color_table = { sellable = { r = .34375, g = .34375, b = 34375 },
	common = { r = .98, g = .98, b = .98 },
	uncommon = { r = 0, g = .797, b = 0 },
	rare = { r = .148, g = .496, b = .977 },
	epic = { r = .676, g = .281, b = .98 },
	relic = { r = 1, g = .5, b = 0 },
	-- no idea
	transcendant = { r = 1, g = 1, b = 1 },
	quest = { r = 1, g = 1, b = 0 },
}

lbag.bestpony = { 'sellable', 'common', 'uncommon', 'rare', 'epic', 'relic', 'transcendant', 'quest' }

lbag.command_queue = {}

function lbag.printf(fmt, ...)
  print(string.format(fmt or 'nil', ...))
end

function lbag.dump_item(item, slotspec)
  local prettystack
  if item.stackMax and item.stackMax > 1 then
    prettystack = string.format(" [%d/%d]", item.stack or 1, item.stackMax)
  else
    prettystack = ""
  end
  local whose
  if item._character and item._character ~= lbag.whoami then
    whose = item._character .. ': '
  else
    whose = ''
  end
  lbag.printf("%s%s: %s%s", whose, item._slotspec or slotspec, item.name, prettystack)
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

function lbag.stack_one_item(item_list, stack_size, verbose)
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
  lbag.printf("Stacking to %d.", stack_size)
  for k, v in pairs(item_list) do
    lbag.printf("Found %d items, slot %s.", v.stack or 1, v._slotspec)
  end
  for k, v in pairs(item_list) do
    local stack = v.stack or 1
    max_stack = max_stack or v.stackMax or 1
    while stack > stack_size do
      lbag.queue(Command.Item.Split, v._slotspec, stack_size)
      lbag.printf("Splitting %d off of [%s] %d.", stack_size, v._slotspec, stack)
      count = count + 1
      stack = stack - stack_size
      did_something = true
    end
    if stack > 0 and stack ~= stack_size then
      v.stack = stack
      match_us_up[v._slotspec] = v
      matches_left = matches_left + stack
      table.insert(ordered, k)
    end
    while table.getn(ordered) >= 2 do
      local removed = false
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
      lbag.queue(Command.Item.Move, match_us_up[first]._slotspec, match_us_up[second]._slotspec)
      count = count + 1
      did_something = true
      local s1 = match_us_up[first].stack
      local s2 = match_us_up[second].stack
      lbag.printf("Moving [%s] %d onto [%s] %d.", match_us_up[first]._slotspec, s1, match_us_up[second]._slotspec, s2)
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
	lbag.queue(Command.Item.Split, match_us_up[second]._slotspec, stack_size)
	lbag.printf("Splitting %d off of [%s] %d.", stack_size, match_us_up[second]._slotspec, match_us_up[second].stack)
        count = count + 1
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
  if verbose then
    lbag.printf("Stacking items to %d took %d moves.", stack_size, count)
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

function lbag.stack(baggish, stack_size, verbose)
  local item_list = lbag.expand(baggish, true)
  local item_lists = {}
  for k, v in pairs(item_list) do
    item_lists[v.type] = item_lists[v.type] or {}
    item_lists[v.type][v._slotspec] = v
  end
  local improved = false
  for k, v in pairs(item_lists) do
    if lbag.stack_one_item(v, stack_size, verbose) then
      improved = true
    end
  end
  if not improved then
    lbag.printf("No room for improving stacking.")
  end
end

function lbag.move_items(baggish, slotspec, swap_items)
  -- the items we'd like to move...
  local item_list = lbag.expand(baggish, true)
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
  local item_list = lbag.expand(baggish)
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
  local ok, val = pcall(function() Utility.Item.Slot.Parse(slotspec) end)
  if not ok then
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

function lbag.expand(baggish, disallow_alts)
  local retval = {}
  if baggish == false then
    return {}
  end
  if baggish == true then
    baggish = Utility.Item.Slot.All()
  end
  local whoami = lbag.whoami()
  if filt.Filter:filter_p(baggish) then
    if lbag.already_filtered[baggish] then
      lbag.printf("Encountered filter loop, returning empty set.")
      return {}
    else
      lbag.already_filtered[baggish] = true
      local slotspec = baggish.userdata.slotspec or Utility.Item.Slot.Inventory()
      retval = lbag.expand(slotspec)
      retval = baggish:filter(retval)
      lbag.already_filtered[baggish] = false
    end
  elseif type(baggish) == 'table' then
    -- could be a few things
    for k, v in pairs(baggish) do
      if lbag.slotspec_p(v) then
        local some_items = lbag.expand(v)
	for k2, v2 in pairs(some_items) do
	  retval[k2] = v2
	end
      elseif type(k) == 'string' and type(v) == 'table' then
        -- a string:table pair is probably already good
	-- this doesn't check for slotspecs because the output of
	-- merge_items doesn't use slotspecs as keys
	retval[k] = v
      else
        lbag.printf("Unknown table item %s => %s", tostring(k), tostring(v))
      end
    end
  elseif lbag.slotspec_p(baggish) then
    local slotspec, character = lbag.slotspec_p(baggish)
    if disallow_alts then
      if character == '*' then
        character = whoami
      end
    end
    if character and character ~= whoami then
      if disallow_alts then
        lbag.printf("No can do:  Can't use alts with this function.")
	retval = {}
      else
        retval = lbag.char_item_details(character, slotspec)
      end
    else
      retval = lbag.char_item_details(whoami, slotspec)
    end
  else
    lbag.printf("Couldn't figure out what %s was.", tostring(baggish))
    return {}
  end
  for k, v in pairs(retval) do
    v.stack = v.stack or 1
    v.rarity = v.rarity or 'common'
    local slotspec, character = lbag.slotspec_p(k)
    if not v._slotspec then
      v._slotspec = slotspec
    end
    if not v._character then
      v._character = character or whoami
    end
  end
  return retval
end

function lbag.dump(baggish)
  local item_list = lbag.expand(baggish)
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
  local item_list = lbag.expand(baggish)
  local count = 0
  for slot, item in pairs(item_list) do
    value = func(item, slot, value, aux)
    count = count + 1
  end
  return value, count
end

function lbag.select(baggish, func, aux)
  local item_list = lbag.expand(baggish)
  local return_list = {}
  for slot, item in pairs(item_list) do
    if func(item, slot, aux) then
      return_list[slot] = item
    end
  end
  return return_list
end

function lbag.reject(baggish, func, aux)
  local item_list = lbag.expand(baggish)
  local return_list = {}
  for slot, item in pairs(item_list) do
    if not func(item, slot, aux) then
      return_list[slot] = item
    end
  end
  return return_list
end

function lbag:first(baggish, func, aux)
  all_items = lbag.expand(aux)
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

function lbag.argstring()
  return "C:s:"
end

function lbag.apply_args(filter, args)
  local charspec, slotspec
  if not args.C and not args.s then
    return false
  end
  if args.C then
    charspec = args.C .. ':'
    args.C = nil
  else
    charspec = ''
  end
  if args.s then
    slotspec = args.s
    args.s = nil
    if slotspec == 'inventory' then
      slotspec = charspec .. Utility.Item.Slot.Inventory()
    elseif slotspec == 'bank' then
      slotspec = charspec .. Utility.Item.Slot.Bank()
    elseif slotspec == 'quest' then
      slotspec = charspec .. Utility.Item.Slot.Quest()
    elseif slotspec == 'wardrobe' then
      slotspec = charspec .. Utility.Item.Slot.Wardrobe()
    elseif slotspec == 'guild' then
      slotspec = charspec .. Utility.Item.Slot.Guild()
    elseif slotspec == 'owned' then
      slotspec = { charspec .. Utility.Item.Slot.Inventory(), charspec .. Utility.Item.Slot.Bank() }
    elseif slotspec == 'all' then
      slotspec = { charspec .. Utility.Item.Slot.Inventory(), charspec .. Utility.Item.Slot.Bank(), charspec .. Utility.Item.Slot.Equipment(), charspec .. Utility.Item.Slot.Quest(), charspec .. Utility.Item.Slot.Wardrobe() }
    else
      slotspec = charspec .. slotspec
    end
  else
    slotspec = charspec .. Utility.Item.Slot.Inventory()
  end
  filter.userdata.slotspec = slotspec
  return true
end

table.insert(Event.Item.Slot, { lbag.slot_updated, "LibBaggotry", "slot update hook" })
table.insert(Event.Item.Update, { lbag.slot_updated, "LibBaggotry", "slot update hook" })
table.insert(Event.Addon.SavedVariables.Load.End, { lbag.variables_loaded, "LibBaggotry", "variable loaded hook" })
table.insert(Event.System.Update.Begin, { lbag.runqueue, "LibBaggotry", "command queue hook" })
