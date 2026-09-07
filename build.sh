#!/bin/bash
# Compiles the binary into the current directory. Used by install.sh and by the Homebrew
# formula, so the build flags live in exactly one place.
set -euo pipefail
cd "$(dirname "$0")"

swiftc -O \
    -framework IOBluetooth \
    -framework IOKit \
    -framework CoreGraphics \
    -framework AppKit \
    -o headphone-disconnect \
    main.swift Sources/*.swift
