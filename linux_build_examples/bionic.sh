#!/bin/bash


# TESTED ON UBUNTU BIONIC VM

set -eux

# build sfml:

# Install sfml build dependencies:
sudo apt install git unzip ssh rsync binutils gcc g++ cmake make libx11-dev x11-xserver-utils xorg-dev libglu1-mesa-dev freeglut3-dev libudev-dev libjpeg-dev libopenal-dev libflac-dev libvorbis-dev libpulse-dev curl

# Download SFML fork source and extract it:
curl -L https://github.com/Boris-Barboris/SFML/archive/master.zip --output sfml.zip -s
unzip sfml.zip && cd SFML-master

# build shared SFML libs
mkdir build && cd build
cmake \
      -DSFML_USE_SYSTEM_DEPS=True \
      -DSFML_BUILD_EXAMPLES=0 \
      -DSFML_BUILD_DOC=0 \
      -DBUILD_SHARED_LIBS=1 \
    ..
make -j 8
sudo make install

# Download CSFML fork source and extract it:
cd ~
curl -L https://github.com/Boris-Barboris/CSFML/archive/master.zip \
    --output csfml.zip -s
unzip csfml.zip && cd CSFML-master

# build shared CSFML libs
mkdir build && cd build
cmake \
      -DCSFML_LINK_SFML_STATICALLY=0 \
      -DCMAKE_MODULE_PATH='~/SFML-master/cmake/Modules' \
    ..
make -j 8


# build openal
cd ~
curl -L https://github.com/Boris-Barboris/openal-soft/archive/mix_gain_limit.zip \
    --output openal-soft.zip -s
unzip openal-soft.zip && cd openal-soft-mix_gain_limit/build
cmake \
    -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=gold \
    -DALSOFT_STATIC_STDCXX=true \
    -DALSOFT_REQUIRE_PULSEAUDIO=true \
    ..
make -j 8


# install dmd compiler
mkdir -p ~/dlang && wget https://dlang.org/install.sh -O ~/dlang/install.sh && \
    bash ~/dlang/install.sh install dmd-2.093.1
source ~/dlang/dmd-2.093.1/activate

# clone dsubs
git clone --recursive git@github.com:Boris-Barboris/dsubs.git
cd dsubs/dsubs_client
dub build -b debug -c prod


# bundle this shit
cd ~

rm -rf dsubs_libs
mkdir dsubs_libs
rsync -lv SFML-master/build/lib/*graphics* dsubs_libs/
rsync -lv SFML-master/build/lib/*system* dsubs_libs/
rsync -lv SFML-master/build/lib/*window* dsubs_libs/
rsync -lv CSFML-master/build/lib/*graphics* dsubs_libs/
rsync -lv CSFML-master/build/lib/*system* dsubs_libs/
rsync -lv CSFML-master/build/lib/*window* dsubs_libs/
rsync -lv CSFML-master/build/lib/*window* dsubs_libs/
rsync -lv openal-soft-mix_gain_limit/build/libopenal.so* dsubs_libs/
rsync -lrv dsubs/dsubs_client/fonts ./
cp dsubs/dsubs_client/dsubs_client dsubs_client
cp dsubs/dsubs_client/alsoft.ini alsoft.ini
echo '#!/bin/bash
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:dsubs_libs/"
./dsubs_client' > run_client.sh
chmod +x run_client.sh
echo "dsubs_libs contain sfml fork and openal-soft, compiled by gcc/g++ 7.4.0 against glibc 2.27.
Requires your distro analog of libx11-dev and xclip.
Run by invoking run_client.sh" > readme_linux.txt
tar -zcvf dsubs-linux-bionic-amd64.tar.gz dsubs_libs fonts dsubs_client alsoft.ini run_client.sh readme_linux.txt