#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

: "${YANG_REPO_3GPP_TAG:="Tag_Rel18_SA111"}"

YANG_MODEL_DIR=${1:-"/opt/dev"}
mkdir -p "${YANG_MODEL_DIR}"

# Target path for yang-models-misc
YANG_MISC_MODEL_DIR="${YANG_MODEL_DIR}/yang-models-misc"

# O-RAN Specs YANG models
ORAN_SPECS_YANG_URL="https://specifications.o-ran.org/download?id=1035"
ORAN_SPECS_YANG_ARCHIVE_DIR="${YANG_MODEL_DIR}/o-ran-yang-models.zip"
ORAN_SPECS_YANG_EXTRACT_DIR="${YANG_MODEL_DIR}/o-ran-yang-models-extract"

# O-RAN SC models
ORAN_SC_YANG_URL="https://gerrit.o-ran-sc.org/r/scp/oam/modeling.git"
ORAN_SC_YANG_DIR="${YANG_MODEL_DIR}/modeling"

# IEEE models
IEEE_YANG_URLS=(
  "https://www.ieee802.org/1/files/public/YANGs/ieee802-dot1x.yang"
  "https://www.ieee802.org/1/files/public/YANGs/ieee802-dot1x-types.yang"
  "https://www.ieee802.org/1/files/public/YANGs/ieee802-types.yang"
)

# IETF-system YANG model
IETF_SYSTEM_YANG_URL="https://raw.githubusercontent.com/YangModels/yang/main/standard/ietf/RFC/ietf-system%402014-08-06.yang"

# 3GPP models
GPP_YANG_URL="https://forge.3gpp.org/rep/sa5/MnS.git"

rm -rf "${ORAN_SPECS_YANG_EXTRACT_DIR}" "${YANG_MISC_MODEL_DIR}" "${ORAN_SC_YANG_DIR}"
mkdir -p "${ORAN_SPECS_YANG_EXTRACT_DIR}" "${YANG_MISC_MODEL_DIR}"

# Downloading O-RAN Specs YANG models
if ! wget -q -O "${ORAN_SPECS_YANG_ARCHIVE_DIR}" "${ORAN_SPECS_YANG_URL}"; then
  echo "ERROR: Failed to download O-RAN YANG models from ${ORAN_SPECS_YANG_URL}" >&2
  exit 1
fi

if ! unzip -qo "${ORAN_SPECS_YANG_ARCHIVE_DIR}" -d "${ORAN_SPECS_YANG_EXTRACT_DIR}"; then
  echo "ERROR: Failed to extract O-RAN YANG models archive ${ORAN_SPECS_YANG_ARCHIVE_DIR}" >&2
  exit 1
fi

oran_yang_files_count=0
while IFS= read -r -d '' yang_file; do
  cp -Lf "${yang_file}" "${YANG_MISC_MODEL_DIR}/$(basename "${yang_file}")"
  oran_yang_files_count=$((oran_yang_files_count + 1))
done < <(find "${ORAN_SPECS_YANG_EXTRACT_DIR}" \( -type f -o -type l \) -name 'o-ran*.yang' -print0)

if [ "${oran_yang_files_count}" -eq 0 ]; then
  echo "ERROR: No O-RAN YANG models found in downloaded O-RAN archive." >&2
  exit 1
fi

rm -rf "${ORAN_SPECS_YANG_EXTRACT_DIR}" "${ORAN_SPECS_YANG_ARCHIVE_DIR}"

# Downloading O-RAN SC YANG models
if ! git ls-remote --exit-code "${ORAN_SC_YANG_URL}" > /dev/null 2>&1; then
  echo "ERROR: O-RAN SC YANG repository is not reachable: ${ORAN_SC_YANG_URL}" >&2
  exit 1
fi
cd "${YANG_MODEL_DIR}" && git clone "${ORAN_SC_YANG_URL}"

oran_sc_yang_files_count=0
while IFS= read -r -d '' yang_file; do
  cp -Lf "${yang_file}" "${YANG_MISC_MODEL_DIR}/$(basename "${yang_file}")"
  oran_sc_yang_files_count=$((oran_sc_yang_files_count + 1))
done < <(find "${ORAN_SC_YANG_DIR}" \( -type f -o -type l \) -name '*.yang' ! -name 'o-ran*' -print0)

if [ "${oran_sc_yang_files_count}" -eq 0 ]; then
  echo "ERROR: No O-RAN SC YANG models found in ${ORAN_SC_YANG_DIR}." >&2
  exit 1
fi

# Downloading IEEE 802 YANG models
for ieee_yang_url in "${IEEE_YANG_URLS[@]}"; do
  ieee_yang_file="${ieee_yang_url##*/}"
  wget -q -O- "${ieee_yang_url}" | tr '\r' '\n' > "${YANG_MISC_MODEL_DIR}/${ieee_yang_file}" || {
    echo "ERROR: Failed to download IEEE YANG module from ${ieee_yang_url}" >&2
    exit 1
  }
done

# Downloading IETF System YANG model
if ! wget -q -O "${YANG_MISC_MODEL_DIR}/ietf-system.yang" "${IETF_SYSTEM_YANG_URL}"; then
  echo "ERROR: Failed to download IETF YANG module from ${IETF_SYSTEM_YANG_URL}" >&2
  exit 1
fi

# Downloading 3GPP YANG models — forge.3gpp.org penalises first connections from
# a new source IP with a ~25s TLS handshake that races their HTTP idle timeout; retry covers it
for attempt in 1 2 3 4 5; do
  rm -rf "${YANG_MODEL_DIR}/MnS"
  if (cd "${YANG_MODEL_DIR}" && git clone --branch "${YANG_REPO_3GPP_TAG}" "${GPP_YANG_URL}"); then
    break
  fi
  if [ "${attempt}" -eq 5 ]; then
    echo "ERROR: 3GPP YANG repository is not reachable after ${attempt} attempts: ${GPP_YANG_URL}" >&2
    exit 1
  fi
  backoff=$((attempt * 10))
  echo "WARN: 3GPP clone failed (attempt ${attempt}); retrying in ${backoff}s..." >&2
  sleep "${backoff}"
done
