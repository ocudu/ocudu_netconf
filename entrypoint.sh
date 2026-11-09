#!/bin/bash

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-FileCopyrightText: Copyright (C) 2026 OCUDU contributors
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

CONFIG_DIR=/opt/dev/configs
RUNNING_CONFIG=/etc/netconf-running/o1-config.xml
PROFILE_STATE=""
PRELOAD_CONFIG=""
CONFIG_VARIANT=""
YANG_PROFILE=""
TLS_ENABLED=0
TLS_CERT_DIR=/etc/netconf-tls
CALLHOME_TARGET=""
SSH_HOSTKEY_DIR=/etc/netconf-ssh
NETCONF_SSH_USERNAME="${NETCONF_SSH_USERNAME:-}"
NETCONF_SSH_PASSWORD="${NETCONF_SSH_PASSWORD:-}"
if [ -n "$NETCONF_SSH_USERNAME" ] || [ -n "$NETCONF_SSH_PASSWORD" ]; then
    if [ -z "$NETCONF_SSH_USERNAME" ] || [ -z "$NETCONF_SSH_PASSWORD" ]; then
        echo "Error: NETCONF_SSH_USERNAME and NETCONF_SSH_PASSWORD must be set together." >&2
        exit 1
    fi
fi

usage() {
    cat <<EOF
Usage:
  $0 --config <gnb|cu|cucp|cuup|du|ru> [--custom-config <path>] [--running-config <path>]
     [--enable-tls] [--tls-cert-dir <path>] [--enable-callhome <host>[:<port>]]
     [--ssh-hostkey-dir <path>]

Options:
  --config          Select the built-in YANG/profile setup and bundled config.
  --custom-config   Override the initial config XML loaded on first start (must be compatible with --config profile).
  --running-config  Override the internal persisted running-config path.
  --enable-tls      Enable a NETCONF-over-TLS listen endpoint on port 6513 alongside the default SSH endpoint.
  --tls-cert-dir    Directory containing ca.crt, server.crt, server.key, client.crt (default: /etc/netconf-tls).
  --enable-callhome Dial the given NETCONF call-home manager (RFC 8071); <host> is an IPv4 address or a
                    hostname (no IPv6 literal), port defaults to 4334.
  --ssh-hostkey-dir Directory containing ssh_host_ed25519_key, ssh_host_ecdsa_key or
                    ssh_host_rsa_key, the SSH host key the server presents (default:
                    /etc/netconf-ssh). Without one the ed25519 key built into the image is used.
  -h, --help        Show this help message.

Environment variables:
  NETCONF_SSH_USERNAME
                    Together with NETCONF_SSH_PASSWORD, create an ietf-ssh-server local
                    user with password authentication (RFC 9644) in the "default-ssh"
                    endpoint and grant it full NACM access. Enables the SSH "password"
                    method for clients that cannot do keyboard-interactive (e.g.
                    OpenDaylight). Default: unset, no user is created.
  NETCONF_SSH_PASSWORD
                    The user's password: a cleartext value is hashed with SHA-512 crypt
                    (openssl passwd -6) before it is stored, so only the hash ever reaches
                    the datastore; a value starting with \$ (a crypt(3) hash, e.g. \$6\$
                    from mkpasswd -m sha-512) is used verbatim.
  NETCONF_CONFIG_GENERATION
                    Any string. The running config saved on stop is loaded on the next start
                    only while this value, the --custom-config file and the installed YANG
                    modules are unchanged; otherwise the server starts from --custom-config.
                    Default: unset.
EOF
}

set_config_profile() {
    case "$1" in
        gnb)
            CONFIG_VARIANT=gnb
            YANG_PROFILE=gnb
            PRELOAD_CONFIG="$CONFIG_DIR/config_gnb.xml"
            ;;
        cu)
            CONFIG_VARIANT=cu
            YANG_PROFILE=cu
            PRELOAD_CONFIG="$CONFIG_DIR/config_cu.xml"
            ;;
        cucp)
            CONFIG_VARIANT=cucp
            YANG_PROFILE=cucp
            PRELOAD_CONFIG="$CONFIG_DIR/config_cucp.xml"
            ;;
        cuup)
            CONFIG_VARIANT=cuup
            YANG_PROFILE=cuup
            PRELOAD_CONFIG="$CONFIG_DIR/config_cuup.xml"
            ;;
        du)
            CONFIG_VARIANT=du
            YANG_PROFILE=du
            PRELOAD_CONFIG="$CONFIG_DIR/config_du.xml"
            ;;
        ru)
            CONFIG_VARIANT=ru
            YANG_PROFILE=ru
            PRELOAD_CONFIG="$CONFIG_DIR/config_ru.xml"
            ;;
        *)
            echo "Error: Unsupported built-in config '$1'. Use one of: gnb, cu, cucp, cuup, du, ru." >&2
            exit 1
            ;;
    esac
}

