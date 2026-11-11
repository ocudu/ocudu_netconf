#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 Cognitive Network Solutions, Inc.
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

# Configure a NETCONF call-home (RFC 8071) client so the server dials the
# given manager instead of (only) listening — emulating an O-RU that accepts
# no inbound NETCONF. The endpoint reuses the default SSH server identity
# (the netopeer2-provisioned "genkey" keystore entry) and refers to the
# default listen endpoint for user authentication, so it accepts exactly the
# users that endpoint does, including the one setup_ssh_user.sh provisions;
# the persistent connection type keeps one connection up and re-dials when
# it drops.

set -euo pipefail

CALLHOME_HOST="${1:?usage: setup_callhome.sh <manager-host> [port]}"
CALLHOME_PORT="${2:-4334}"

CALLHOME_XML="$(mktemp)"
trap 'rm -f "$CALLHOME_XML"' EXIT

cat > "$CALLHOME_XML" <<EOF
<netconf-server xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-server">
  <call-home>
    <netconf-client>
      <name>callhome-manager</name>
      <endpoints>
        <endpoint>
          <name>callhome-ssh</name>
          <ssh>
            <tcp-client-parameters>
              <remote-address>${CALLHOME_HOST}</remote-address>
              <remote-port>${CALLHOME_PORT}</remote-port>
            </tcp-client-parameters>
            <ssh-server-parameters>
              <server-identity>
                <host-key>
                  <name>default-key</name>
                  <public-key>
                    <central-keystore-reference>genkey</central-keystore-reference>
                  </public-key>
                </host-key>
              </server-identity>
              <client-authentication>
                <endpoint-reference xmlns="urn:cesnet:libnetconf2-netconf-server">default-ssh</endpoint-reference>
              </client-authentication>
            </ssh-server-parameters>
          </ssh>
        </endpoint>
      </endpoints>
      <connection-type><persistent/></connection-type>
    </netconf-client>
  </call-home>
</netconf-server>
EOF

echo "Applying call-home config (dialing ${CALLHOME_HOST}:${CALLHOME_PORT}) to sysrepo running datastore ..."
sysrepocfg --edit "$CALLHOME_XML" --datastore running -f xml
