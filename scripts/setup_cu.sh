#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

source /usr/local/bin/sysrepo_common.sh

echo "Installing CU YANG modules ..."

# Compose CU from CU-CP + CU-UP
/usr/local/bin/setup_cucp.sh
/usr/local/bin/setup_cuup.sh

ensure_module /opt/dev/cu-qos-consistency.yang
