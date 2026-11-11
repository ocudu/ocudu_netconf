#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

# Usage: nacm_admin.sh grant|revoke <username>
#
# NACM denies writes to everyone but sysrepo's recovery user (root), which bypasses NACM
# entirely. Instead of logging in as root, a NETCONF user gets full access through NACM:
# membership in the group "o1-admin", whose rule-list "o1-admin-access" permits everything.
# The group is shared by every user granted here (the SSH password user, the TLS client
# CN), so revoke removes only that one member and leaves the others alone.

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

if [ -z "${2:-}" ]; then
    echo "Usage: $0 grant|revoke <username>" >&2
    exit 1
fi
USERNAME_ESC="$(xml_escape "$2")"

NACM_XML="$(mktemp)"
trap 'rm -f "$NACM_XML"' EXIT

case "$1" in
    grant)
        cat >"$NACM_XML" <<EOF
<nacm xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-acm">
  <groups>
    <group>
      <name>o1-admin</name>
      <user-name>${USERNAME_ESC}</user-name>
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
        ;;
    revoke)
        # nc:operation="remove" passes silently when the member is already gone.
        cat >"$NACM_XML" <<EOF
<nacm xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-acm" xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0">
  <groups>
    <group>
      <name>o1-admin</name>
      <user-name nc:operation="remove">${USERNAME_ESC}</user-name>
    </group>
  </groups>
</nacm>
EOF
        ;;
    *)
        echo "Usage: $0 grant|revoke <username>" >&2
        exit 1
        ;;
esac

sysrepocfg --edit "$NACM_XML" --datastore running -f xml -m ietf-netconf-acm
