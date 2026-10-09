#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

NETCONF_SSH_USERNAME="${1:-}"
NETCONF_SSH_PASSWORD="${2:-}"

# OpenDaylight-based controllers only implement the SSH "password" method, which the
# stock server never offers because its local users all use system authentication
# (keyboard-interactive). An ietf-ssh-server local user with a password (RFC 9644)
# enables that method for exactly this user. The user goes into the stock endpoint
# "default-ssh", whatever its port override says.
if [ -z "$NETCONF_SSH_USERNAME" ] || [ -z "$NETCONF_SSH_PASSWORD" ]; then
    echo "Error: NETCONF_SSH_USERNAME and NETCONF_SSH_PASSWORD must be set together." >&2
    exit 1
fi

# libnetconf2 compares <hashed-password> directly against a crypt(3) hash; $0$ marks
# a cleartext value. A password that already starts with $ is a pre-built crypt string
# (e.g. $6$ from mkpasswd -m sha-512 / openssl passwd -6) and passes through verbatim.
case "$NETCONF_SSH_PASSWORD" in
    '$'*) HASHED_PASSWORD="$NETCONF_SSH_PASSWORD" ;;
    *) HASHED_PASSWORD="\$0\$${NETCONF_SSH_PASSWORD}" ;;
esac

echo "Configuring NETCONF SSH user '$NETCONF_SSH_USERNAME' with password authentication ..."

USER_XML="$(mktemp)"
NACM_XML="$(mktemp)"
trap 'rm -f "$USER_XML" "$NACM_XML"' EXIT

cat >"$USER_XML" <<EOF
<netconf-server xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-server">
  <listen>
    <endpoints>
      <endpoint>
        <name>default-ssh</name>
        <ssh>
          <ssh-server-parameters>
            <client-authentication>
              <users>
                <user>
                  <name>${NETCONF_SSH_USERNAME}</name>
                  <password>
                    <hashed-password>${HASHED_PASSWORD}</hashed-password>
                  </password>
                </user>
              </users>
            </client-authentication>
          </ssh-server-parameters>
        </ssh>
      </endpoint>
    </endpoints>
  </listen>
</netconf-server>
EOF

sysrepocfg --edit "$USER_XML" --datastore running -f xml

# NACM denies writes to everyone but the recovery user (root) by default, which would
# make the new user read-only. Grant it full access: membership in the "o1-admin"
# group plus a permit-all rule, so <edit-config> works for it like it does for root.
cat >"$NACM_XML" <<EOF
<nacm xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-acm">
  <groups>
    <group>
      <name>o1-admin</name>
      <user-name>${NETCONF_SSH_USERNAME}</user-name>
    </group>
  </groups>
  <rule-list>
    <name>o1-admin-access</name>
    <group>o1-admin</group>
    <rule>
      <name>permit-all</name>
      <module-name>*</module-name>
      <access-operations>*</access-operations>
      <action>permit</action>
    </rule>
  </rule-list>
</nacm>
EOF

sysrepocfg --edit "$NACM_XML" --datastore running -f xml -m ietf-netconf-acm

echo "NETCONF SSH user '$NETCONF_SSH_USERNAME' configured."
