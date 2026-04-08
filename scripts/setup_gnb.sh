#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

echo "Installing CU/DU YANG modules ..."

/usr/local/bin/setup_du.sh
/usr/local/bin/setup_cu.sh

