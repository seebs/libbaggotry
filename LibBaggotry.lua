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

local info, lbag = ...
Library = Library or {}
Library.LibBaggotry = lbag
lbag.version = "VERSION"
local filt = Library.LibEnfiltrate

local printf = Library.printf.printf
local printfhs = Library.printf.printfhs
local sprintf = Library.printf.sprintf

function lbag.variables_loaded(event, name)
  if name == 'LibBaggotry' then
    LibBaggotryGlobal = LibBaggotryGlobal or {}
    LibBaggotryAccount = LibBaggotryAccount or {}
  end
  LibBaggotryAccount.settings = LibBaggotryAccount.settings or {}
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
	red = 'transcendent',
}
lbag.rarity_color_table = { sellable = { r = .34375, g = .34375, b = 34375 },
	common = { r = .98, g = .98, b = .98 },
	uncommon = { r = 0, g = .797, b = 0 },
	rare = { r = .148, g = .496, b = .977 },
	epic = { r = .676, g = .281, b = .98 },
	relic = { r = 1, g = .5, b = 0 },
	transcendent = { r = .8, g = 0, b = 0 },
	quest = { r = 1, g = 1, b = 0 },
}

lbag.bestpony = { 'sellable', 'common', 'uncommon', 'rare', 'epic', 'relic', 'transcendent', 'quest' }

lbag.command_queue = {}
lbag.need_update = false

function lbag.dump_item(item, slotspec)
  local prettystack
  if item.stackMax and item.stackMax > 1 then
    prettystack = string.format(" [%d/%d]", item.stack or 1, item.stackMax)
  else
    prettystack = ""
  end
  local whose
  if item._character and item._character ~= lbag.whoami() then
    whose = item._character .. ': '
  else
    whose = ''
  end
  printf("%s%s: %s%s", whose, item._slotspec or slotspec, item.name, prettystack)
end

function lbag.slot_updated()
  lbag.need_update = true
end

function lbag.computed_stack_size(item, stack_size)
  local max = (item.stackMax or 1)
  if not stack_size then
    return max
  elseif stack_size < 1 then
    stack_size = max + stack_size
  end
  if stack_size > max or stack_size < 1 then
    return false
  end
  return stack_size
end

function lbag.stack_one_item(item_list, stack_size, verbose)
  local count = 0
  did_something = false
  local match_us_up = {}
  local matches_left = 0
  local ordered = {}
  local max_stack
  local real_size
  local stacks = 0
  local total_items = 0
  local what_is_it
  for k, v in pairs(item_list) do
    what_is_it = v.name
    max_stack = max_stack or v.stackMax or 1
    stacks = stacks + 1
    total_items = total_items + (v.stack or 1)
    if not real_size then
      real_size = lbag.computed_stack_size(v, stack_size)
      if not real_size then
	printf("Can't handle stack size of %s for %s.", tostring(stack_size), what_is_it)
        return false
      end
    end
  end
  stack_size = real_size
  -- nothing to do; don't need to split, and only have one stack
  if stacks < 2 and total_items < stack_size then
    return false
  end
  printf("Stacking %s to %d.", what_is_it or "something unknown", stack_size)
  for k, v in pairs(item_list) do
    local stack = v.stack or 1
    max_stack = max_stack or v.stackMax or 1
    while stack > stack_size do
      lbag.queue(Command.Item.Split, v._slotspec, stack_size)
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
	printf("Over a hundred steps, giving up.")
	return did_something
      end
      --[[ note:  "ordered" isn't a specific order; rather, it's ANY
	order at all so that we can do "the first one". ]]
      local first = ordered[1]
      local second = ordered[2]
      if not match_us_up[first] then
        printf("error, match_us_up1[%s] is nil", first)
      end
      if not match_us_up[second] then
        printf("error, match_us_up2[%s] is nil", second)
      end
      lbag.queue(Command.Item.Move, match_us_up[first]._slotspec, match_us_up[second]._slotspec)
      count = count + 1
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
	lbag.queue(Command.Item.Split, match_us_up[second]._slotspec, stack_size)
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
    printf("Stacking items to %d took %d move%s.", stack_size, count, count ~= 1 and "s" or "")
  end
  -- we may have things which were left over
  return did_something
