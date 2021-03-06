What is this baggotry?

LibBaggotry is a suite of utility functions which I am making available
separately from the Baggotry addon in case someone else wants them.  I'm
also trying to use them in a GUI addon that isn't going very well.

The central concept is the "baggish".  A baggish is a thing which can be
reasonably understood to denote a set of inventory items.  That could be:

	* True:  All items.
	* False:  No items.
	* One or more slotspecs: Those items
	* A filter:  The items picked by that filter
	* A table of { slotspec = details } pairs:  Those pairs.

In all cases, the return should be a table of { slotspec: details } pairs,
which is, of course, still a baggish.

As a side note, "slotspec" in LibBaggotry is fancier than "slotspec" in
the rest of the game.  A slotspec can be of the form
	char:slot
where "char" is a character name or "*", and "slot" is a slot specifier
of the form generated by Utility.Item.Slot.*().

Filters are now handled by LibEnfiltrate.  However, LibBaggotry uses
the .userdata component of a filter to store character/slot information;
if .userdata.slotspec exists, it is used, otherwise the default is
to search the current character's inventory.


BAGGROUND PROCESSING (tm):

When a LibBaggotry function needs to perform many operations, it performs
one per update rather than spamming them all at once.  If you have a
cheapish video card, this should avoid the command throttle for you!  :)


The utilities are still being worked on, but:
	Library.LibBaggotry.expand(baggish, disallow_alts)
		Finds everything, yields a { slot = details } table.
	Library.LibBaggotry.iterate(baggish, func, value, aux)
		Loop over baggish, doing
			value = func(details, slot, value, aux)
		and return value at the end.  Returns value, count,
		where count is the number of items iterated.
	Library.LibBaggotry.select(baggish, func, aux)
		Calls func(details, slot, aux) for everything in baggish,
		returns a table of the ones for which func returned a truthy
		value (not false or nil).  This is logically equivalent
		to, if baggish were a filter, doing :require(func, aux),
		except that LibEnfiltrate won't let you :require a function
		directly.
	Library.LibBaggotry.reject(baggish, func, aux)
		Like iterate, but takes things for which func returns
		false/nil.
	Library.LibBaggotry.first(baggish, func, aux)
		Calls func(details, slot, aux) for things in baggish
		returning { slot: details } for the first one it finds
		for which func returned a truthy value -- note that "first"
		is not particularly deterministic.
	Library.LibBaggotry.stack(baggish, size, verbose)
		Attempts to merge everything in baggish into stacks of
		at least size, defaulting to the maximum stack size.  Smart
		enough to not try to merge things that aren't actually
		of the same type.  (Used to be separate split and merge
		functions, but now they're the same.)  A stack size of
		0 means stackMax, and negative numbers are less than
		stackMax; for instance, splitting runes to -3 will
		actually split them to 17.  If you ever use the negative
		number case, please let me know, I'm so curious.
	Library.LibBaggotry.slotspec_p(slotspec)
		Returns true if 'slotspec' is a valid slotspec.  As a
		bonus feature, if slotspec is of the form
			char_identifier:slotspec
		yields slotspec, character so you can do
		fancy things like look in other inventories.
	Library.LibBaggotry.rarity_p(rarity, permissive)
		Returns a non-nil/false value if 'rarity' is a valid rarity
		In fact, returns three values in such cases;
			quality, name, { r, g, b }
		The quality is a value starting at 1 for trash and
		increasing monotonically, the name is a canonicalized name,
		and 'permissive' controls whether rarity_p tries to
		translate non-standard names such as 'purple' or 'white'.
		(The returned name is canonicalized.)  Ordering is:
			sellable
			common
			uncommon
			rare
			epic
			relic
			quest
	Library.LibBaggotry.queue(func, args)
		Appends func to the Bagground Processing (SM) queue.
		Items registered this way are processed, one per frame,
		in the order they were queued.  The argument list is
		stored and passed in when the function is invoked.
	Library.LibBaggotry.known_char(string)
		Indicates whether string is the name of a known character.
	Library.LibBaggotry.rarity_color(rarity)
		returns r, g, b
	Library.LibBaggotry.merge_items(baggish)
		Returns a merged list in which stacks of the same item
		are combined, with _character, _slotspec, etc. updated
		suitably.  Keys will be item type, rather than slots.
	Library.LibBaggotry.move_items(baggish, slotspec, replace_items)
		Move items from baggish into slots described by slotspec.
		If replace_items is truthy, will swap items into places that
		contain items not matching baggish.
		(If baggish is a filter, this is defined by filter.match,
		if baggish is a list of items, it'd be items that are in
		baggish.)
		Note that bags themselves (sibg, sbbg) are filtered out
		from both ends of this.
	Library.LibBaggotry.argstring()
		Returns a string of known options, currently:
			C	charspec
			s	slotspec
	Library.LibBaggotry.apply_args(filter, args)
		Applies C and s args (as above) to a filter, removing
		them from the args table.
