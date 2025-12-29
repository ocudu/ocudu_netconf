#!/bin/bash

: "${YANG_REPO_3GPP_TAG:="Tag_Rel16_SA104"}"

yang_model_folder=${1:-"/opt/dev"}
mkdir -p "${yang_model_folder}"

# O-RAN YANG models
cd "${yang_model_folder}" && git clone https://gerrit.o-ran-sc.org/r/scp/oam/modeling.git

# 3GPP YANG models
cd "${yang_model_folder}" && git clone --branch "${YANG_REPO_3GPP_TAG}" https://forge.3gpp.org/rep/sa5/MnS.git
