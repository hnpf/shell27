#!/bin/sh
# Rebuilds the clock shader (shaders/glasstext.frag -> shaders/glasstext.frag.qsb). Needs Qt's shader baker (qt6-shadertools).
cd "$(dirname "$0")" || exit 1
QSB=$(command -v qsb || command -v qsb6 || echo /usr/lib/qt6/bin/qsb)
"$QSB" --qt6 -o shaders/glasstext.frag.qsb shaders/glasstext.frag && echo "built shaders/glasstext.frag.qsb"
