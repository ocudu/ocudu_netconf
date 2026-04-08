#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

CONFIG_DIR=/opt/dev/configs
RUNNING_CONFIG=/etc/netconf-running/o1-config.xml
PROFILE_STATE=""
PRELOAD_CONFIG=""
CONFIG_VARIANT=""
YANG_PROFILE=""

usage() {
    cat <<EOF
Usage:
  $0 --config <gnb|cu|cucp|cuup|du|ru> [--running-config <path>]

Options:
  --config          Select the built-in YANG/profile setup and bundled config.
  --running-config  Override the internal persisted running-config path.
  -h, --help        Show this help message.
EOF
}

set_config_profile() {
    case "$1" in
        gnb)
            CONFIG_VARIANT=gnb
            YANG_PROFILE=gnb
            PRELOAD_CONFIG="$CONFIG_DIR/config_gnb.xml"
            ;;
        cu)
            CONFIG_VARIANT=cu
            YANG_PROFILE=cu
            PRELOAD_CONFIG="$CONFIG_DIR/config_cu.xml"
            ;;
        cucp)
            CONFIG_VARIANT=cucp
            YANG_PROFILE=cucp
            PRELOAD_CONFIG="$CONFIG_DIR/config_cucp.xml"
            ;;
        cuup)
            CONFIG_VARIANT=cuup
            YANG_PROFILE=cuup
            PRELOAD_CONFIG="$CONFIG_DIR/config_cuup.xml"
            ;;
        du)
            CONFIG_VARIANT=du
            YANG_PROFILE=du
            PRELOAD_CONFIG="$CONFIG_DIR/config_du.xml"
            ;;
        ru)
            CONFIG_VARIANT=ru
            YANG_PROFILE=ru
            PRELOAD_CONFIG="$CONFIG_DIR/config_ru.xml"
            ;;
        *)
            echo "Error: Unsupported built-in config '$1'. Use one of: gnb, cu, cucp, cuup, du, ru." >&2
            exit 1
            ;;
    esac
}

run_profile_setup() {
    case "$YANG_PROFILE" in
        gnb)
            /usr/local/bin/setup_gnb.sh
            ;;
        cu)
            /usr/local/bin/setup_cu.sh
            ;;
        cucp)
            /usr/local/bin/setup_cucp.sh
            ;;
        cuup)
            /usr/local/bin/setup_cuup.sh
            ;;
        du)
            /usr/local/bin/setup_du.sh
            ;;
        ru)
            /usr/local/bin/setup_ru.sh
            ;;
        *)
            echo "Error: Unsupported YANG profile '$YANG_PROFILE'." >&2
            exit 1
            ;;
    esac
}

merge_selected_config() {
    echo "Merging running config from $RUNNING_CONFIG into running datastore ..."
    sysrepocfg --edit "$RUNNING_CONFIG" --datastore running -f xml
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --config." >&2
                usage
                exit 1
            fi
            set_config_profile "$1"
            ;;
        --running-config)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --running-config." >&2
                usage
                exit 1
            fi
            RUNNING_CONFIG="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "Error: Unknown option '$1'." >&2
            usage
            exit 1
            ;;
        *)
            echo "Error: Positional config files are not supported. Use --config <gnb|cu|cucp|cuup|du|ru>." >&2
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$CONFIG_VARIANT" ]; then
    echo "Error: Missing required --config <gnb|cu|cucp|cuup|du|ru> option." >&2
    usage
    exit 1
fi

if [ -z "$PRELOAD_CONFIG" ]; then
    echo "Error: Missing preload config."
    usage
    exit 1
fi

if [ ! -e "$PRELOAD_CONFIG" ]; then
    echo "Error: Preload config '$PRELOAD_CONFIG' does not exist." >&2
    exit 1
fi

mkdir -p "$(dirname "$RUNNING_CONFIG")"
PROFILE_STATE="$(dirname "$RUNNING_CONFIG")/yang-profile"

# protects against reusing persisted state of one profile (e.g. ru) with a different profile (e.g. du) when rerunning container with persisted state using docker -v option
if [ -e "$PROFILE_STATE" ]; then
    EXISTING_PROFILE="$(cat "$PROFILE_STATE")"
    if [ "$EXISTING_PROFILE" != "$YANG_PROFILE" ]; then
        echo "Error: Container already initialized with YANG profile '$EXISTING_PROFILE', not '$YANG_PROFILE'." >&2
        exit 1
    fi
fi

run_profile_setup
printf '%s\n' "$YANG_PROFILE" > "$PROFILE_STATE"

cleanup() {
    echo "Container stopped, exporting running config .."
    sysrepocfg --export -d running > "$RUNNING_CONFIG"
}

# Trap SIGTERM and SIGINT so docker stop and Ctrl+C both export the running config.
trap 'cleanup' SIGTERM SIGINT

# Load config either from old run (RUNNING_CONFIG) or from configMap (PRELOAD_CONFIG)
if [ -e "$RUNNING_CONFIG" ]; then
    echo "Importing existing config from last run $RUNNING_CONFIG .."
else
    echo "Importing config from configMap $PRELOAD_CONFIG .."
    cp "$PRELOAD_CONFIG" "$RUNNING_CONFIG"
fi

merge_selected_config

echo "Starting netconf server .."
netopeer2-server -v3 -d

# Wait for all child processes to terminate
wait
