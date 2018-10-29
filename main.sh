#!/bin/bash
set -eu
script="${BASH_SOURCE[0]}"
echo "Accessing libplugin.so via .runfiles/__main__/external/child:"
ldd $script.runfiles/__main__/external/child/libplugin.so | grep appcode
echo "Accessing libplugin.so via .runfiles/child:"
ldd $script.runfiles/child/libplugin.so | grep appcode
