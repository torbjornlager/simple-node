# A simple Web Prolog node

A runnable companion to the implementation appendix of the
[Trinity book](https://trinity.elfenbenstornet.se/book.html). The code keeps
actors, toplevel processes, stateless HTTP calls, and continuation caching
small enough to read together. The Trinity homepage links here under
[“A simple node”](https://trinity.elfenbenstornet.se/pocs.html).

- `actors.pl`: local actors, selective receive, guards, links, and monitors
- `toplevel_actors.pl`: resumable solution slices and toplevel control
- `node.pl`: a loopback HTTP endpoint with a bounded continuation cache
- `rpc.pl`: a nondeterministic HTTP client
- `term_wire.pl`: character-list text, portable terms, and canonical keys
- `tests.pl` and `regression_tests.pl`: actor, HTTP, RPC, and cleanup checks
- `parallel.pl`: small parallel actor examples

This teaching implementation runs trusted goals with the authority of its
SWI-Prolog process. Actors share host modules and the clause database. It
has no authentication, sandbox, private actor databases, distributed actor
transport, `node` or `load_*` spawn options, source installation, or JSON
answers. It does not claim conformance to a complete Web Prolog profile.
Use the [full node](https://github.com/torbjornlager/swi-prolog-node) for
those mechanisms. Keep this example on a trusted local machine.

## Requirements and tests

Use a recent threaded SWI-Prolog with `sig_atomic/1` and `findnsols/4`.
The suite has been checked with SWI-Prolog 10.1.18 on macOS, including the
standard application distribution. From this repository:

```sh
swipl -q -s tests.pl -g '(t -> halt(0); halt(1)).'
```

Alternatively, load `[tests].` in the Prolog shell and call `t.`. The suite
includes real HTTP requests and checks text decoding, literal `'$VAR'/1`
data, variable sharing, changed page sizes, pending errors after partial
pages, absence of lookahead, eviction, and interruption cleanup.

With `boken` cloned beside this repository, the printed appendix listings
can also be extracted and tested directly:

```sh
python3 ../boken/author/companions/implementation/check_examples.py
```

That script accepts `--swipl /path/to/swipl` and `--simple-node /path/to/simple-node`.

## Run a node

```prolog
?- [node, rpc, toplevel_actors].
true.
?- node(3010).
true.
```

The server binds to loopback. Run one node per Prolog process.

[All answers](http://localhost:3010/call?goal=member(X,%5Ba,b%5D)&template=X)
from `/call?goal=member(X,[a,b])&template=X`:

```prolog
success([a,b],false).
```

Add `limit=1` to request the first page:

```prolog
success([a],true).
```

Repeat with `offset=1&limit=1`:

```prolog
success([b],false).
```

The default format is `prolog`, with content type `application/x-prolog`.
Omitting `limit` collects all solutions. An explicit limit must be positive;
`offset` must be nonnegative. Double-quoted HTTP input denotes character
lists: `goal=X="ab"&template=X` returns `success([[a,b]],false).`
Cyclic terms, attributed variables, native strings, and opaque host values
are rejected at the answer boundary.

Stop the server and reclaim cached workers with:

```prolog
?- stop_node(3010).
true.
```

## Use RPC

With the node running:

```prolog
?- rpc('http://localhost:3010', member(X, [a,b]), [limit(1)]).
X = a ;
X = b.
```

Goal and template serialization preserves quoted atoms, literal `'$VAR'/1`
data, and variable sharing. For text in locally entered goals, use character
lists such as `[a,b]`, or set the caller's `double_quotes` flag to `chars`.
The HTTP parser applies `chars` independently of the caller's flag.

Paging avoids recomputation while the matching continuation remains cached:

```prolog
?- rpc('http://localhost:3010', (sleep(1), X=foo ; X=bar), [limit(1)]).
X = foo ;
X = bar.
```

The first answer takes about a second; the second resumes the suspended
query. No extra solution is evaluated to decide `More`. A partial page
followed by an exception is delivered before its pending error; the next
offset advances by the actual page length.

The cache holds at most 100 suspended workers by default, and eviction
terminates the worker. Requests own workers until they transfer them into
the cache; timeout or interruption reclaims an untransferred worker.
The page wait timeout defaults to 30 seconds. These settings are available
through `library(settings)` as `node:cache_size` and `node:timeout`.
Selective receive uses protected queue polls with sleeps outside the atomic
step; this adds up to about 10 ms of receive latency. There is no idle expiry: abandoned queries remain until eviction,
`node:clear_cache`, server shutdown through `stop_node/1`, or process exit.

After eviction, the same request replays the goal from its offset. Pure
goals with stable dependencies retain their answer sequence; changing data
and side effects can behave differently. There is no snapshot or
exactly-once guarantee.

## Try a toplevel actor

```prolog
?- toplevel_spawn(Pid, [monitor(true)]).
Pid = <thread>(...).
?- toplevel_call($Pid, between(1,5,I), [template(I),limit(2)]).
true.
?- flush.
Shell got success(<thread>(...),[1,2],true)
true.
?- toplevel_next($Pid, [limit(10)]).
true.
?- flush.
Shell got success(<thread>(...),[3,4,5],false)
Shell got down(<thread>(...),<thread>(...),true)
true.
```

Thread identifiers differ between runs. Unlike the full node, this local
actor example exposes host thread identifiers rather than wire-portable pids.
