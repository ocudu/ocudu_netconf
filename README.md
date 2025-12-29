# Netconf-based Configuration Service for srsRAN

### Build container

`$ docker build -t srsran-sysrepo/srsran-sysrepo:latest . --progress=plain`

### Run with Docker compose

This automatically adds the container into the SMO network

`$ docker compose up`

## Run netopeer2-server as standalone container

`$ docker run -it -p 830:830 srsran-sysrepo/srsran-sysrepo:v1`

## Run with console access

`$ docker run --entrypoint /bin/bash -it -p 830:830 srsran-sysrepo/srsran-sysrepo:v1`

## Connect with netopeer2-client

Get shell in srsran-sysrepo container and execute:

```
$ netopeer2-cli
> connect --login root
> edit-config --target running --config=cellConfig.xml
> get-config --source=running
```

## Modify config in datastore

`$ sysrepocfg -E nano --datastore running --format xml`

## Get IP address

To be later able to add the srsRAN CU/DU as ORAN components into the SMO we need to
know the assigned IP address to the srsran-sysrepo container. To do that check the 

`$ docker network inspect smo_integration | grep -i ipaddress`