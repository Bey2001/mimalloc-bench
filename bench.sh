#!/bin/bash
# Copyright 2018-2022, Microsoft Research, Daan Leijen, Julien Voisin, Matthew Parkinson


# --------------------------------------------------------------------
# Allocators and tests
# --------------------------------------------------------------------

readonly alloc_all="sys hd je mi tc my"
alloc_run=""           # allocators to run (expanded by command line options)
alloc_installed="sys"  # later expanded to include all installed allocators
alloc_libs="sys="      # mapping from allocator to its .so as "<allocator>=<sofile> ..."

readonly tests_all1="cfrac espresso barnes lean larson-sized mstress rptest gs lua"
# Omitted rocksdb and redis due to not being able to download them
readonly tests_all2="alloc-test sh6bench xmalloc-test cscratch glibc-simple glibc-thread"

readonly tests_all="$tests_all1 $tests_all2 $tests_all3 $tests_all4"
readonly tests_allt="$tests_all1 $tests_all2"  # run with 'allt' command option

tests_run=""
tests_exclude=""
readonly tests_exclude_macos="sh6bench"

# --------------------------------------------------------------------
# Environment
# --------------------------------------------------------------------

verbose="no"
ldpreload="LD_PRELOAD"
timecmd="$(type -P time)"  # the shell builtin doesn't have all the options we need
sedcmd=sed
darwin=""
extso=".so"
procs=8
repeats=1          # repeats of all tests
test_repeats=1     # repeats per test
sleep=0            # mini sleeps between tests seem to improve stability
case "$OSTYPE" in
  darwin*) 
    darwin="1"
    timecmd=gtime  # use brew install gnu-time
    extso=".dylib"
    ldpreload="DYLD_INSERT_LIBRARIES"
    libc=`clang --version | head -n 1`
    procs=`sysctl -n hw.physicalcpu`
    sedcmd=gsed;;
  *)
    libc=`ldd --version 2>&1 | head -n 1` || true
    libc="${libc#ldd }"
    if command -v nproc > /dev/null; then 
      procs=`nproc`
    fi;;
esac


# --------------------------------------------------------------------
# Check directories
# --------------------------------------------------------------------

readonly curdir=`pwd`
if ! test -f ../../build-bench-env.sh; then
  echo "error: you must run this script from the 'out/bench' directory!"
  exit 1
fi
if ! test -d ../../extern; then
  echo "error: you must first run `./build-build/bench.sh` (in `../..`) to install benchmarks and allocators."
  exit 1
fi

pushd "../../extern" > /dev/null # up from `mimalloc-bench/out/bench`
readonly localdevdir=`pwd`
popd > /dev/null
pushd "../../bench" > /dev/null
readonly benchdir=`pwd`
popd > /dev/null


# --------------------------------------------------------------------
# The allocator library paths
# --------------------------------------------------------------------
function alloc_lib_add {  # <allocator> <variable> <librarypath>
  alloc_libs="$1=$2 $alloc_libs"
}

readonly lib_rp="`find ${localdevdir}/rp/bin/*/release -name librpmallocwrap$extso 2> /dev/null`"
readonly lib_tbb="$localdevdir/tbb/bench_release/libtbbmalloc_proxy$extso"
readonly lib_tbb_dir="$(dirname $lib_tbb)"

alloc_lib_add "hd"     "$localdevdir/hd/src/libhoard$extso"
alloc_lib_add "je"     "$localdevdir/je/lib/libjemalloc$extso"
alloc_lib_add "tc"     "$localdevdir/tc/.libs/libtcmalloc_minimal$extso"
alloc_lib_add "mi"     "$localdevdir/mi/out/release/libmimalloc$extso"
### User entered here
alloc_lib_add "sam"    "$localdevdir/samalloc/libsamalloc$extso"

xmidir="$localdevdir/../../mi"
if ! [ -d "$xmidir" ]; then
  xmidir_ext="${xmidir}malloc"
  if [ -d "$xmidir_ext" ]; then 
    xmidir="$xmidir_ext";
  fi
