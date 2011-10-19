= DataGraph Paths

DataGraph was originally designed to limit access to models via a generic API.  At one URL users could access one subset of fields, at another URL users could access a different subset of fields.  In addition to solving the eager loading problem, DataGraph provided an easy way define and perform filtering at each endpoint.  Here's how.

A 'graph' of data can be normalized into call paths.  These are the paths that return data in the example:

  graph.paths # => ['a', 'b', 'c', 'assoc.x', 'assoc.y']

Paths outside of this list (like 'assoc.z') are not guaranteed to return any information.  Therefore these paths act as a whitelist defining what can be accessed from this graph.  Query parameters can be normalized to paths and compared vs the graph paths to determine if they're all allowed.



