# O1/Netconf-based Configuration Service for OCUDU

All commands should work with docker/podman

## Build container

`$ docker build -t ocudu-netconf/ocudu-netconf:latest . --progress=plain`

## Run netopeer2-server as standalone container

This command has to be called from within the main directory of this repo.

`$ docker run -it -p 830:830 -v "$(pwd)/default_config.xml:/config/default_config.xml" ocudu-netconf/ocudu-netconf:latest /config/default_config.xml`

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