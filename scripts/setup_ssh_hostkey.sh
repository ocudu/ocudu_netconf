#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -euo pipefail

KEY_DIR="${1:-/etc/netconf-ssh}"

# The image's host key is the same in every container from a tag and changes on every rebuild,
# so a client that pins it breaks on the next image bump. A mounted key replaces it in the
# keystore entry 'genkey' the SSH endpoint refers to by name, so no endpoint config changes.
# One entry holds one key: take the first of the names 'ssh-keygen -A' writes, strongest first.
# The last candidate is the image's own ed25519 key, which keeps netopeer2's RSA genkey - the
# one no verifying client can negotiate - from ever being served.
HOST_KEY=""
for candidate in \
        "$KEY_DIR/ssh_host_ed25519_key" \
        "$KEY_DIR/ssh_host_ecdsa_key" \
        "$KEY_DIR/ssh_host_rsa_key" \
        /etc/netconf-ssh-default/ssh_host_ed25519_key; do
    if [ -e "$candidate" ]; then
        HOST_KEY="$candidate"
        break
    fi
done

if [ -z "$HOST_KEY" ]; then
    echo "No SSH host key in $KEY_DIR — keeping the host key generated in the image."
    exit 0
fi

# Looser than 0640 is usable but readable by every user in the container. -L because a
# Kubernetes Secret arrives as a symlink into ..data/, whose own mode is always 0777; the
# kubelet lands the file itself at 0440 whenever a fsGroup is set.
KEY_PERMS="$(stat -Lc %a "$HOST_KEY")"
case "$KEY_PERMS" in
    400|440|600|640) ;;
    *) echo "Warning: SSH host key '$HOST_KEY' is mode $KEY_PERMS — mount it 0400 (0440 under Kubernetes)." >&2 ;;
esac

KEY_COPY="$(mktemp)"
HOSTKEY_XML="$(mktemp)"
trap 'rm -f "$KEY_COPY" "$HOSTKEY_XML"' EXIT

# ssh-keygen refuses to read a group- or world-readable private key, which is how a Secret
# arrives; mktemp gives 0600.
cat "$HOST_KEY" > "$KEY_COPY"

# Also the validity check: ssh-keygen reads every encoding it writes and fails on a malformed
# one. -P '' makes an encrypted key fail here instead of blocking on the passphrase prompt.
if ! PUBLIC_KEY="$(ssh-keygen -y -P '' -f "$KEY_COPY" 2>/dev/null)"; then
    echo "Error: No readable unencrypted private key in '$HOST_KEY'." >&2
    exit 1
fi

# Each identity covers RSA, EC and ED25519 alike - only the encoding is named. The np2 ones are
# libnetconf2 augments: OpenSSH is what ssh-keygen writes by default, PKCS#8 what openssl does.
case "$(head -1 "$KEY_COPY")" in
    *"BEGIN OPENSSH PRIVATE KEY"*) KEY_FORMAT="np2:openssh-private-key-format" ;;
    *"BEGIN PRIVATE KEY"*)         KEY_FORMAT="np2:private-key-info-format" ;;
    *"BEGIN RSA PRIVATE KEY"*)     KEY_FORMAT="ct:rsa-private-key-format" ;;
    *"BEGIN EC PRIVATE KEY"*)      KEY_FORMAT="ct:ec-private-key-format" ;;
    *)
        echo "Error: Unrecognised private key encoding in '$HOST_KEY' — expected a PEM header." >&2
        exit 1
        ;;
esac

if [ "$(printf '%s' "$PUBLIC_KEY" | awk '{print $1}')" = "ssh-rsa" ]; then
    echo "Warning: '$HOST_KEY' is an RSA key. known_hosts records it as 'ssh-rsa' but this server offers only rsa-sha2-256/512, so the O1 adapter cannot verify it — provision ed25519 or ecdsa instead." >&2
fi

# Derived from the copy, not from a '.pub': a Secret usually carries the private key alone.
FINGERPRINT="$(printf '%s\n' "$PUBLIC_KEY" | ssh-keygen -l -f - | awk '{print $2}')"
echo "Installing provisioned SSH host key $HOST_KEY ($FINGERPRINT) as $KEY_FORMAT ..."

# ietf-keystore wants the bare base64 of that encoding, which is the PEM body without armour.
PRIVATE_KEY_B64="$(grep -v -- "-----" "$KEY_COPY" | tr -d '\n')"

cat >"$HOSTKEY_XML" <<EOF
<keystore xmlns="urn:ietf:params:xml:ns:yang:ietf-keystore">
  <asymmetric-keys>
    <asymmetric-key>
      <name>genkey</name>
      <public-key-format xmlns:ct="urn:ietf:params:xml:ns:yang:ietf-crypto-types">ct:ssh-public-key-format</public-key-format>
      <private-key-format xmlns:ct="urn:ietf:params:xml:ns:yang:ietf-crypto-types" xmlns:np2="urn:cesnet:libnetconf2-netconf-server">${KEY_FORMAT}</private-key-format>
      <cleartext-private-key>${PRIVATE_KEY_B64}</cleartext-private-key>
    </asymmetric-key>
  </asymmetric-keys>
</keystore>
EOF

sysrepocfg --edit "$HOSTKEY_XML" --datastore running -f xml -m ietf-keystore
