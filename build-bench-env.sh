#!/bin/bash
# Copyright 2018-2022, Microsoft Research, Daan Leijen, Julien Voisin, Matthew Parkinson

set -eo pipefail

CFLAGS='-march=native'
CXXFLAGS='-march=native'

procs=8
extso=".so"
case "$OSTYPE" in
  darwin*) 
    export HOMEBREW_NO_EMOJI=1
    darwin="1"
    extso=".dylib"
    procs=`sysctl -n hw.physicalcpu`;;
  *)
    darwin=""
    if command -v nproc > /dev/null; then 
      procs=`nproc`
    fi;;
esac

curdir=`pwd`
rebuild=0
all=0

# allocator versions
readonly version_hd=5afe855  # 3.13 #a43ac40 #d880f72  #9d137ef37
readonly version_je=5.3.0
readonly version_mi=v1.7.7
readonly version_tc=gperftools-2.10
### Version of mymalloc.  Use v<year>.<month>.<day>
readonly version_my=v2023.4.13

# benchmark versions
readonly version_lean=v3.4.2
readonly version_lua=v5.4.4

# allocators
setup_hd=0
setup_je=0
setup_mi=0
setup_tc=0
### Flag for personal allocator
setup_my=0

# bigger benchmarks
setup_bench=0
setup_lean=0


# Parse command-line arguments
while : ; do
  flag="$1"
  case "$flag" in
  *=*)  flag_arg="${flag#*=}";;
  no-*) flag_arg="0"
        flag="${flag#no-}";;
  none) flag_arg="0" ;;
  *)    flag_arg="1" ;;
  esac
  # echo "option: $flag, arg: $flag_arg"
  case "$flag" in
    "") break;;
    all|none)
        all=$flag_arg
        setup_hd=$flag_arg              
        setup_je=$flag_arg
        setup_mi=$flag_arg
        setup_tc=$flag_arg
        ### Setting up personal allocator
        setup_my=$flag_arg
        # bigger benchmarks
        setup_lean=$flag_arg
        setup_bench=$flag_arg
        ;;
    bench)
        setup_bench=$flag_arg;;
    hd)
        setup_hd=$flag_arg;;
    je)
        setup_je=$flag_arg;;
    lean)
        setup_lean=$flag_arg;;
    mi)
        setup_mi=$flag_arg;;
    tc)
        setup_tc=$flag_arg;;
    ### Setting personal allocator using arg
    my)
        setup_my=$flag_arg;;
    -r|--rebuild)
        rebuild=1;;
    -j=*|--procs=*)
        procs=$flag_arg;;
    -h|--help|-\?|help|\?)
        echo "./build-bench-env [options]"
        echo ""
        echo "  all                          setup and build (almost) everything"
        echo ""
        echo "  --procs=<n>                  number of processors (=$procs)"
        echo "  --rebuild                    force re-clone and re-build for given tools"
        echo ""
        echo "  hd                           setup hoard ($version_hd)"
        echo "  je                           setup jemalloc ($version_je)"
        echo "  mi                           setup mimalloc ($version_mi)"
        echo "  tc                           setup tcmalloc ($version_tc)"
        echo "  my                           setup your personal malloc ($version_my)"
        echo ""
        echo "  bench                        build all local benchmarks"
        echo "  lean                         setup lean 3 benchmark"
        echo ""
        echo "Prefix an option with 'no-' to disable an option"
        exit 0;;
    *) echo "warning: unknown option \"$1\"." 1>&2
  esac
  shift
done

if test -f ./build-bench-env.sh; then
  echo ""
  echo "use '-h' to see all options"
  echo "use 'all' to build all allocators"
  echo ""
  echo "building with $procs threads"
  echo "--------------------------------------------"
  echo ""
else
  echo "error: must run from the toplevel mimalloc-bench directory!"
  exit 1
fi

mkdir -p extern
readonly devdir="$curdir/extern"

function phase {
  cd "$curdir"
  echo
  echo
  echo "--------------------------------------------"
  echo "$1"
  echo "--------------------------------------------"
  echo
}

function write_version {  # name, git-tag, repo
  commit=$(git log -n1 --format=format:"%h")
  echo "$1: $2, $commit, $3" > "$devdir/version_$1.txt"
}

function partial_checkout {  # name, git-tag, git repo, directory to download
  phase "build $1: version $2"
  pushd $devdir
  if test "$rebuild" = "1"; then
    rm -rf "$1"
  fi
  if test -d "$1"; then
    echo "$devdir/$1 already exists; no need to git clone"
    cd "$1"
  else
    mkdir "$1"
    cd "$1"
    git init
    git remote add origin $3
    git config extensions.partialClone origin
    git sparse-checkout set $4
  fi
  git fetch --depth=1 --filter=blob:none origin $2
  git checkout $2
  git reset origin/$2 --hard
  write_version $1 $2 $3
}

function checkout {  # name, git-tag, git repo, options
  phase "build $1: version $2"
  pushd $devdir
  if test "$rebuild" = "1"; then
    rm -rf "$1"
  fi
  if test -d "$1"; then
    echo "$devdir/$1 already exists; no need to git clone"
  else
    git clone $4 $3 $1
  fi
  cd "$1"
  git checkout $2
  write_version $1 $2 $3
}

