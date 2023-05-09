<img align="left" width="100" height="100" src="doc/mimalloc-logo.png"/>

# Mimalloc-bench

&nbsp;

Suite for benchmarking malloc implementations, originally
developed for benchmarking [`mimalloc`](https://github.com/microsoft/mimalloc).
Collection of various benchmarks from the academic literature, together with
automated scripts to pull specific versions of benchmark programs and
allocators from Github and build them.

Due to the large variance in programs and allocators, the suite is currently
only developed for Unix-like systems.
The only system-installed allocator used is glibc's implementation that ships as part of Linux's libc.
All other allocators are downloaded and built as part of `build-bench-env.sh`.

Enjoy,
  Daan

Note that all the code in the `bench` directory is not part of
_mimalloc-bench_ as such, and all programs in the `bench` directory are
governed under their own specific licenses and copyrights as detailed in
their `README.md` (or `license.txt`) files. They are just included here for convenience.

# Benchmarking

The `build-bench-env.sh` script with the `all` argument will automatically pull
all needed benchmarks and allocators and build them in the `extern` directory:

```
~/dev/mimalloc-bench> ./build-bench-env.sh all
```

It starts installing packages and you will need to enter the sudo password.
All other programs are build in the `mimalloc-bench/extern` directory.
Use `./build-bench-env.sh -h` to see all options.

If everything succeeded, you can run the full benchmark suite (from `out/bench`) as:

- `~/dev/mimalloc-bench> cd out/bench`
- `~/dev/mimalloc-bench/out/bench>../../bench.sh alla allt`

Or just test _mimalloc_ and _tcmalloc_ on _cfrac_ and _larson_ with 16 threads:

- `~/dev/mimalloc-bench/out/bench>../../bench.sh --procs=16 mi tc cfrac larson`

Generally, you can specify the allocators (`mi`, `je`,
`tc`, `hd`, `sys` (system allocator)) etc, and the benchmarks
, `cfrac`, `espresso`, `barnes`, `lean`, `larson`, `alloc-test`, `cscratch`, etc.
Or all allocators (`alla`) and tests (`allt`).
Use `--procs=<n>` to set the concurrency, and use `--help` to see all supported
allocators and benchmarks.

## Current Allocators

Supported allocators are as follow, see
[build-bench-env.sh](https://github.com/daanx/mimalloc-bench/blob/master/build-bench-env.sh)
for the versions:

- **hd**: The [_Hoard_](https://github.com/emeryberger/Hoard) allocator by
  Emery Berger \[1]. This is one of the first multi-thread scalable allocators.
- **je**: The [_jemalloc_](https://github.com/jemalloc/jemalloc)
  allocator by [Jason Evans](https://github.com/jasone),
  now developed at Facebook
  and widely used in practice, for example in FreeBSD and Firefox.
- **mi**: The [_mimalloc_](https://github.com/microsoft/mimalloc) allocator.
  We can also test the debug version as **dmi** (this can be used to check for
  any bugs in the benchmarks), and the secure version as **smi**.
- **tc**: The [_tcmalloc_](https://github.com/gperftools/gperftools)
  allocator which comes as part of the Google performance tools,
  now maintained by the commuity.
- **sys**: The system allocator. Here we usually use the _glibc_ allocator
  (which is originally based on _Ptmalloc2_).

## Current Benchmarks

The first set of benchmarks are real world programs, or are trying to mimic
some, and consists of:

- **barnes**: a hierarchical n-body particle solver \[4], simulating the
  gravitational forces between 163840 particles. It uses relatively few
  allocations compared to `cfrac` and `espresso` but is multithreaded.
- **cfrac**: by Dave Barrett, implementation of continued fraction
  factorization, using many small short-lived allocations.
- **espresso**: a programmable logic array analyzer, described by
  Grunwald, Zorn, and Henderson \[3]. in the context of cache aware memory allocation.
- **gs**: have [ghostscript](https://www.ghostscript.com) process the entire
  Intel Software Developer’s Manual PDF, which is around 5000 pages.
- **leanN**:  The [Lean](https://github.com/leanprover/lean) compiler by
  de Moura _et al_, version 3.4.1,
  compiling its own standard library concurrently using N threads
  (`./lean --make -j N`). Big real-world workload with intensive
  allocations.
- **larsonN-sized**: by Larson and Krishnan \[2]. Simulates a server workload using 100 separate
   threads which each allocate and free many objects but leave some
   objects to be freed by other threads. Larson and Krishnan observe this
   behavior (which they call _bleeding_) in actual server applications,
   and the benchmark simulates this. Uses sized deallocation calls which
   have a fast path in some allocators.
- **lua**: compiling the [lua interpreter](https://github.com/lua/lua).

The second set of benchmarks are stress tests and consist of:

- **cache-scratch**: by Emery Berger \[1]. Introduced with the
  [Hoard](https://github.com/emeryberger/Hoard) allocator to test for
  _passive-false_ sharing of cache lines: first some small objects are
  allocated and given to each thread; the threads free that object and allocate
  immediately another one, and access that repeatedly. If an allocator
  allocates objects from different threads close to each other this will lead
  to cache-line contention.
- **glibc-simple** and **glibc-thread**: benchmarks for the [glibc](https://github.com/bminor/glibc/tree/master/benchtests).
- **malloc-large**: part of mimalloc benchmarking suite, designed
  to exercice large (several MiB) allocations.
- **rptest**: modified version of the [rpmalloc-benchmark](https://github.com/mjansson/rpmalloc-benchmark) suite.
- **mstress**: simulates real-world server-like allocation patterns, using N threads with with allocations in powers of 2  
  where objects can migrate between threads and some have long life times. Not all threads have equal workloads and
  after each phase all threads are destroyed and new threads created where some objects survive between phases.
- **sh6bench**: by [MicroQuill](http://www.microquill.com) as part of
  [SmartHeap](http://www.microquill.com/smartheap/sh_tspec.htm). Stress test
  where some of the objects are freed in a usual last-allocated, first-freed
  (LIFO) order, but others are freed in reverse order. Using the public
  [source](http://www.microquill.com/smartheap/shbench/bench.zip) (retrieved
  2019-01-02)
- **xmalloc-testN**: by Lever and Boreham \[5] and Christian Eder. We use the
  updated version from the
  [SuperMalloc](https://github.com/kuszmaul/SuperMalloc) repository. This is a
  more extreme version of the _larson_ benchmark with 100 purely allocating
  threads, and 100 purely deallocating threads with objects of various sizes
  migrating between them. This asymmetric producer/consumer pattern is usually
  difficult to handle by allocators with thread-local caches.

Finally, there is a
[security benchmark](https://github.com/daanx/mimalloc-bench/tree/master/bench/security)
aiming at checking basic security properties of allocators.

# References

- \[1] Emery D. Berger, Kathryn S. McKinley, Robert D. Blumofe, and Paul R. Wilson.
   _Hoard: A Scalable Memory Allocator for Multithreaded Applications_
   the Ninth International Conference on Architectural Support for Programming Languages and Operating Systems (ASPLOS-IX). Cambridge, MA, November 2000.
   [pdf](http://www.cs.utexas.edu/users/mckinley/papers/asplos-2000.pdf)

- \[2] P. Larson and M. Krishnan. _Memory allocation for long-running server applications_. In ISMM, Vancouver, B.C., Canada, 1998.
      [pdf](http://citeseemi.ist.psu.edu/viewdoc/download;jsessionid=5F0BFB4F57832AEB6C11BF8257271088?doi=10.1.1.45.1947&rep=rep1&type=pdf)

- \[3] D. Grunwald, B. Zorn, and R. Henderson.
  _Improving the cache locality of memory allocation_. In R. Cartwright, editor,
  Proceedings of the Conference on Programming Language Design and Implementation, pages 177–186, New York, NY, USA, June 1993.
  [pdf](http://citeseemi.ist.psu.edu/viewdoc/download?doi=10.1.1.43.6621&rep=rep1&type=pdf)

- \[4] J. Barnes and P. Hut. _A hierarchical O(n*log(n)) force-calculation algorithm_. Nature, 324:446-449, 1986.

- \[5] C. Lever, and D. Boreham. _Malloc() Performance in a Multithreaded Linux Environment._
  In USENIX Annual Technical Conference, Freenix Session. San Diego, CA. Jun. 2000.
  Available at <https://​github.​com/​kuszmaul/​SuperMalloc/​tree/​master/​tests>
