#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

source /usr/local/bin/sysrepo_common.sh

USER_XML=""

cleanup() {
    rm -f "$USER_XML"
}
trap cleanup EXIT

# OpenDaylight-based controllers only implement the SSH "password" method, which the
# stock server never offers because its local users all use system authentication
# (keyboard-interactive). An ietf-ssh-server local user with a password (RFC 9644)
# enables that method for exactly this user. The user goes into the stock endpoint
# "default-ssh", whatever its port override says.
create_user() {
    local username="$1"
    local password="$2"
    local username_esc hashed_password

    # libnetconf2 compares <hashed-password> directly against a crypt(3) hash, so the
    # cleartext is hashed with SHA-512 crypt: the hash is XML-safe (no & or < to break
    # the fragment) and only the hash is ever stored, so the running config exported
    # on container stop never contains the password. A value starting with $ is a
    # pre-built crypt string (e.g. $6$ from mkpasswd -m sha-512 / openssl passwd -6)
    # and is used verbatim.
    case "$password" in
        '$'*) hashed_password="$password" ;;
        *) hashed_password="$(openssl passwd -6 "$password")" ;;
    esac
    username_esc="$(xml_escape "$username")"

    echo "Configuring NETCONF SSH user '$username' with password authentication ..."

    USER_XML="$(mktemp)"

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
                  <name>${username_esc}</name>
                  <password>
                    <hashed-password>${hashed_password}</hashed-password>
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

    # Full NACM access through the shared "o1-admin" group, not the recovery user root.
    /usr/local/bin/nacm_admin.sh grant "$username"

    echo "NETCONF SSH user '$username' configured."
}

# The inverse of create_user, for the next start without the env vars: without it a
# working login would survive in the persisted running config. nc:operation="remove"
# deletes the nodes when present and passes silently when they are already gone.
remove_user() {
    local username="$1"
    local username_esc
    username_esc="$(xml_escape "$username")"

    echo "Removing NETCONF SSH user '$username' ..."

    USER_XML="$(mktemp)"

    cat >"$USER_XML" <<EOF
<netconf-server xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-server" xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0">
  <listen>
    <endpoints>
      <endpoint>
        <name>default-ssh</name>
        <ssh>
          <ssh-server-parameters>
            <client-authentication>
              <users>
                <user nc:operation="remove">
                  <name>${username_esc}</name>
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

    # Other members of "o1-admin" (e.g. the TLS client CN) keep their access.
    /usr/local/bin/nacm_admin.sh revoke "$username"

    echo "NETCONF SSH user '$username' removed."
}

case "${1:-}" in
    --remove)
        if [ -z "${2:-}" ]; then
            echo "Error: --remove needs the username to remove." >&2
            exit 1
        fi
        remove_user "$2"
        ;;
    *)
        if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
            echo "Error: NETCONF_SSH_USERNAME and NETCONF_SSH_PASSWORD must be set together." >&2
            exit 1
        fi
        create_user "$1" "$2"
        ;;
esac
