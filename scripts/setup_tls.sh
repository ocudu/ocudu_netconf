#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

CERT_DIR="${1:-/etc/netconf-tls}"
# Client cert CN becomes the NETCONF username (cert-to-name). Override to escape sysrepo's NACM-recovery user.
CLIENT_CN="${CLIENT_CN:-root}"

SERVER_CRT="$CERT_DIR/server.crt"
SERVER_KEY="$CERT_DIR/server.key"
CA_CRT="$CERT_DIR/ca.crt"

# Bootstrap a self-signed CA + server + client cert if the cert dir has no CA.
# Production deployments mount their own ca.crt/server.{crt,key} into $CERT_DIR;
# the presence of ca.crt is the sentinel for "operator-provisioned, do not touch".
if [ ! -e "$CA_CRT" ]; then
    echo "No CA cert in $CERT_DIR — bootstrapping self-signed CA + server + client cert ..."
    mkdir -p "$CERT_DIR"

    # CA (self-signed): 2048-bit RSA key + X.509 cert in one call.
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 30 \
        -keyout "$CERT_DIR/ca.key" -out "$CA_CRT" \
        -subj "/CN=ocudu-netconf-ca" >/dev/null 2>&1

    # Server: generate key + CSR (CN=ocudu-netconf, the docker-compose hostname).
    openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$SERVER_KEY" -out "$CERT_DIR/server.csr" \
        -subj "/CN=ocudu-netconf" >/dev/null 2>&1

    # Server: sign the server CSR with the CA.
    openssl x509 -req -in "$CERT_DIR/server.csr" \
        -CA "$CA_CRT" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
        -out "$SERVER_CRT" -days 30 -sha256 >/dev/null 2>&1

    # Client: generate key + CSR (CN=$CLIENT_CN, drives the cert-to-name mapping).
    # When connecting to the netconf server, the client authenticates as this
    # username — the cert-to-name uses map-type=common-name to derive it.
    openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$CERT_DIR/client.key" -out "$CERT_DIR/client.csr" \
        -subj "/CN=$CLIENT_CN" >/dev/null 2>&1
        
    # Client: sign the client CSR with the CA.
    openssl x509 -req -in "$CERT_DIR/client.csr" \
        -CA "$CA_CRT" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
        -out "$CERT_DIR/client.crt" -days 30 -sha256 >/dev/null 2>&1

    chmod 0644 "$CERT_DIR"/*.crt "$CERT_DIR"/*.key
fi

for f in "$SERVER_CRT" "$SERVER_KEY" "$CA_CRT"; do
    if [ ! -r "$f" ]; then
        echo "Error: required TLS file '$f' missing or unreadable." >&2
        exit 1
    fi
done

# Re-encode as DER + 64-col base64 (libyang rejects multi-object/odd-wrapped PEM,
# leaving the TLS endpoint uninstalled). x509 takes the leaf/first cert.
SERVER_CRT_B64="$(openssl x509 -in "$SERVER_CRT" -outform DER | openssl base64)"
SERVER_KEY_B64="$(openssl pkey -in "$SERVER_KEY" -outform DER | openssl base64)"
SERVER_PUB_B64="$(openssl x509 -in "$SERVER_CRT" -noout -pubkey | openssl pkey -pubin -outform DER | openssl base64)"

# The CA file may be a chain (e.g. intermediate + root); emit one bag entry per cert
CA_CERTS_XML=""
ca_idx=0
ca_pem=""
while IFS= read -r line || [ -n "$line" ]; do
    ca_pem="$ca_pem$line"$'\n'
    case "$line" in
        *"-----END CERTIFICATE-----"*)
            ca_idx=$((ca_idx + 1))
            CA_CERT_B64="$(printf '%s' "$ca_pem" | openssl x509 -outform DER | openssl base64)"
            CA_CERTS_XML="$CA_CERTS_XML
      <certificate>
        <name>netconf-tls-ca-${ca_idx}</name>
        <cert-data>${CA_CERT_B64}</cert-data>
      </certificate>"
            ca_pem=""
            ;;
    esac
done < "$CA_CRT"

TLS_XML="$(mktemp)"
trap 'rm -f "$TLS_XML"' EXIT

cat >"$TLS_XML" <<EOF
<keystore xmlns="urn:ietf:params:xml:ns:yang:ietf-keystore">
  <asymmetric-keys>
    <asymmetric-key>
      <name>netconf-tls-key</name>
      <public-key-format xmlns:ct="urn:ietf:params:xml:ns:yang:ietf-crypto-types">ct:subject-public-key-info-format</public-key-format>
      <public-key>${SERVER_PUB_B64}</public-key>
      <private-key-format xmlns:ct="urn:ietf:params:xml:ns:yang:ietf-crypto-types">ct:rsa-private-key-format</private-key-format>
      <cleartext-private-key>${SERVER_KEY_B64}</cleartext-private-key>
      <certificates>
        <certificate>
          <name>netconf-tls-cert</name>
          <cert-data>${SERVER_CRT_B64}</cert-data>
        </certificate>
      </certificates>
    </asymmetric-key>
  </asymmetric-keys>
</keystore>
<truststore xmlns="urn:ietf:params:xml:ns:yang:ietf-truststore">
  <certificate-bags>
    <certificate-bag>
      <name>netconf-tls-cacerts</name>${CA_CERTS_XML}
    </certificate-bag>
  </certificate-bags>
</truststore>
<netconf-server xmlns="urn:ietf:params:xml:ns:yang:ietf-netconf-server">
  <listen>
    <endpoints>
      <endpoint>
        <name>netconf-tls</name>
        <tls>
          <tcp-server-parameters>
            <local-bind>
              <local-address>0.0.0.0</local-address>
              <local-port>6513</local-port>
            </local-bind>
          </tcp-server-parameters>
          <tls-server-parameters>
            <server-identity>
              <certificate>
                <central-keystore-reference>
                  <asymmetric-key>netconf-tls-key</asymmetric-key>
                  <certificate>netconf-tls-cert</certificate>
                </central-keystore-reference>
              </certificate>
            </server-identity>
            <client-authentication>
              <ca-certs>
                <central-truststore-reference>netconf-tls-cacerts</central-truststore-reference>
              </ca-certs>
            </client-authentication>
          </tls-server-parameters>
          <netconf-server-parameters>
            <client-identity-mappings>
              <cert-to-name>
                <id>1</id>
                <map-type xmlns:x509c2n="urn:ietf:params:xml:ns:yang:ietf-x509-cert-to-name">x509c2n:common-name</map-type>
                <!-- no <name> needed; the cert's CN is the username -->
              </cert-to-name>
            </client-identity-mappings>
          </netconf-server-parameters>
        </tls>
      </endpoint>
    </endpoints>
  </listen>
</netconf-server>
EOF

echo "Applying TLS endpoint config to sysrepo running datastore ..."
sysrepocfg --edit "$TLS_XML" --datastore running -f xml