end

function lbag.stack_full_p(item, slotspec, stack_size)
  if stack_size then
    stack_size = lbag.computed_stack_size(item, stack_size)
    return (item.stack or 1) == stack_size
  else
    return item.stack == item.stackMax
  end
end

function lbag.stack(baggish, stack_size, verbose)
  local item_list = lbag.expand(baggish, true)
  local item_lists = {}
  local item_counts = {}
  local item_slots = {}
  local item_stack_sizes = {}
  local total_considered = 0
  local types_considered = 0
  for k, v in pairs(item_list) do
    -- ignore things with a max stack of 1
    if (v.stackMax or 1) ~= 1 then
      item_lists[v.type] = item_lists[v.type] or {}
      item_lists[v.type][v._slotspec] = v
      total_considered = total_considered + 1
    end
  end
  local improved = false
  for k, v in pairs(item_lists) do
    types_considered = types_considered + 1
    local slot, item = next(v)
    local real_size = lbag.computed_stack_size(item, stack_size)
    local count = 0
    local slots = 0
    local discard = {}
    -- discard stacks which are already of the expected size
    for slot, item in pairs(v) do
      -- printf("Considering %s [%s, %d]",
        -- slot, item.name, item.stack or -1)
      if lbag.stack_full_p(item, item._slotspec, real_size) then
	discard[#discard + 1] = slot
      else
        count = count + (item.stack or 1)
	slots = slots + 1
      end
    end
    -- no point in stacking unless either:
    -- 1. There's more than one stack that isn't currently of the right size.
    -- 2. There's only one such stack, and it's bigger than the right size.
    -- printf("%s: %d slot, %d count, stack %d, %d ignored",
      -- item.name, slots, count, real_size, #discard)
    if slots > 1 or count > real_size then
      -- ignore stacks that are already right
      for i = 1, #discard do
        v[discard[i]] = nil
	printf("Ignoring %s as it is already of the right size.", discard[i])
      end
      if lbag.stack_one_item(v, stack_size, verbose) then
	improved = true
      end
    end
  end
  printf("Considered %d total item%s (%d distinct type%s), %s.",
    total_considered, total_considered ~= 1 and "s" or "",
    types_considered, types_considered ~= 1 and "s" or "",
    improved and "improved stacking" or "nothing to do")
end

function lbag.move_items(baggish, slotspec, swap_items)
  -- the items we'd like to move...
  local item_list = lbag.expand(baggish, true)
  if not item_list then
    printf("Error, couldn't find any items to move.")
  end
  if not lbag.slotspec_p(slotspec) then
    printf("Error, got invalid slotspec '%s', can't move things to it.", slotspec)
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

function lbag.rarity_color(rarity, html)
  _, _, rgb = lbag.rarity_p(rarity, true)
  if not rgb then
    rgb = { r = 0.8, g = 0.8, b = 0.8 }
  end
  if html then
    rgb.html = sprintf("%02x%02x%02x", rgb.r * 255, rgb.g * 255, rgb.b * 255)
  end
  return rgb
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
  local ok, v1, v2, v3 = pcall(function() return Utility.Item.Slot.Parse(slotspec) end)
  if not ok then
    return false
  end
  return slotspec, character, v1, v2, v3
end

local function capitalize(s)
  if type(s) ~= 'string' then
    s = tostring(s)
  end
  return s:sub(1, 1):upper() .. s:sub(2, -1)
end

lbag.slot_name_lookups = {
  bank = 'Bank Bags',
  vault = 'Bank Vault',
}

function lbag.slotspec_pretty(input_slotspec)
  local slotspec, charspec, v1, v2, v3 = lbag.slotspec_p(input_slotspec)
  if slotspec then
    -- typically, something like "bank, 2, 22", or "equipment, slotname"
    if v1 == 'equipment' then
      return capitalize(v2)
    else
      if v2 == 'bag' then
        v1 = capitalize(v1) .. ' Bag'
      else
        v1 = lbag.slot_name_lookups[v1] or capitalize(v1)
      end
      return v1
    end
  else
    return 'Unknown'
  end
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

-- add a character spec to either a single slot or a table of slots.
function lbag.add_charspec(slotspec, charspec)
  if charspec and #charspec > 0 then
    if charspec:sub(-1, -1) ~= ':' then
      charspec = charspec .. ':'
    end
    if type(slotspec) == 'table' then
      for k, v in pairs(slotspec) do
        slotspec[k] = charspec .. slotspec[k]
      end
    elseif type(slotspec) == 'string' then
      return charspec .. slotspec
    end
  end
  return slotspec
end

function lbag.default_slotspec(charname)
    local slotspec = { Utility.Item.Slot.Inventory(), Utility.Item.Slot.Vault(), Utility.Item.Slot.Bank() }
    lbag.add_charspec(slotspec, charname)
    return slotspec
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
      printf("Encountered filter loop, returning empty set.")
      return {}
    else
      lbag.already_filtered[baggish] = true
      local slotspec = baggish.userdata.slotspec or lbag.default_slotspec()
      retval = lbag.expand(slotspec)
      retval = baggish:filter(retval)
      lbag.already_filtered[baggish] = false
    end
  elseif type(baggish) == 'table' then
    -- could be a few things
    for k, v in pairs(baggish) do
      if lbag.slotspec_p(v) then
        local some_items = lbag.expand(v)
	local count = 0
	for k2, v2 in pairs(some_items) do
	  count = count + 1
	  retval[k2] = v2
	end
      elseif type(k) == 'string' and type(v) == 'table' then
        -- a string:table pair is probably already good
	-- this doesn't check for slotspecs because the output of
	-- merge_items doesn't use slotspecs as keys
	retval[k] = v
      else
        printf("Unknown table item %s => %s", tostring(k), tostring(v))
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
        printf("No can do:  Can't use alts with this function.")
	retval = {}
      else
        retval = lbag.char_item_details(character, slotspec)
      end
    else
      retval = lbag.char_item_details(whoami, slotspec)
    end
  else
    printf("Couldn't figure out what %s was.", tostring(baggish))
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
    printf("No matches.")
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
  if lbag.need_update then
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
    global_or_account[shard][whoami].inventory = Inspect.Item.Detail(Utility.Item.Slot.All())
    lbag.need_update = false
  end
  if lbag.command_queue[1] then
    local func_args = lbag.command_queue[1]
    local func = func_args[1]
    if not func then
      printf("Huh?  Got nil func.  Ignoring it.")
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
  local seen = {}
  local shard = lbag.shard()
  char = string.lower(char)
  if LibBaggotryAccount[shard] then
    for k, v in pairs(LibBaggotryAccount[shard]) do
      if k == char or (char == '*' and Library.LibAccounts.available_p(k)) then
	if not seen[k] then
	  chars[#chars + 1] = k
	end
      end
    end
  end
  if LibBaggotryGlobal[shard] then
    for k, v in pairs(LibBaggotryGlobal[shard]) do
      if k == char or (char == '*' and Library.LibAccounts.available_p(k)) then
	if not seen[k] then
	  chars[#chars + 1] = k
	end
      end
    end
  end
  return chars
end

-- you gotta caaaaaaare, you gotta shaaaaaaaare
function lbag.share_inventory_p()
  local whoami = lbag.whoami()
  local shard = lbag.shard()
  if LibBaggotryAccount.settings[shard] and LibBaggotryAccount.settings[shard][whoami] then
    return LibBaggotryAccount.settings[shard][whoami].share_inventory
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

local whoami

function lbag.whoami()
  if not whoami then
    local me = Inspect.Unit.Detail("player")
    if me then
      whoami = string.lower(me.name)
    end
  end
  return whoami or "Unknown"
end

function lbag.share_inventory(sharing)
  local was_sharing
  local whoami = lbag.whoami()
  local shard = lbag.shard()
  LibBaggotryAccount.settings[shard] = LibBaggotryAccount.settings[shard] or {}
  LibBaggotryAccount.settings[shard][whoami] = LibBaggotryAccount.settings[shard][whoami] or {}
  was_sharing = LibBaggotryAccount.settings[shard][whoami].share_inventory
  LibBaggotryAccount.settings[shard][whoami].share_inventory = sharing
  if sharing ~= was_sharing then
    if was_sharing then
      LibBaggotryAccount[shard] = LibBaggotryAccount[shard] or {}
      LibBaggotryAccount[shard][whoami] = LibBaggotryAccount[shard][whoami] or {}
      LibBaggotryAccount[shard][whoami].inventory = Inspect.Item.Detail(Utility.Item.Slot.All())
      LibBaggotryGlobal[shard] = LibBaggotryGlobal[shard] or {}
      LibBaggotryGlobal[shard][whoami] = LibBaggotryGlobal[shard][whoami] or {}
      LibBaggotryGlobal[shard][whoami].inventory = nil
    else
      LibBaggotryGlobal[shard] = LibBaggotryGlobal[shard] or {}
      LibBaggotryGlobal[shard][whoami] = LibBaggotryGlobal[shard][whoami] or {}
      LibBaggotryGlobal[shard][whoami].inventory = Inspect.Item.Detail(Utility.Item.Slot.All())
      LibBaggotryAccount[shard] = LibBaggotryAccount[shard] or {}
      LibBaggotryAccount[shard][whoami] = LibBaggotryAccount[shard][whoami] or {}
      LibBaggotryAccount[shard][whoami].inventory = nil
    end
  end
  return sharing
end

function lbag.char_inventory(character)
  -- this is useful because 'character' might have been '*'
  local char_list = lbag.find_chars(character)
  local shard = lbag.shard()
  local retval = {}
  for _, charname in ipairs(char_list) do
    local more_items = {}
    if LibBaggotryAccount[shard] and LibBaggotryAccount[shard][charname] and LibBaggotryAccount[shard][charname].inventory then
      more_items = LibBaggotryAccount[shard][charname].inventory
    elseif LibBaggotryGlobal[shard] and LibBaggotryGlobal[shard][charname] then
      more_items = LibBaggotryGlobal[shard][charname].inventory or {}
    end
    local count = 0
    for k, v in pairs(more_items) do
      count = count + 1
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
    charspec = args.C
    args.C = nil
  else
    charspec = ''
  end
  -- use "owned" by default instead of defaulting to
  -- inventory only, because inventory-only is almost never what you want.
  if not args.s then
    args.s = "owned"
  end
  slotspec = args.s
  args.s = nil
  if slotspec == 'inventory' then
    slotspec = Utility.Item.Slot.Inventory()
  elseif slotspec == 'bank' then
    slotspec = Utility.Item.Slot.Bank()
  elseif slotspec == 'equip' or slotspec == 'equipment' then
    slotspec = Utility.Item.Slot.Equipment()
  elseif slotspec == 'vault' then
    slotspec = Utility.Item.Slot.Vault()
  elseif slotspec == 'quest' then
    slotspec = Utility.Item.Slot.Quest()
  elseif slotspec == 'wardrobe' then
    slotspec = Utility.Item.Slot.Wardrobe()
  elseif slotspec == 'guild' then
    slotspec = Utility.Item.Slot.Guild()
  elseif slotspec == 'owned' then
    slotspec = lbag.default_slotspec()
  elseif slotspec == 'all' then
    slotspec = Utility.Item.Slot.All()
  end
  if charspec then
    slotspec = lbag.add_charspec(slotspec, charspec)
  end
  filter.userdata.slotspec = slotspec
  return true
end

Command.Event.Attach(Event.Item.Slot, lbag.slot_updated, "slot update hook")
Command.Event.Attach(Event.Item.Update, lbag.slot_updated, "item update hook")
Command.Event.Attach(Event.Addon.SavedVariables.Load.End, lbag.variables_loaded, "variables loaded hook")
Command.Event.Attach(Event.System.Update.Begin, lbag.runqueue, "command queue hook")
