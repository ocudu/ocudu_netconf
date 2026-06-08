# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS base

ENV PYTHONBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# install common dependencies
RUN apt-get update \
    && apt-get install -y \
    ca-certificates \
    openssh-client \
    sudo \
    wget \
    unzip \
    # needed for convinience in container
    nano \
    && wget -q -O /usr/local/share/ca-certificates/GeoTrustTLSRSACAG1.crt \
       https://cacerts.digicert.com/GeoTrustTLSRSACAG1.crt.pem \
    && update-ca-certificates \
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
ARG YANG_REPO_3GPP_TAG=Tag_Rel18_SA111
ARG NETOPEER2_TAG=v2.8.2
ARG LIBNETCONF2_TAG=v4.2.14
ARG LIBYANG_TAG=v5.4.9
ARG SYSREPO_TAG=v4.5.4

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
ADD scripts/download_yang_models.sh /usr/local/bin/download_yang_models.sh
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

# copy custom yangs to the image
COPY custom_yangs/*.yang        /opt/dev/

# copy config xmls to the image
COPY configs/config_gnb.xml     /opt/dev/configs/config_gnb.xml
COPY configs/config_cu.xml      /opt/dev/configs/config_cu.xml
COPY configs/config_cucp.xml    /opt/dev/configs/config_cucp.xml
COPY configs/config_cuup.xml    /opt/dev/configs/config_cuup.xml
COPY configs/config_du.xml      /opt/dev/configs/config_du.xml
COPY configs/config_ru.xml      /opt/dev/configs/config_ru.xml

COPY scripts/*.sh entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Run as non-root uid 1000: join the sysrepo group (on connect sysrepo chgrp()s its
# lock/datastore files to group "sysrepo", which a non-root process can only do as a
# member of that group) and the shadow group (PAM password auth reads /etc/shadow
# directly), and own the sysrepo repo + the writable /etc/netconf-{running,tls} dirs.
RUN usermod -aG sysrepo,shadow ubuntu && \
    mkdir -p /etc/netconf-running /etc/netconf-tls && \
    chown -R 1000:1000 /etc/sysrepo /etc/netconf-running /etc/netconf-tls

USER 1000

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
