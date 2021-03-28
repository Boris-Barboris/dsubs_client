#!/bin/bash

set -eu
dub build -b debug "$@"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${0%/*}/dsubs_libs/"
#export ALSOFT_CONF="./alsoft.ini"
./dsubs_client
