#!/bin/bash

set -euo pipefail

# This is a simple script for downloading + compiling + installing mcl version 22-282
cff=22-273
mcl=22-282

# Change if you want to install somewhere else
INSTALL=$HOME/local

# Now the rest of this script should have enough to run.
mcltar=mcl-$mcl.tar.gz
cfftar=cimfomfa-$cff.tar.gz

if command -v wget > /dev/null; then 
   wget http://micans.org/mcl/src/$mcltar -O $mcltar
   wget http://micans.org/mcl/src/$cfftar -O $cfftar
elif command -v curl > /dev/null; then 
   curl http://micans.org/mcl/src/$mcltar -O
   curl http://micans.org/mcl/src/$cfftar -O
else
   echo "Explain to me how to download stuff please"
   false
fi

if true; then
  thedir=${cfftar%.tar.gz}
  tar xzf $cfftar
  ( cd $thedir
    ./configure --prefix=$INSTALL --disable-shared
    make
    make install
  )
fi

if true; then
  tar xzf $mcltar
  thedir=${mcltar%.tar.gz}
  ( cd $thedir
    ./configure CFLAGS=-I$INSTALL/include LDFLAGS=-L$INSTALL/lib --prefix=$INSTALL --enable-rcl
    make
    make install
  )
fi

