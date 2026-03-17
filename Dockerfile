# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS base

ENV PYTHONBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# install common dependencies
RUN apt-get update \
    && apt-get install -y \
    openssh-client \
    sudo \
    wget \
    unzip \
    # needed for convinience in container
    nano \
    && rm -rf /var/lib/apt/lists/*

# Adding netconf user
RUN adduser --system netconf && \
    mkdir -p /home/netconf/.ssh && \
    echo "netconf:netconf" | chpasswd && adduser netconf sudo

# Clearing and setting authorized ssh keys
RUN echo '' > /home/netconf/.ssh/authorized_keys && \
    ssh-keygen -A && \
    ssh-keygen -t dsa -P '' -f /home/netconf/.ssh/id_dsa && \
    cat /home/netconf/.ssh/id_dsa.pub >> /home/netconf/.ssh/authorized_keys

# Updating shell to bash
RUN sed -i s#/home/netconf:/bin/false#/home/netconf:/bin/bash# /etc/passwd

RUN mkdir /opt/dev && sudo chown -R netconf /opt/dev

# set root password to root
RUN echo "root:root" | chpasswd

FROM base AS builder

ARG OS_VERSION
# Check tag here https://forge.3gpp.org/rep/sa5/MnS/-/tree/Tag_Rel16_SA102?ref_type=tags
ARG YANG_REPO_3GPP_TAG=Tag_Rel16_SA104
ARG NETOPEER2_TAG=v2.7.0
ARG LIBNETCONF2_TAG=v4.1.2
ARG LIBYANG_TAG=v4.2.2
ARG SYSREPO_TAG=v4.2.10

# install build dependencies
RUN apt-get update \
    && apt-get install -y \
    build-essential \
    cmake \
    debhelper \
    git \
    graphviz \
    libcmocka-dev \
    libcurlpp-dev \
    libpam0g-dev \
    libpcre2-dev \
    libssh-dev \
    libssl-dev \
    libsystemd-dev \
    pipx \
    pkg-config \
    software-properties-common \
    valgrind \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.local/bin:${PATH}"

RUN pipx install apkg

# libyang
RUN cd /opt/dev && \
    git clone --branch ${LIBYANG_TAG} https://github.com/CESNET/libyang.git && \
    cd libyang && apkg build -b && \
    find pkg/pkgs/ubuntu-${OS_VERSION} -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/libyang && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/libyang/

# sysrepo
RUN cd /opt/dev && \
    git clone --branch ${SYSREPO_TAG} https://github.com/sysrepo/sysrepo.git && \
    cd sysrepo && apkg build -b && \
    find pkg/pkgs/ubuntu-${OS_VERSION} -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/sysrepo && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/sysrepo/

# libnetconf2
RUN cd /opt/dev && \
    git clone --branch ${LIBNETCONF2_TAG} https://github.com/CESNET/libnetconf2.git && \
    cd libnetconf2 && apkg build -b && \
    find pkg/pkgs/ubuntu-${OS_VERSION} -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/libnetconf2 && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/libnetconf2/

# netopeer2
RUN cd /opt/dev && \
    git clone --branch ${NETOPEER2_TAG} https://github.com/CESNET/Netopeer2.git && \
    cd Netopeer2 && apkg build -b && \
    find pkg/pkgs/ubuntu-${OS_VERSION} -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/netopeer2 && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/netopeer2/

# download yangs
ADD custom_yangs/download_yang_models.sh /usr/local/bin/download_yang_models.sh
RUN chmod +x /usr/local/bin/download_yang_models.sh && /usr/local/bin/download_yang_models.sh


FROM base AS runner

# copy packages from builder
COPY --from=builder /out/ /out/

# install package dependencies
RUN apt-get update \
    && apt-get install -y \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# install packages from builder, skip dev packages
RUN find /out/libyang -maxdepth 1 -type f -name "*.deb" ! -name "*-dev*" -print0 | xargs -0 dpkg -i && \
    find /out/sysrepo -maxdepth 1 -type f -name "*.deb" ! -name "*-dev*" -print0 | xargs -0 dpkg -i && \
    find /out/libnetconf2 -maxdepth 1 -type f -name "*.deb" ! -name "*-dev*" -print0 | xargs -0 dpkg -i && \
    find /out/netopeer2 -maxdepth 1 -type f -name "*.deb" ! -name "*-dev*" -print0 | xargs -0 dpkg -i

# set environment variables for netopeer2 postinstall scripts
ENV NP2_MODULE_DIR=/usr/share/yang/modules/netopeer2 \
    NP2_MODULE_PERMS=640 \
    NP2_MODULE_OWNER=root \
    NP2_MODULE_GROUP=sysrepo \
    LN2_MODULE_DIR=/usr/share/yang/modules/libnetconf2

# netopeer2 postinstall scripts setting default values for ietf-netconf-server yang module
RUN bash /usr/share/netopeer2/scripts/setup.sh && \
    bash /usr/share/netopeer2/scripts/merge_hostkey.sh && \
    bash /usr/share/netopeer2/scripts/merge_config.sh
    
# copy downloaded yangs from builder
COPY --from=builder /opt/dev/modeling/data-model/yang/published/o-ran/ru-fh/ /opt/dev/modeling/data-model/yang/published/o-ran/ru-fh/
COPY --from=builder /opt/dev/modeling/data-model/yang/published/ietf/        /opt/dev/modeling/data-model/yang/published/ietf/
COPY --from=builder /opt/dev/MnS/yang-models/                                /opt/dev/MnS/yang-models/
COPY --from=builder /opt/dev/yang-models-misc/                               /opt/dev/yang-models-misc/

# Prepare mandatory user.xml 
RUN echo '<users xmlns="urn:o-ran:user-mgmt:1.0">\n\
    <user>\n\
    <name>netconf</name>\n\
    <account-type>PASSWORD</account-type>\n\
    <enabled>true</enabled>\n\
    </user>\n\
    </users>' > /opt/dev/user.xml

# Install IANA, IETF, IEEE and O-RAN YANG Models
RUN cd /opt/dev/yang-models-misc && \
    sysrepoctl -i iana-if-type\@2017-01-19.yang && \
    sysrepoctl -i iana-hardware\@2018-03-13.yang && \
    sysrepoctl -i ietf-hardware\@2018-03-13.yang && \
    sysrepoctl -i ietf-system.yang && \
    sysrepoctl -i ietf-dhcpv6-common\@2021-01-29.yang && \
    sysrepoctl -i ietf-dhcpv6-types\@2018-09-04.yang && \
    sysrepoctl -i ietf-alarms\@2019-09-11.yang && \
    sysrepoctl -i ietf-yang-schema-mount.yang && \
    sysrepoctl -i ietf-yang-types@2013-07-15.yang && \
    sysrepoctl -i ietf-netconf-monitoring.yang && \
    sysrepoctl -i ieee802-types.yang && \
    sysrepoctl -i ieee802-dot1x-types.yang && \
    sysrepoctl -i ieee802-dot1x.yang && \
    sysrepoctl -i o-ran-common-yang-types.yang && \
    sysrepoctl -i o-ran-wg4-features.yang && \
    sysrepoctl -i o-ran-interfaces.yang && \
    sysrepoctl -i o-ran-usermgmt.yang -v3 --init-data /opt/dev/user.xml && \
    sysrepoctl -i o-ran-processing-element.yang && \
    sysrepoctl -i o-ran-compression-factors.yang && \
    sysrepoctl -i o-ran-module-cap.yang && \
    sysrepoctl -i o-ran-hardware.yang && \
    sysrepoctl -i o-ran-delay-management.yang && \
    sysrepoctl -i o-ran-uplane-conf.yang && \
    sysrepoctl -i o-ran-mplane-int.yang && \
    sysrepoctl -i o-ran-sync.yang && \
    sysrepoctl -i o-ran-troubleshooting.yang && \
    sysrepoctl -i o-ran-supervision.yang && \
    sysrepoctl -i o-ran-file-management.yang && \
    sysrepoctl -i o-ran-software-management.yang && \
    sysrepoctl -i o-ran-operations.yang && \
    sysrepoctl -i o-ran-fm.yang && \    
    sysrepoctl -i o-ran-dhcp.yang && \
    sysrepoctl -i o-ran-certificates.yang

# enable YANG options
RUN sysrepoctl -c ietf-hardware -e hardware-state && \
    sysrepoctl -c o-ran-hardware -e ENERGYSAVING && \
    sysrepoctl -c o-ran-interfaces -e UDPIP-BASED-CU-PLANE && \
    sysrepoctl -c o-ran-module-cap -e PRACH-STATIC-CONFIGURATION-SUPPORTED -e SRS-STATIC-CONFIGURATION-SUPPORTED -e CONFIGURABLE-TDD-PATTERN-SUPPORTED && \
    sysrepoctl -c o-ran-wg4-features -e SUPERVISION-WITH-SESSION-ID && \
    sysrepoctl -c o-ran-sync -e GNSS -e ANTI-JAM

# 3GPP YANG models
RUN cd /opt/dev/MnS/yang-models && \
    sysrepoctl -i _3gpp-common-yang-extensions.yang && \
    sysrepoctl -i _3gpp-common-yang-types.yang && \
    sysrepoctl -i _3gpp-common-top.yang && \
    sysrepoctl -i _3gpp-common-measurements.yang && \
    sysrepoctl -i _3gpp-common-ep-rp.yang && \
    sysrepoctl -i _3gpp-common-trace.yang && \
    sysrepoctl -i _3gpp-common-managed-function.yang && \
    sysrepoctl -i _3gpp-common-subscription-control.yang && \
    sysrepoctl -i _3gpp-common-fm.yang && \
    sysrepoctl -i _3gpp-common-subnetwork.yang && \
    sysrepoctl -i _3gpp-common-managed-element.yang && \
    sysrepoctl -i _3gpp-5gc-nrm-configurable5qiset.yang && \
    sysrepoctl -i _3gpp-5g-common-yang-types.yang && \
    sysrepoctl -i _3gpp-nr-nrm-rrmpolicy.yang && \
    sysrepoctl -i _3gpp-nr-nrm-gnbdufunction.yang && \
    sysrepoctl -i _3gpp-nr-nrm-bwp.yang && \
    sysrepoctl -i _3gpp-nr-nrm-nrcelldu.yang && \
    sysrepoctl -i _3gpp-nr-nrm-gnbcucpfunction.yang && \
    sysrepoctl -i _3gpp-nr-nrm-nrcellcu.yang && \
    sysrepoctl -i _3gpp-nr-nrm-nrsectorcarrier.yang && \
    sysrepoctl -i _3gpp-nr-nrm-gnbdufunction.yang && \
    sysrepoctl -i _3gpp-nr-nrm-gnbcuupfunction.yang && \
    sysrepoctl -i _3gpp-nr-nrm-ep.yang

RUN cd /opt/dev/MnS/yang-models && \
    sysrepoctl -c _3gpp-common-managed-function -e MeasurementsUnderManagedFunction && \
    sysrepoctl -c _3gpp-common-managed-element -e FmUnderManagedElement && \
    sysrepoctl -c _3gpp-nr-nrm-ep -e EPClassesUnderGNBDUFunction && \
    sysrepoctl -c _3gpp-nr-nrm-ep -e EPClassesUnderGNBCUCPFunction

COPY custom_yangs/*.yang /opt/dev/
RUN cd /opt/dev && \
    sysrepoctl -i nrcelldu-base-extensions.yang && \
    sysrepoctl -i nrcelldu-pdsch-extensions.yang && \
    sysrepoctl -i nrcelldu-prach-extensions.yang && \
    sysrepoctl -i nrcelldu-ssb-extensions.yang && \
    sysrepoctl -i nrcelldu-ofh-extensions.yang && \
    sysrepoctl -i nrcelldu-tdd-extensions.yang && \
    sysrepoctl -i nrcelldu-extensions.yang && \
    sysrepoctl -i gnbdufunction-log-extensions.yang && \
    sysrepoctl -i gnbdufunction-testmode-extensions.yang && \
    sysrepoctl -i hal-extensions.yang && \
    sysrepoctl -i metrics-extensions.yang && \
    sysrepoctl -i remote-control-extensions.yang && \
    sysrepoctl -i gnbdufunction-extensions.yang

COPY entrypoint.sh /usr/local/bin
RUN chmod +x /usr/local/bin/entrypoint.sh 

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