run_profile_setup() {
    case "$YANG_PROFILE" in
        gnb)
            /usr/local/bin/setup_gnb.sh
            ;;
        cu)
            /usr/local/bin/setup_cu.sh
            ;;
        cucp)
            /usr/local/bin/setup_cucp.sh
            ;;
        cuup)
            /usr/local/bin/setup_cuup.sh
            ;;
        du)
            /usr/local/bin/setup_du.sh
            ;;
        ru)
            # the standalone mock O-RU also serves the PM model; the DU-side
            # profiles reach setup_ru.sh through setup_du.sh without this flag
            /usr/local/bin/setup_ru.sh --standalone
            ;;
        *)
            echo "Error: Unsupported YANG profile '$YANG_PROFILE'." >&2
            exit 1
            ;;
    esac
}

merge_selected_config() {
    echo "Merging running config from $RUNNING_CONFIG into running datastore ..."
    sysrepocfg --edit "$RUNNING_CONFIG" --datastore running -f xml
}

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --config." >&2
                usage
                exit 1
            fi
            set_config_profile "$1"
            ;;
        --custom-config)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --custom-config." >&2
                usage
                exit 1
            fi
            PRELOAD_CONFIG="$1"
            ;;
        --running-config)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --running-config." >&2
                usage
                exit 1
            fi
            RUNNING_CONFIG="$1"
            ;;
        --enable-tls)
            TLS_ENABLED=1
            ;;
        --tls-cert-dir)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --tls-cert-dir." >&2
                usage
                exit 1
            fi
            TLS_CERT_DIR="$1"
            ;;
        --enable-callhome)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --enable-callhome." >&2
                usage
                exit 1
            fi
            CALLHOME_TARGET="$1"
            ;;
        --ssh-hostkey-dir)
            shift
            if [ -z "$1" ]; then
                echo "Error: Missing value for --ssh-hostkey-dir." >&2
                usage
                exit 1
            fi
            SSH_HOSTKEY_DIR="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "Error: Unknown option '$1'." >&2
            usage
            exit 1
            ;;
        *)
            echo "Error: Positional config files are not supported. Use --config <gnb|cu|cucp|cuup|du|ru>." >&2
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$CONFIG_VARIANT" ]; then
    echo "Error: Missing required --config <gnb|cu|cucp|cuup|du|ru> option." >&2
    usage
    exit 1
fi

if [ -z "$PRELOAD_CONFIG" ]; then
    echo "Error: Missing preload config."
    usage
    exit 1
fi

if [ ! -e "$PRELOAD_CONFIG" ]; then
    echo "Error: Preload config '$PRELOAD_CONFIG' does not exist." >&2
    exit 1
fi

mkdir -p "$(dirname "$RUNNING_CONFIG")"
PROFILE_STATE="$(dirname "$RUNNING_CONFIG")/yang-profile"
NETCONF_SSH_USER_STATE="$(dirname "$RUNNING_CONFIG")/netconf-ssh-user"

# protects against reusing persisted state of one profile (e.g. ru) with a different profile (e.g. du) when rerunning container with persisted state using docker -v option
if [ -e "$PROFILE_STATE" ]; then
    EXISTING_PROFILE="$(cat "$PROFILE_STATE")"
    if [ "$EXISTING_PROFILE" != "$YANG_PROFILE" ]; then
        echo "Error: Container already initialized with YANG profile '$EXISTING_PROFILE', not '$YANG_PROFILE'." >&2
        exit 1
    fi
fi

# In a Kubernetes pod /dev/shm outlives the container. sysrepo state left there by an earlier
# run does not match the fresh repository in this container and breaks every sysrepo call.
rm -f "${SYSREPO_SHM_DIR:-/dev/shm}/${SYSREPO_SHM_PREFIX:-sr}"_* "${SYSREPO_SHM_DIR:-/dev/shm}/${SYSREPO_SHM_PREFIX:-sr}"sub_*

run_profile_setup
printf '%s\n' "$YANG_PROFILE" > "$PROFILE_STATE"

CONFIG_FINGERPRINT_STATE="$(dirname "$RUNNING_CONFIG")/config-fingerprint"
NP_PID=""
CONFIG_LOADED=0

# Written to a temporary file first, so a stop in the middle never leaves half a config.
save_running_config() {
    sysrepocfg --export -d running > "$RUNNING_CONFIG.tmp" && mv -f "$RUNNING_CONFIG.tmp" "$RUNNING_CONFIG"
}

# Saves only once a config is loaded: a stop during the setup must not overwrite the saved
# config with a half-initialised datastore.
cleanup() {
    if [ "$CONFIG_LOADED" = "1" ]; then
        echo "Container stopped, exporting running config .."
        save_running_config
    fi
    if [ -n "$NP_PID" ]; then
        kill "$NP_PID" 2>/dev/null
        wait "$NP_PID"
    fi
}

trap 'cleanup; exit 0' SIGTERM SIGINT