fi

alloc_lib_add "xmi"    "$xmidir/out/release/libmimalloc$extso"

if test "$use_packages" = "1"; then
  if test -f "/usr/lib/libtcmalloc$extso"; then
    alloc_lib_add "tc"  "/usr/lib/libtcmalloc$extso"
  fi
  if test -f "/usr/lib/x86_64-linux-gnu/libtcmalloc$extso"; then
    alloc_lib_add "tc" "/usr/lib/x86_64-linux-gnu/libtcmalloc$extso"
  fi
fi

readonly luadir="$localdevdir/lua"
readonly leandir="$localdevdir/lean"
readonly leanmldir="$leandir/../mathlib"
readonly pdfdoc="$localdevdir/large.pdf" 

readonly spec_dir="$localdevdir/../../spec2017"
readonly spec_base="base"
readonly spec_bench="refspeed"
readonly spec_config="malloc-test-m64"


# --------------------------------------------------------------------
# Helper functions
# --------------------------------------------------------------------

function warning { # <message> 
  echo ""
  echo "warning: $1"
  echo ""
}

function contains {  # <string> <substring>   does string contain substring?
  for s in $1; do
    if test "$s" = "$2"; then
      return 0
    fi
  done
  return 1
}

function is_installed {  # <allocator>
  contains "$alloc_installed" $1
}

function alloc_run_add {  # <allocator>   :add to runnable
  alloc_run="$alloc_run $1"
}

function alloc_run_remove {   # <allocator>  :remove from runnables
  if contains "$alloc_run" "$1"; then
    alloc_run_old="$alloc_run"
    alloc_run=""
    for s in $alloc_run_old; do
      if [ "$s" != "$1" ]; then
        alloc_run_add "$s"
      fi
    done
  fi
}

function alloc_run_add_remove { # <allocator> <add?> 
  if test "$2" = "1"; then
    alloc_run_add "$1"
  else
    alloc_run_remove "$1"
  fi
}

# read in the installed allocators
while read word _; do alloc_installed="$alloc_installed ${word%:*}"; done < ${localdevdir}/versions.txt


alloc_lib=""
function alloc_lib_set {  # <allocator>
  for entry in $alloc_libs; do
    entry_name="${entry%=*}"
    entry_lib="${entry#*=}"
    if [ "$entry_name" = "$1" ]; then
      alloc_lib="$entry_lib"
      return 0
    fi
  done
  warning "cannot set library path for allocator $1"
  alloc_lib="lib$1.so"
}

function tests_run_add {  # <tests>   :add to runnable tests
  tests_run="$tests_run $1"
}

function tests_run_remove {   # <test>  :remove from runnable tests
  if contains "$tests_run" "$1"; then
    tests_run_old="$tests_run"
    tests_run=""
    for tst in $tests_run_old; do
      if [ "$tst" != "$1" ]; then
        tests_run_add "$tst"
      fi
    done
  fi
}

function tests_run_add_remove { # <test> <add?> 
  if test "$2" = "1"; then
    tests_run_add "$1"
  else
    tests_run_remove "$1"
  fi
}

if test "$darwin" = "1"; then
  # remove tests that don't run on darwin
  tests_exclude="$tests_exclude $tests_exclude_macos"
fi


if [ ! -f "${localdevdir}/lean/bin/lean" ]; then  # only run lean if it is installed (for CI)
  tests_exclude="$tests_exclude lean lean-mathlib"
fi


# --------------------------------------------------------------------
# Parse command line
# --------------------------------------------------------------------

