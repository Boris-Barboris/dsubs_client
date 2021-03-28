#!/bin/bash

set -eux

# Install sfml build dependencies:
pacman --noconfirm -S unzip libsndfile libxrandr openal glew freetype2 libx11 mesa make gcc cmake libjpeg

# Download SFML fork source and extract it:
curl -L https://github.com/Boris-Barboris/SFML/archive/master.zip --output sfml.zip -s
unzip sfml.zip
cd SFML-master

# build shared SFML libs
mkdir build && cd build
cmake \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DSFML_USE_SYSTEM_DEPS=ON \
      -DSFML_BUILD_EXAMPLES=0 \
      -DSFML_BUILD_DOC=0 \
      -DJPEG_INCLUDE_DIR=/usr/include \
      -DBUILD_SHARED_LIBS=1 \
    ..
make
make install

# Download CSFML fork source and extract it:
cd ~
curl -L https://github.com/Boris-Barboris/CSFML/archive/master.zip --output csfml.zip -s
unzip csfml.zip
cd CSFML-master

# build shared CSFML libs
mkdir build && cd build
cmake \
      -DCSFML_LINK_SFML_STATICALLY=0 \
      -DCMAKE_MODULE_PATH='~/SFML-master/cmake/Modules' \
    ..
make