#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

module_name_from_file() {
    local file_path="$1"
    local filename

    filename="$(basename "$file_path" .yang)"
    printf '%s\n' "${filename%%@*}"
}

find_module_file() {
    local pattern="$1"
    local match

    match="$(compgen -G "$pattern" | head -n 1 || true)"

    if [ -z "$match" ]; then
        echo "Error: Unable to resolve YANG file for pattern '$pattern'." >&2
        exit 1
    fi

    printf '%s\n' "$match"
}

ensure_module() {
    local file_path="$1"
    shift || true

    local module_name
    module_name="$(module_name_from_file "$file_path")"

    echo "Installing module $module_name from $file_path ..."
    sysrepoctl -i "$file_path" "$@"
}

ensure_named_module_glob() {
    local module_name="$1"
    local pattern="$2"
    shift 2 || true

    echo "Installing module $module_name from pattern $pattern ..."
    sysrepoctl -i "$(find_module_file "$pattern")" "$@"
}

ensure_feature() {
    local module="$1"
    local feature="$2"

    echo "Enabling feature $feature on module $module ..."
    sysrepoctl -c "$module" -e "$feature"
}
