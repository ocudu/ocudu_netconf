#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

source /usr/local/bin/sysrepo_common.sh

YANG_MISC_DIR=/opt/dev/yang-models-misc
YANG_3GPP_DIR=/opt/dev/MnS/yang-models
YANG_IETF_DIR=/opt/dev/modeling/data-model/yang/published/ietf
CUSTOM_YANG_DIR=/opt/dev

echo "Installing DU YANG modules ..."

# RU YANG Modules also have to be installed to allow the NETCONF server to reflect RU configuration
/usr/local/bin/setup_ru.sh

ensure_module "$YANG_3GPP_DIR/_3gpp-common-yang-extensions.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-yang-types.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-top.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-files.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-measurements.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-ep-rp.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-trace.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-managed-function.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-subscription-control.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-fm.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-5gc-nrm-configurable5qiset.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-5gc-nrm-ecmconnectioninfo.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-5g-common-yang-types.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-ecmappingrule.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-subnetwork.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-common-managed-element.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-gnbdufunction.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-bwp.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-nrcelldu.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-gnbcucpfunction.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-nrcellcu.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-nrsectorcarrier.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-gnbcuupfunction.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-ep.yang"
ensure_module "$YANG_3GPP_DIR/_3gpp-nr-nrm-rrmpolicy.yang"

ensure_feature "_3gpp-common-managed-function" "MeasurementsUnderManagedFunction"
ensure_feature "_3gpp-common-managed-element" "FmUnderManagedElement"
ensure_feature "_3gpp-nr-nrm-ep" "EPClassesUnderGNBDUFunction"

ensure_module "$CUSTOM_YANG_DIR/nrcelldu-base-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/nrcelldu-pdsch-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/nrcelldu-prach-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/nrcelldu-ssb-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/nrcelldu-ofh-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/nrcelldu-tdd-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/nrcelldu-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/log-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/gnbdufunction-testmode-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/hal-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/metrics-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/pcap-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/remote-control-extensions.yang"
ensure_module "$CUSTOM_YANG_DIR/gnbdufunction-extensions.yang"
