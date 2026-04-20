# A simple Web Prolog proof of concept

This directory contains a small proof-of-concept implementation of Web
Prolog, written to make the core ideas easy to read and easy to port.
It is intentionally smaller than the more complete Trinity codebase.

The current PoC consists of:

- `actors.pl` for Erlang-style actor primitives
- `toplevel_actors.pl` for shell-style toplevel processes
- `node.pl` for a small stateless HTTP API
- `rpc.pl` for client-side HTTP RPC
- `tests.pl` for the regression suite

The implementation is deliberately incomplete. In particular, it does
not implement the `node` option or the `load_*` options.

## Requirements

Install a recent [SWI-Prolog](https://www.swi-prolog.org/download/devel)
for your platform.

## Running the tests

From this directory:

```text
$ cd simple-node
$ swipl
```

Then:

```prolog
?- [tests].
true.

?- t.
```

All tests should pass.

You can also run the whole suite directly from the shell:

```text
$ swipl -q -g "['tests.pl'], t, halt."
```

## Running a node

Start SWI-Prolog in this directory and load the node and RPC modules:

```prolog
?- [node, rpc, toplevel_actors].
true.
```

Then start a node on port `3010`:

```prolog
?- node(3010).
true.
```

There is no startup banner at the moment, but the HTTP server is then
running on `http://localhost:3010/`.

**Warning:** do not expose this node to the public internet in its
current form.

## Trying the HTTP API

The node currently only implements the `prolog` answer format. If you
omit `format=prolog`, the default response is:

```text
JSON output is not yet implemented
Use format=prolog
```

Try this in a browser:

[http://localhost:3010/call?goal=member(X,[a,b])&format=prolog](http://localhost:3010/call?goal=member(X,[a,b])&format=prolog)

You should see:

```text
success([member(a,[a,b]),member(b,[a,b])],false).
```

Then try:

[http://localhost:3010/call?goal=member(X,[a,b])&template=X&offset=0&limit=1&format=prolog](http://localhost:3010/call?goal=member(X,[a,b])&template=X&offset=0&limit=1&format=prolog)

and you should get:

```text
success([a],true).
```

Then try the same query with `offset=1`:

[http://localhost:3010/call?goal=member(X,[a,b])&template=X&offset=1&limit=1&format=prolog](http://localhost:3010/call?goal=member(X,[a,b])&template=X&offset=1&limit=1&format=prolog)

which should give:

```text
success([b],false).
```

## Trying `rpc/2-3`

With the node still running:

```prolog
?- rpc('http://localhost:3010', member(X, [a,b])).
X = a ;
X = b.
```

And:

```prolog
?- rpc('http://localhost:3010', member(X, [a,b]), [limit(1)]).
X = a ;
X = b.
```

The point of the paged implementation is that it avoids spurious
recomputation. For example:

```prolog
?- time(rpc('http://localhost:3010', (sleep(1), X=foo ; X=bar), [limit(1)])).
X = foo ;
X = bar.
```

The first answer should take about one second, while the second should
arrive almost immediately because the node continues from a cached
toplevel instead of recomputing the delayed first branch.

## Using the Prolog shell as a client

You can also use the ordinary Prolog toplevel as a shell for a toplevel
actor:

```prolog
?- toplevel_spawn(Pid, [monitor(true)]).
Pid = <thread>(...).

?- toplevel_call($Pid, between(1,5,I), [
       template(I),
       limit(2)
   ]).
Pid = <thread>(...).

?- flush.
Shell got success(<thread>(...),[1,2],true)
true.

?- toplevel_next($Pid, [limit(10)]).
Pid = <thread>(...).

?- flush.
Shell got success(<thread>(...),[3,4,5],false)
Shell got down(<thread>(...),<thread>(...),true)
true.
```

Your actual thread identifiers will differ.

## Not implemented

Examples that currently do not work include:

1. examples that use the `node` option
2. examples that use the `load_*` options
3. JSON answers from the HTTP API