# The saved config belongs to one initial config, one set of YANG modules and one
# NETCONF_CONFIG_GENERATION. When any of them changes, the server starts from the initial
# config again.
CONFIG_FINGERPRINT="$({
    sha256sum < "$PRELOAD_CONFIG"
    sysrepoctl -l | awk -F'|' 'NF > 3 { print $1 $2 $7 }'
    printf '%s\n' "${NETCONF_CONFIG_GENERATION:-}"
} | sha256sum | cut -d' ' -f1)"

if [ -e "$RUNNING_CONFIG" ] && [ "$(cat "$CONFIG_FINGERPRINT_STATE" 2>/dev/null)" = "$CONFIG_FINGERPRINT" ]; then
    echo "Importing existing config from last run $RUNNING_CONFIG .."
    # Fail closed: a saved config that no longer loads is never replaced by the initial one.
    if ! merge_selected_config; then
        echo "Error: The saved running config $RUNNING_CONFIG does not load." >&2
        exit 1
    fi
else
    if [ -e "$RUNNING_CONFIG" ]; then
        echo "Initial config, YANG modules or NETCONF_CONFIG_GENERATION changed, not loading $RUNNING_CONFIG .."
    fi
    echo "Importing config from configMap $PRELOAD_CONFIG .."
    if ! sysrepocfg --edit "$PRELOAD_CONFIG" --datastore running -f xml; then
        echo "Error: The initial config $PRELOAD_CONFIG does not load." >&2
        exit 1
    fi
    save_running_config || exit 1
    printf '%s\n' "$CONFIG_FINGERPRINT" > "$CONFIG_FINGERPRINT_STATE"
fi
CONFIG_LOADED=1

# Falls back to the image's ed25519 key when none is mounted. Fail closed: serving netopeer2's
# own genkey instead would lock out every client that verifies the provisioned one.
if ! /usr/local/bin/setup_ssh_hostkey.sh "$SSH_HOSTKEY_DIR"; then
    echo "Error: SSH host key setup failed." >&2
    exit 1
fi

# Optional ietf-ssh-server local user with password authentication for clients that
# cannot do keyboard-interactive (e.g. OpenDaylight). Runs after the config merge so
# the endpoint it targets exists; fail closed, the user is useless half-configured.
# The state file remembers which user the env vars created, so a start without the
# env vars removes the user again instead of leaving a working login in the
# persisted config, and a renamed user takes its grant along instead of leaking it.
if [ -n "$NETCONF_SSH_USERNAME" ]; then
    if [ -e "$NETCONF_SSH_USER_STATE" ]; then
        PREVIOUS_SSH_USER="$(cat "$NETCONF_SSH_USER_STATE")"
        if [ "$PREVIOUS_SSH_USER" != "$NETCONF_SSH_USERNAME" ]; then
            if ! /usr/local/bin/setup_ssh_user.sh --remove "$PREVIOUS_SSH_USER"; then
                echo "Error: NETCONF SSH user removal failed." >&2
                exit 1
            fi
        fi
    fi
    if ! /usr/local/bin/setup_ssh_user.sh "$NETCONF_SSH_USERNAME" "$NETCONF_SSH_PASSWORD"; then
        echo "Error: NETCONF SSH user setup failed." >&2
        exit 1
    fi
    printf '%s\n' "$NETCONF_SSH_USERNAME" > "$NETCONF_SSH_USER_STATE"
elif [ -e "$NETCONF_SSH_USER_STATE" ]; then
    PREVIOUS_SSH_USER="$(cat "$NETCONF_SSH_USER_STATE")"
    if ! /usr/local/bin/setup_ssh_user.sh --remove "$PREVIOUS_SSH_USER"; then
        echo "Error: NETCONF SSH user removal failed." >&2
        exit 1
    fi
    rm -f "$NETCONF_SSH_USER_STATE"
fi

if [ "$TLS_ENABLED" = "1" ]; then
    /usr/local/bin/setup_tls.sh "$TLS_CERT_DIR"
fi

if [ -n "$CALLHOME_TARGET" ]; then
    CALLHOME_HOST="${CALLHOME_TARGET%%:*}"
    case "$CALLHOME_TARGET" in
        *:*) CALLHOME_PORT="${CALLHOME_TARGET#*:}" ;;
        *)   CALLHOME_PORT=4334 ;;
    esac
    /usr/local/bin/setup_callhome.sh "$CALLHOME_HOST" "$CALLHOME_PORT" || exit 1
fi

echo "Starting netconf server .."
# Default pidfile lives under /run (root-owned) --> overwrite with /tmp
# In the background: bash runs a trap only once the foreground command returns, and wait
# returns as soon as a trapped signal arrives.
netopeer2-server -v2 -d -p /tmp/netopeer2-server.pid &
NP_PID=$!
wait "$NP_PID"
NP_STATUS=$?

# The server exited on its own: the datastore is still there, so keep what it held.
echo "Netconf server exited ($NP_STATUS), exporting running config .."
save_running_config
exit "$NP_STATUS"
