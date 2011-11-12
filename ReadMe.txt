What is this baggotry?

LibBaggotry is a suite of utility functions which I am making available
separately from the Baggotry addon in case someone else wants them.

Things you can do:

1.  Create "filters":

	f = Library.LibBaggotry.filter()

	f:include('name', 'roc orchid petals')
	f:include('category', 'collectible')
	f:exclude('stack', '1')
	f:include(func)

This creates a "filter" which will yield any objects which are named
roc orchid petals, or are tagged 'collectible', but which are in a stack
that isn't a stack of 1 (thus, a stack of 2 or more).

If you include or exclude a function, it should yield some kind of
description of what it thinks it does when called with a nil first
argument.  This is used for f:dump().  For instance, for the above,
you'd get:
	Includes:
	  name = roc orchid petals
	  category = collectible
	  <output of func(nil)>
	Excludes:
	  stack = 1

Filters work with slot specifiers; if none is provided, the filter can
have a default:

	f:slot(Utility.Item.Slot.Bank())

Or you can name it directly:
	f:find(Utility.Item.Slot.All())

The utilities are still being worked on, but:
	Library.LibBaggotry.find(baggish)
		Finds everything, yields a { slot = details } table.
	Library.LibBaggotry.iterate(baggish, func, aux)
		Calls func(details, slot, aux) for everything in baggish,
		returns a table of the ones for which func returned a truthy
		value (not false or nil)
	Library.LibBaggotry.first(baggish, func, aux)
		Calls func(details, slot, aux) for things in baggish
		returning { slot, details } for the first one it finds
		for which func returned a truthy value -- note that "first"
		is not particularly deterministic.