while : ; do
  # set flag and flag_arg
  flag="$1"
  case "$flag" in
    *=*)  flag_arg="${flag#*=}"
          flag="${flag%=*}=";;
    no-*) flag_arg="0"
          flag="${flag#no-}";;
    none) flag_arg="0" ;;
    *)    flag_arg="1" ;;
  esac
  case "$flag_arg" in
    yes|on|true)  flag_arg="1";;
    no|off|false) flag_arg="0";;
  esac

  if contains "$alloc_all" "$flag"; then
    if ! contains "$alloc_installed" "$flag"; then
      warning "allocator '$flag' selected but it seems it is not installed ($alloc_installed)"
    fi
    alloc_run_add_remove "$flag" "$flag_arg"    
  else
    if contains "$tests_all" "$flag"; then
      tests_run_add_remove "$flag" "$flag_arg"
    else
      case "$flag" in
        "") break;;
        alla)
            # use all installed allocators (iterate to maintain order as specified in alloc_all)
            for alloc in $alloc_all; do 
              if is_installed "$alloc"; then
                alloc_run_add_remove "$alloc" "$flag_arg"
              fi
            done;;
        allt)
            for tst in $tests_allt; do
              tests_run_add_remove "$tst" "$flag_arg"
            done;;
        glibc)
            tests_run_add_remove "glibc-simple" "$flag_arg"
            tests_run_add_remove "glibc-thread" "$flag_arg";;
        spec=*)
            test_run_add "spec"
            run_spec_bench="$flag_arg";;
        -j=*|--procs=*)
            procs="$flag_arg";;
        -r=*)
            repeats="$flag_arg";;
        -n=*)
            test_repeats="$flag_arg";;
        -s=*|--sleep=*)
            sleep="$flag_arg";;
        -v|--verbose)
            verbose="yes";;
        -h|--help|-\?|help|\?)
            echo "./bench [options]"
            echo ""
            echo "options:"
            echo "  -h, --help                   show this help"  
            echo "  -v, --verbose                be verbose (=$verbose)"
            echo "  -j=<n>, --procs=<n>          concurrency level (=$procs)"
            echo "  -r=<n>                       number of repeats of the full suite (=$repeats)"
            echo "  -n=<n>                       number of repeats of each individual test (=$test_repeats)"
            echo "  -s=<n>, --sleep=<n>          seconds of sleep between each test (=$sleep)"
            echo ""
            echo "  allt                         run all tests"
            echo "  alla                         run all allocators"
            echo "  no-<test|allocator>          do not run specific <test> or <allocator>"   
            echo ""
            echo "allocators:"
            echo "  hd                           use hoard"
            echo "  je                           use jemalloc"
            echo "  mi                           use mimalloc"
            echo "  tc                           use tcmalloc (from gperftools)"
            echo "  my                           use samalloc (From ME)"
            echo ""
            echo "tests included in 'allt':"
            echo "  $tests_all1"
            echo "  $tests_all2"
            echo ""
            echo "installed allocators:"
            echo "  sys:    $libc"
            column -t "$localdevdir/versions.txt" | sed 's/^/  /'
            echo ""
            exit 0;;
        *) warning "unknown option \"$1\"." 1>&2
      esac
    fi
  fi
  shift
done

echo "benchmarking on $procs cores."
echo "use '-h' or '--help' for help on configuration options."
echo ""
export verbose



# --------------------------------------------------------------------
# Info
# --------------------------------------------------------------------

if test "$verbose" = "yes"; then
  echo "available tests: $verbose"
  echo "  $tests_all1"
  echo "  $tests_all2"
  echo "  $tests_all3 $tests_all4"
  echo ""
  echo "available allocators:"
  echo "  $alloc_all"
  echo ""
  echo "installed allocators:"
  echo "  sys:    $libc"
  column -t "$localdevdir/versions.txt" | sed 's/^/  /'
  echo ""
fi

for tst in $tests_exclude; do
  tests_run_remove "$tst"
done

echo "allocators: $alloc_run"
echo "tests     : $tests_run"
if [ ! -z "$tests_exclude" ]; then
  echo "(excluded tests: $tests_exclude)"
fi  

if [ -z "$tests_run" ]; then
  warning "no tests are specified."
  exit 1
fi
if [ -z "$alloc_run" ]; then
  warning "no allocators are specified."
  exit 1
fi  

