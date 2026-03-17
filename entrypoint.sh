#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

PRELOAD_CONFIG=$1
RUNNING_CONFIG_PATH=$2
RUNNING_CONFIG=/etc/netconf-running/o1-config.xml

if [ -z "$PRELOAD_CONFIG" ]; then
    echo "Error: Missing preload config file argument."
    exit 1
fi

mkdir -p "$(dirname "$RUNNING_CONFIG")"

cleanup() {
    if [ -n "$PRELOAD_CONFIG" ]; then
        echo "Container stopped, exporting running config .."
        sysrepocfg --export -d running > "$PRELOAD_CONFIG"
    else
        echo "Warning: PRELOAD_CONFIG is empty, skipping export."
    fi
}

# Trap SIGTERM
trap 'cleanup' SIGTERM

# Load config either from old run (RUNNING_CONFIG) or from configMap (PRELOAD_CONFIG)
if [ -e $RUNNING_CONFIG ]; then
    echo "Importing existing config from last run $RUNNING_CONFIG .."
else
    echo "Importing config from configMap $PRELOAD_CONFIG .."
    cp $PRELOAD_CONFIG $RUNNING_CONFIG
fi

sysrepocfg --import $RUNNING_CONFIG --datastore running -f xml -m _3gpp-common-managed-element
sysrepocfg --import $RUNNING_CONFIG --datastore running -f xml -m _3gpp-nr-nrm-rrmpolicy

echo "Starting netconf server .."
netopeer2-server -v3 -d

# Wait for all child processes to terminate
wait
