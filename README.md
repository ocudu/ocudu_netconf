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

The trust model is the same in both modes: the server accepts any client cert that chains to the trusted `ca.crt`, and the cert's Common Name becomes the NETCONF username via the `cert-to-name` mapping (`map-type=common-name`). So a client cert with `CN=root` connects as the `root` netconf user. In self-signed mode that's only the auto-generated `client.crt`; in operator-provisioned mode it's anyone holding a cert signed by your CA — provision and revoke accordingly.

To connect from outside the container as a NETCONF client over TLS (e.g. via `ncclient.manager.connect_tls(host="localhost", port=6513, ...)` against a self-signed run), copy the auto-generated client cert + key + CA out of the running container:

```bash
mkdir -p tls
docker cp ocudu-netconf:/etc/netconf-tls/ca.crt     tls/ca.crt
docker cp ocudu-netconf:/etc/netconf-tls/client.crt tls/client.crt
docker cp ocudu-netconf:/etc/netconf-tls/client.key tls/client.key
```

Replace `ocudu-netconf` above with the running container's name (from `docker ps`) — not the image name; under docker-compose use `docker compose cp <service>:...` instead. Point your client at `tls/client.{crt,key}` for mutual auth, with `tls/ca.crt` as the trust anchor for the server's cert.

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
