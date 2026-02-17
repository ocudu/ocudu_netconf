#
# Copyright 2021-2026 Software Radio Systems Limited
#
# By using this file, you agree to the terms and conditions set
# forth in the LICENSE file which can be found at the top level of
# the distribution.
#

ARG OS_VERSION=22.04
FROM ubuntu:$OS_VERSION AS base

ENV PYTHONBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# install common dependencies
RUN apt-get update \
    && apt-get install -y \
    openssh-client \
    sudo \
    wget \
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

# Check tag here https://forge.3gpp.org/rep/sa5/MnS/-/tree/Tag_Rel16_SA102?ref_type=tags
ARG YANG_REPO_3GPP_TAG=Tag_Rel16_SA104
ARG NETOPEER2_TAG=v2.2.31
ARG LIBNETCONF2_TAG=v3.5.1
ARG LIBYANG_TAG=v3.4.2
ARG SYSREPO_TAG=v2.11.7

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
    pkg-config \
    python3-pip \
    software-properties-common \
    valgrind \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install apkg

# libyang
RUN cd /opt/dev && \
    git clone --branch ${LIBYANG_TAG} https://github.com/CESNET/libyang.git && \
    cd libyang && apkg build -b && \
    find pkg/pkgs/ubuntu-22.04 -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/libyang && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/libyang/

# sysrepo
RUN cd /opt/dev && \
    git clone --branch ${SYSREPO_TAG} https://github.com/sysrepo/sysrepo.git && \
    cd sysrepo && apkg build -b && \
    find pkg/pkgs/ubuntu-22.04 -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/sysrepo && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/sysrepo/

# libnetconf2
RUN cd /opt/dev && \
    git clone --branch ${LIBNETCONF2_TAG} https://github.com/CESNET/libnetconf2.git && \
    cd libnetconf2 && apkg build -b && \
    find pkg/pkgs/ubuntu-22.04 -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/libnetconf2 && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/libnetconf2/

# netopeer2
RUN cd /opt/dev && \
    git clone --branch ${NETOPEER2_TAG} https://github.com/CESNET/Netopeer2.git && \
    cd Netopeer2 && apkg build -b && \
    find pkg/pkgs/ubuntu-22.04 -type f -name "*.deb" > deb_packages.txt && \
    dpkg -i $(cat deb_packages.txt) && \
    mkdir -p /out/netopeer2 && \
    xargs -a deb_packages.txt -I{} cp "{}" /out/netopeer2/

# download yangs
ADD custom_yangs/download_yang_models.sh /usr/local/bin/download_yang_models.sh
RUN /usr/local/bin/download_yang_models.sh


FROM base AS runner

# copy packages from builder
COPY --from=builder /out/ /out/

# install package dependencies
RUN apt-get update \
    && apt-get install -y \
    libpcre2-dev \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# install packages from builder
RUN dpkg -i /out/libyang/*.deb && \
    dpkg -i /out/sysrepo/*.deb && \
    dpkg -i /out/libnetconf2/*.deb && \
    dpkg -i /out/netopeer2/*.deb

# copy downloaded yangs from builder
COPY --from=builder /opt/dev/modeling/data-model/yang/published/o-ran/ru-fh/ /opt/dev/modeling/data-model/yang/published/o-ran/ru-fh/
COPY --from=builder /opt/dev/modeling/data-model/yang/published/ietf/        /opt/dev/modeling/data-model/yang/published/ietf/
COPY --from=builder /opt/dev/MnS/yang-models/                                /opt/dev/MnS/yang-models/

# Prepare mandatory user.xml
RUN echo '<users xmlns="urn:o-ran:user-mgmt:1.0">\n\
    <user>\n\
    <name>netconf</name>\n\
    <account-type>PASSWORD</account-type>\n\
    <enabled>true</enabled>\n\
    </user>\n\
    </users>' > /opt/dev/user.xml

# O-RAN YANG models
RUN cd /opt/dev/modeling/data-model/yang/published/o-ran/ru-fh && \
    sysrepoctl -i iana-if-type\@2017-01-19.yang && \
    sysrepoctl -i iana-hardware\@2018-03-13.yang && \
    sysrepoctl -i ietf-hardware\@2018-03-13.yang && \
    sysrepoctl -i o-ran-interfaces.yang && \
    sysrepoctl -i o-ran-wg4-features.yang && \
    sysrepoctl -i o-ran-usermgmt.yang -v3 --init-data /opt/dev/user.xml && \
    sysrepoctl -i o-ran-processing-element.yang && \
    sysrepoctl -i o-ran-compression-factors.yang && \
    sysrepoctl -i o-ran-module-cap.yang && \
    sysrepoctl -i o-ran-hardware.yang && \
    sysrepoctl -i o-ran-uplane-conf.yang && \
    sysrepoctl -i ietf-alarms\@2019-09-11.yang && \
    sysrepoctl -i ietf-yang-schema-mount.yang && \
    sysrepoctl -i ietf-yang-types@2013-07-15.yang && \
    sysrepoctl -i ietf-netconf-monitoring.yang

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

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
