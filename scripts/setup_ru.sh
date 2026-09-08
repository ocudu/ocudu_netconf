#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

source /usr/local/bin/sysrepo_common.sh

YANG_MISC_DIR=/opt/dev/yang-models-misc
YANG_EXTERNAL_YAMS_DIR=/opt/dev/MnS/yang-models/external-yams

# --standalone: the image runs as the mock O-RU itself (entrypoint --config ru).
# setup_du.sh also sources this script for the DU-side servers; those keep the
# module set the O1 SMO mount is validated against.
STANDALONE_RU=0
[ "${1:-}" = "--standalone" ] && STANDALONE_RU=1

echo "Installing RU YANG modules ..."

ensure_module "$YANG_MISC_DIR/iana-if-type@2017-01-19.yang"
ensure_module "$YANG_MISC_DIR/iana-hardware@2018-03-13.yang"
ensure_module "$YANG_EXTERNAL_YAMS_DIR/ietf-inet-types.yang"
ensure_module "$YANG_MISC_DIR/ietf-hardware@2018-03-13.yang"
ensure_module "$YANG_MISC_DIR/ietf-system.yang"
ensure_module "$YANG_MISC_DIR/ietf-dhcpv6-common@2021-01-29.yang"
ensure_module "$YANG_MISC_DIR/ietf-dhcpv6-types@2018-09-04.yang"
ensure_module "$YANG_MISC_DIR/ietf-alarms@2019-09-11.yang"
ensure_module "$YANG_MISC_DIR/ietf-yang-schema-mount.yang"
ensure_module "$YANG_EXTERNAL_YAMS_DIR/ietf-yang-types.yang"
ensure_module "$YANG_MISC_DIR/ietf-netconf-monitoring.yang"
ensure_module "$YANG_MISC_DIR/ieee802-types.yang"
ensure_module "$YANG_MISC_DIR/ieee802-dot1x-types.yang"
ensure_module "$YANG_MISC_DIR/ieee802-dot1x.yang"
ensure_module "$YANG_MISC_DIR/o-ran-common-yang-types.yang"
ensure_module "$YANG_MISC_DIR/o-ran-wg4-features.yang"
ensure_module "$YANG_MISC_DIR/o-ran-interfaces.yang"
ensure_module "$YANG_MISC_DIR/o-ran-usermgmt.yang" -v3 --init-data /opt/dev/user.xml
ensure_module "$YANG_MISC_DIR/o-ran-processing-element.yang"
ensure_module "$YANG_MISC_DIR/o-ran-compression-factors.yang"
ensure_module "$YANG_MISC_DIR/o-ran-module-cap.yang"
ensure_module "$YANG_MISC_DIR/o-ran-hardware.yang"
ensure_module "$YANG_MISC_DIR/o-ran-delay-management.yang"
ensure_module "$YANG_MISC_DIR/o-ran-uplane-conf.yang"
ensure_module "$YANG_MISC_DIR/o-ran-mplane-int.yang"
ensure_module "$YANG_MISC_DIR/o-ran-sync.yang"
ensure_module "$YANG_MISC_DIR/o-ran-troubleshooting.yang"
ensure_module "$YANG_MISC_DIR/o-ran-supervision.yang"
ensure_module "$YANG_MISC_DIR/o-ran-file-management.yang"
ensure_module "$YANG_MISC_DIR/o-ran-software-management.yang"
ensure_module "$YANG_MISC_DIR/o-ran-operations.yang"
ensure_module "$YANG_MISC_DIR/o-ran-fm.yang"
ensure_module "$YANG_MISC_DIR/o-ran-dhcp.yang"
ensure_module "$YANG_MISC_DIR/o-ran-certificates.yang"
if [ "$STANDALONE_RU" = 1 ]; then
    # o-ran-performance-management (PM configuration + measurement-result-stats)
    # for the mock O-RU only: its submodules are not served over get-schema, so
    # the model must stay out of the du/gnb profiles' advertised set.
    ensure_module "$YANG_MISC_DIR/o-ran-performance-management.yang" -s "$YANG_MISC_DIR"
fi

ensure_feature "ietf-hardware" "hardware-state"
ensure_feature "o-ran-hardware" "ENERGYSAVING"
ensure_feature "o-ran-interfaces" "UDPIP-BASED-CU-PLANE"
ensure_feature "o-ran-module-cap" "PRACH-STATIC-CONFIGURATION-SUPPORTED"
ensure_feature "o-ran-module-cap" "SRS-STATIC-CONFIGURATION-SUPPORTED"
ensure_feature "o-ran-module-cap" "CONFIGURABLE-TDD-PATTERN-SUPPORTED"
ensure_feature "o-ran-wg4-features" "SUPERVISION-WITH-SESSION-ID"
ensure_feature "o-ran-sync" "GNSS"
ensure_feature "o-ran-sync" "ANTI-JAM"
