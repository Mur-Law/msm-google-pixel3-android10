#!/bin/bash

# Incremental build wrapper script for Android kernel
# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Usage:
#   build/incremental_build.sh [options]
#
# Options:
#   --clean, -c     Force a complete clean rebuild
#   --config, -cfg  Rebuild configuration only (when configs changed)
#   --help, -h      Show this help message
#
# Examples:
#   build/incremental_build.sh              # Normal incremental build
#   build/incremental_build.sh --clean      # Force clean rebuild
#   build/incremental_build.sh -j24 V=1     # Incremental build with make options

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default settings
FORCE_CLEAN=0
CONFIG_ONLY=0
MAKE_ARGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean|-c)
            FORCE_CLEAN=1
            shift
            ;;
        --config|-cfg)
            CONFIG_ONLY=1
            shift
            ;;
        --help|-h)
            echo "Incremental build wrapper script for Android kernel"
            echo ""
            echo "Usage: $0 [options] [make options]"
            echo ""
            echo "Options:"
            echo "  --clean, -c     Force a complete clean rebuild"
            echo "  --config, -cfg  Rebuild configuration only"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Normal incremental build"
            echo "  $0 --clean           # Force clean rebuild"
            echo "  $0 -j24 V=1          # Incremental build with make options"
            echo ""
            echo "Environment variables:"
            echo "  OUT_DIR             Output directory (default: out/android-msm-pixel-4.9)"
            echo "  DIST_DIR            Distribution directory (default: \$OUT_DIR/dist)"
            echo "  BUILD_CONFIG        Build config file (default: build.config)"
            exit 0
            ;;
        *)
            MAKE_ARGS="$MAKE_ARGS $1"
            shift
            ;;
    esac
done

# Set default build config if not specified
if [ -z "${BUILD_CONFIG}" ]; then
    # Try to find the appropriate build config
    if [ -f "${ROOT_DIR}/private/msm-google/build.config.common" ]; then
        export BUILD_CONFIG="private/msm-google/build.config.common"
        echo "Using BUILD_CONFIG: ${BUILD_CONFIG}"
    else
        echo "Warning: No BUILD_CONFIG specified and default not found"
        echo "You may need to set BUILD_CONFIG environment variable"
    fi
fi

# Configure incremental build behavior
if [ "$FORCE_CLEAN" = "1" ]; then
    echo "========================================================"
    echo " Performing FORCE CLEAN rebuild"
    echo "========================================================"
    export FORCE_CLEAN=1
    export INCREMENTAL_BUILD=0
elif [ "$CONFIG_ONLY" = "1" ]; then
    echo "========================================================"
    echo " Rebuilding configuration only"
    echo "========================================================"
    export SKIP_MRPROPER=1
    unset SKIP_DEFCONFIG
    export INCREMENTAL_BUILD=1
else
    echo "========================================================"
    echo " Starting INCREMENTAL build"
    echo "========================================================"
    export INCREMENTAL_BUILD=1
fi

# Set up output directories
export OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out/android-msm-pixel-4.9}"
export DIST_DIR="${DIST_DIR:-${OUT_DIR}/dist}"

echo " OUT_DIR: ${OUT_DIR}"
echo " DIST_DIR: ${DIST_DIR}"
echo " BUILD_CONFIG: ${BUILD_CONFIG}"

# Show build time estimation
if [ -f "${OUT_DIR}/.config" ] && [ "$FORCE_CLEAN" != "1" ]; then
    echo ""
    echo "Incremental build detected - estimated time: 2-5 minutes"
    echo "(vs 20-30 minutes for full rebuild)"
else
    echo ""
    echo "Full build required - estimated time: 20-30 minutes"
fi

echo "========================================================"

# Execute the build
exec "${SCRIPT_DIR}/build.sh" $MAKE_ARGS