readonly benchres="$curdir/benchres.csv"

procsx2=$((procs * 2))
procsx4=$((procs * 4))
procs_div2=$((procs / 2))
procs_max16=$((procs > 16 ? 16 : procs))

function set_spec_bench_dir {
  if test -f "$1.0000/compare.out"; then
    spec_bench_dir="$1.0000"
  elif test -f "$1.0001/compare.out"; then
    spec_bench_dir="$1.0001"
  elif test -f "$1.0002/compare.out"; then
    spec_bench_dir="$1.0002"
  elif test -f "$1.0003/compare.out"; then
    spec_bench_dir="$1.0003"
  else
    spec_bench_dir="$1.0004"
  fi
}


# --------------------------------------------------------------------
# Run a test
# --------------------------------------------------------------------
readonly allocfill="     "
readonly benchfill="           "

function run_test_env_cmd { # <test name> <allocator name> <environment args> <command> <repeat>
  if ! [ -z "$sleep" ]; then
    sleep "$sleep"
  fi
  echo
  echo "run $5: $1 $2: $3 $4"
  # clear temporary output
  if [ -f "$benchres.line" ]; then
    rm "$benchres.line"
  fi
  outfile="$curdir/$1-$2-out.txt"
  infile="/dev/null"
#  outfile="/dev/null"
  case "$1" in
    lean*)
      echo "preprocess..."
      pushd "../out/release"
      make clean-olean
      popd;;
    lua)
      pushd "$luadir"
      make clean
      popd;;
    spec-*)
      readonly spec_subdir="${1#*-}"
      set_spec_bench_dir "$spec_dir/benchspec/CPU/$spec_subdir/run/run_${spec_base}_${spec_bench}_${spec_config}"
      echo "run spec benchmark in: $spec_bench_dir"
      pushd "$spec_bench_dir";;
    larson*|xmalloc*)
      outfile="$1-$2-out.txt";;
    barnes)
      infile="$benchdir/barnes/input";;
  esac

  $timecmd -a -o "$benchres.line" -f "$1${benchfill:${#1}} $2${allocfill:${#2}} %E %M %U %S %F %R" /usr/bin/env $3 $4 < "$infile" > "$outfile"

  # fixup larson with relative time
  case "$1" in
    larson*)
      rtime=`cat "$1-$2-out.txt" | sed -n 's/.* time: \([0-9\.]*\).*/\1/p'`
      echo "$1,$2, relative time: ${rtime}s"
      sed -E -i.bak "s/($1  *$2  *)[^ ]*/\10:$rtime/" "$benchres.line";;
    rptest*)
      ops=`cat "$1-$2-out.txt" | sed -n 's/.*\.\.\.\([0-9]*\) memory ops.*/\1/p'`
      rtime=`echo "scale=3; (2000000 / $ops)" | bc`
      echo "$1,$2: ops/sec: $ops, relative time: ${rtime}s"
      sed -E -i.bak "s/($1  *$2  *)[^ ]*/\10:$rtime/" "$benchres.line";;
    xmalloc*)
      rtime=`cat "$1-$2-out.txt" | sed -n 's/rtime: \([0-9\.]*\).*/\1/p'`
      echo "$1,$2, relative time: ${rtime}s"
      sed -E -i.bak "s/($1  *$2  *)[^ ]*/\10:$rtime/" "$benchres.line";;
    glibc-thread)
      ops=`cat "$1-$2-out.txt" | sed -n 's/\([0-9\.]*\).*/\1/p'`
      rtime=`echo "scale=3; (1000000000 / $ops)" | bc`
      echo "$1,$2: iterations: ${ops}, relative time: ${rtime}s"
      sed -E -i.bak "s/($1  *$2  *)[^ ]*/\10:$rtime/" "$benchres.line";;
  esac
  test -f "$benchres.line" && cat "$benchres.line" | tee -a $benchres
}

