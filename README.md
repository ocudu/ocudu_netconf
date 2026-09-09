# O1/Netconf-based Configuration Service for OCUDU

All commands should work with docker/podman

## Build container

`$ docker build -t ocudu-netconf/ocudu-netconf:latest . --progress=plain`

## Run netopeer2-server as standalone container

This command has to be called from within the main directory of this repo.

Use one of the built-in configs bundled in the image:

`$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config gnb`

`$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config cu`

`$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config cucp`

`$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config cuup`

`$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config du`

`$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config ru`

On first start, the selected config also triggers the matching YANG setup script inside the container.

## Enable NETCONF over TLS

Pass `--enable-tls` to expose a TLS endpoint on port `6513` alongside the SSH endpoint on `830`:

```
$ docker run -it -p 830:830 -p 6513:6513 \
    -v tls-certs:/etc/netconf-tls \
    ocudu-netconf/ocudu-netconf:latest --config gnb --enable-tls
```

The cert dir (default `/etc/netconf-tls`, override with `--tls-cert-dir <path>`) is dual-mode:

- **Empty / unprovisioned** (no `ca.crt` present): on first start the container self-signs a CA plus matching server and client certs into the dir. Useful for dev / lab / integration tests.
- **Operator-provisioned** (`ca.crt` already present): the container leaves the dir alone and uses the operator's `ca.crt` + `server.crt` + `server.key` as-is. Use this for production — mount your CA-issued material into `/etc/netconf-tls` (e.g. via a Kubernetes Secret with `readOnly: true`).

The trust model is the same in both modes: the server accepts any client cert that chains to the trusted `ca.crt`, and the cert's Common Name becomes the NETCONF username via the `cert-to-name` mapping (`map-type=common-name`). So a client cert with `CN=root` connects as the `root` netconf user. In self-signed mode those are the two auto-generated client certs; in operator-provisioned mode it's anyone holding a cert signed by your CA — provision and revoke accordingly.

Self-signed mode issues two client identities:

- `client.crt` / `client.key` with `CN=root` (override with `CLIENT_CN=<name>`). `root` is sysrepo's recovery user and bypasses NACM; set `CLIENT_CN=mplane` to connect as the read-only `mplane-ro` group of the `ru` profile.
- `client-hybrid-odu.crt` / `client-hybrid-odu.key` with `CN=hybrid-odu` (override with `HYBRID_ODU_CN=<name>`). In the `ru` profile this user is in the `hybrid-odu` NACM group, whose rule-list in `configs/config_ru.xml` grants the hybrid-odu access of the O-RAN WG4 M-plane spec, Table 6.5-1.

No system user is needed for either name; the username only feeds NACM.

To connect from outside the container as a NETCONF client over TLS (e.g. via `ncclient.manager.connect_tls(host="localhost", port=6513, ...)` against a self-signed run), copy the auto-generated client cert + key + CA out of the running container:

```bash
mkdir -p tls
docker cp ocudu-netconf:/etc/netconf-tls/ca.crt     tls/ca.crt
docker cp ocudu-netconf:/etc/netconf-tls/client.crt tls/client.crt
docker cp ocudu-netconf:/etc/netconf-tls/client.key tls/client.key
```

For the hybrid-odu identity copy `client-hybrid-odu.crt` / `client-hybrid-odu.key` instead.

Replace `ocudu-netconf` above with the running container's name (from `docker ps`) — not the image name; under docker-compose use `docker compose cp <service>:...` instead. Point your client at `tls/client.{crt,key}` for mutual auth, with `tls/ca.crt` as the trust anchor for the server's cert.

## Enable NETCONF call-home

Pass `--enable-callhome <host>[:<port>]` to make the server dial a NETCONF
call-home manager (RFC 8071) at the given address (port defaults to `4334`)
alongside its normal listen endpoint — emulating an O-RU that accepts no
inbound NETCONF and calls its manager instead. The connection is persistent:
the server keeps one connection up and re-dials when it drops. Server
identity and user authentication are the same as on the listen endpoint.

```
$ docker run -it -p 830:830 ocudu-netconf/ocudu-netconf:latest --config ru --enable-callhome 172.17.0.1:4334
```

## Provision the SSH host key

The host key is generated at image build time, so it is the same in every container from a tag
and different after every rebuild — breaking any client that pins it.

Mount your own instead. The key dir (default `/etc/netconf-ssh`, override with
`--ssh-hostkey-dir <path>`) is read on every start, and the first of `ssh_host_ed25519_key`,
`ssh_host_ecdsa_key`, `ssh_host_rsa_key` found is installed and its fingerprint logged:

```bash
ssh-keygen -t ed25519 -N "" -f ./ssh_host_ed25519_key
docker run -it -p 830:830 -v $PWD:/etc/netconf-ssh:ro \
    ocudu-netconf/ocudu-netconf:latest --config gnb

# clients verify it against this; the bracket form is needed off port 22
printf '[%s]:%s %s\n' ocudu-netconf 830 "$(cut -d' ' -f1,2 ./ssh_host_ed25519_key.pub)" > known_hosts
```

Any unencrypted encoding `ssh-keygen` writes is accepted (OpenSSH, `-m PEM`, `-m PKCS8`); an
encrypted one is refused, not prompted for. Use ed25519 or ecdsa — an RSA key is recorded in
`known_hosts` as `ssh-rsa` but offered as `rsa-sha2-512`/`rsa-sha2-256`, so a client narrowing
to the recorded name cannot negotiate it. Mounting one is warned about, not refused: it still
serves clients that handle the mismatch, but the O1 adapter will not verify it.

With no key mounted the server installs the ed25519 key generated into the image at build time,
which is stable per image tag and changes on every rebuild.

Mount the key `0400`. Under Kubernetes the pod needs a `fsGroup`: the kubelet chowns the
projected Secret to `root:<fsGroup>` and widens the mode so the server (uid 1000) can read it.

## Run with console access

`$ docker run --entrypoint /bin/bash -it -p 830:830 ocudu-netconf/ocudu-netconf:latest`

## Connect with netopeer2-client

Get shell in the ocudu-netconf container and execute:

```
$ netopeer2-cli
> connect --login root
> edit-config --target running --config=cellConfig.xml
> get-config --source=running
```

## Modify config in datastore

`$ sysrepocfg -E nano --datastore running --format xml`

## Get IP address

To be later able to add the OCUDU gNB/CU/DU as ORAN components into the SMO we need to
know the assigned IP address to the ocudu-netconf container. To do that, check the output of:

`$ docker network inspect smo_integration | grep -i ipaddress`