if test "$all" = "1"; then
  if test "$rebuild" = "1"; then
    phase "clean $devdir for a full rebuild"
    pushd "$devdir"
    cd ..
    rm -rf "extern/*"
    popd
  fi
fi

if test "$setup_tc" = "1"; then
  checkout tc $version_tc https://github.com/gperftools/gperftools
  if test -f configure; then
    echo "already configured"
  else
    ./autogen.sh
    CXXFLAGS="$CXXFLAGS -w -DNDEBUG -O2" ./configure --enable-minimal --disable-debugalloc
  fi
  make -j $procs # ends with error on benchmark, but thats ok.
  #echo ""
  #echo "(note: the error 'Makefile:3912: recipe for target 'malloc_bench' failed' is expected)"
  popd
fi

if test "$setup_hd" = "1"; then
  checkout hd $version_hd https://github.com/emeryberger/Hoard
  cd src
  if [ "`uname -m -s`" = "Darwin x86_64" ] ; then
    sed -i_orig 's/-arch arm64/ /g' GNUmakefile   # fix the makefile    
  fi
  make -j $procs
  popd
fi

if test "$setup_je" = "1"; then
  checkout je $version_je https://github.com/jemalloc/jemalloc
  if test -f config.status; then
    echo "$devdir/jemalloc is already configured; no need to reconfigure"
  else
    ./autogen.sh --enable-doc=no --enable-static=no --disable-stats
  fi
  make -j $procs
  [ "$CI" ] && rm -rf ./src/*.o  # jemalloc has like ~100MiB of object files
  [ "$CI" ] && rm -rf ./lib/*.a  # jemalloc produces 80MiB of static files
  popd
fi

if test "$setup_mi" = "1"; then
  checkout mi $version_mi https://github.com/microsoft/mimalloc

  echo ""
  echo "- build mimalloc release"

  mkdir -p out/release
  cd out/release
  cmake ../..
  make -j $procs
  cd ../..

  echo ""
  echo "- build mimalloc debug with full checking"

  mkdir -p out/debug
  cd out/debug
  cmake ../.. -DMI_CHECK_FULL=ON
  make -j $procs
  cd ../..

  echo ""
  echo "- build mimalloc secure"

  mkdir -p out/secure
  cd out/secure
  cmake ../.. -DMI_SECURE=ON
  make -j $procs
  cd ../..
  popd
fi

### Actually moving user library here
if test "$setup_my" = "1"; then 
  if ! test -d "./extern/mymalloc/"; then
    mkdir ./extern/mymalloc
  fi
  ### <path to .so> ./extern/mymalloc/
  cp ../../src/libmymalloc.so ./extern/mymalloc/
  # write_version samalloc $version_my
  echo "sam: $version_my, 0, here" > "$devdir/version_my.txt"
fi

phase "install benchmarks"

if test "$setup_lean" = "1"; then
  phase "build lean $version_lean"
  checkout lean $version_lean https://github.com/leanprover/lean
  mkdir -p out/release
  cd out/release
  env CC=gcc CXX="g++" cmake ../../src -DCUSTOM_ALLOCATORS=OFF -DLEAN_EXTRA_CXX_FLAGS="-w"
  echo "make -j$procs"
  make -j $procs
  rm -rf ./tests/  # we don't need tests
  popd
fi

if test "$setup_bench" = "1"; then
  phase "patch shbench"
  pushd "bench/shbench"
  if test -f sh6bench-new.c; then
    echo "do nothing: bench/shbench/sh6bench-new.c already exists"
  else
    wget --no-verbose http://www.microquill.com/smartheap/shbench/bench.zip
    unzip -o bench.zip
    dos2unix sh6bench.patch
    dos2unix sh6bench.c
    patch -p1 -o sh6bench-new.c sh6bench.c sh6bench.patch
  fi
  popd

  phase "get large PDF document"

  readonly pdfdoc="large.pdf"
  readonly pdfurl="https://raw.githubusercontent.com/geekaaron/Resources/master/resources/Writing_a_Simple_Operating_System--from_Scratch.pdf "
  #readonly pdfurl="https://www.intel.com/content/dam/develop/external/us/en/documents/325462-sdm-vol-1-2abcd-3abcd-508360.pdf"
  pushd "$devdir"
  if test -f "$pdfdoc"; then
    echo "do nothing: $devdir/$pdfdoc already exists"
  else
    useragent="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:95.0) Gecko/20100101 Firefox/95.0"
    wget --no-verbose -O "$pdfdoc" -U "useragent" $pdfurl
  fi
  popd

  phase "get lua"
  checkout lua $version_lua https://github.com/lua/lua
  popd

  phase "build benchmarks"

  mkdir -p out/bench
  cd out/bench
  cmake ../../bench
  make -j $procs
  cd ../..
fi


curdir=`pwd`

phase "installed allocators"
cat $devdir/version_*.txt 2>/dev/null | tee $devdir/versions.txt | column -t || true

phase "done in $curdir"
echo "run a specific benchmark across all allocators as:"
echo "> cd out/bench"
echo "> ../../bench.sh alla <benchmark_name>"
echo
echo "run all benchmarks across a specific allocator as:"
echo "> cd out/bench"
echo "> ../../bench.sh <allocator_name> allt"
echo
echo "to see all options use:"
echo "> ../../bench.sh help"
echo