function run_test_cmd {  # <test name> <command>
  echo ""
  echo "---- $repeat: $1"  
  for alloc in $alloc_run; do     # use order as given on the command line
  # for alloc in $alloc_all; do   # use order as specified in $alloc_all
    if contains "$alloc_run" "$alloc"; then
      alloc_lib_set "$alloc"  # sets alloc_lib to point to the allocator .so file
      for ((i=$test_repeats; i>0; i--)); do
        case "$alloc" in
          sys) run_test_env_cmd $1 "sys" "SYSMALLOC=1" "$2" $i;;
          *)   run_test_env_cmd $1 "$alloc" "${ldpreload}=$alloc_lib" "$2" $i;;
        esac
      done
    fi
  done             
}


# --------------------------------------------------------------------
# Run all tests
# --------------------------------------------------------------------

echo "#,benchmark,allocator,elapsed,rss,user,sys,page-faults,page-reclaims" > $benchres

function run_test {  # <test>
  case $1 in
    cfrac)
      run_test_cmd "cfrac" "./cfrac 17545186520507317056371138836327483792789528";;
    espresso)
      run_test_cmd "espresso" "./espresso ../../bench/espresso/largest.espresso";;
    barnes)
      run_test_cmd "barnes" "./barnes";;
    gs)
      run_test_cmd "gs" "gs -dBATCH -dNODISPLAY $pdfdoc";;
    lua)
      pushd "$luadir"
      run_test_cmd "lua" "make"
      popd;;
    lean)
      pushd "$leandir/library"
      if test $procs -gt 8; then # more than 8 makes it slower
        run_test_cmd "leanN" "../bin/lean --make -j 8"
      else
        run_test_cmd "leanN" "../bin/lean --make -j $procs"
      fi
      popd;;
    alloc-test)
      run_test_cmd "alloc-test1" "./alloc-test 1"
      if test "$procs" != "1"; then
        if test $procs -gt 16; then
          run_test_cmd "alloc-testN" "./alloc-test 16"  # 16 is the max for this test
        else
          run_test_cmd "alloc-testN" "./alloc-test $procs"
        fi
      fi;;
    larson-sized)
      run_test_cmd "larsonN-sized" "./larson-sized 5 8 1000 5000 100 4141 $procs";;
    sh6bench)
      run_test_cmd "sh6benchN" "./sh6bench $procsx2";;
    xmalloc-test)
      run_test_cmd "xmalloc-testN" "./xmalloc-test -w $procs -t 5 -s 64";;
    cscratch)
      run_test_cmd "cache-scratch1" "./cache-scratch 1 1000 1 2000000 $procs"
      if test "$procs" != "1"; then
        run_test_cmd "cache-scratchN" "./cache-scratch $procs 1000 1 2000000 $procs"
      fi;;
    malloc-large)
      run_test_cmd "malloc-large" "./malloc-large";;
    mstress)
      run_test_cmd "mstressN" "./mstress $procs 50 25";;
    rptest)
      run_test_cmd "rptestN" "./rptest $procs 0 1 2 500 1000 100 8 16000";;
    glibc-simple)
      run_test_cmd "glibc-simple" "./glibc-simple";;
    glibc-thread)
      run_test_cmd "glibc-thread" "./glibc-thread $procs";;
    *)
      warning "skipping unknown test: $1";;
  esac
}

# Clear previous results
rm "$benchres"
rm -f ./security-*-out.txt

for ((repeat=$repeats; repeat>0; repeat--)); do
  for tst in $tests_run; do
    run_test "$tst"
  done
done


# --------------------------------------------------------------------
# Wrap up
# --------------------------------------------------------------------
if test -f "$benchres"; then
  sed -i.bak "s/ 0:/ /" $benchres
  echo ""
  echo "results written to: $benchres"
  echo ""
  echo "#------------------------------------------------------------------"
  echo "# test    alloc   time  rss    user  sys  page-faults page-reclaims"

  cat $benchres
  echo ""
fi

for file in security-*-out.txt
do
  if [ -f "$file" ]; then
    cat "$file"
    echo ""
  fi
done
