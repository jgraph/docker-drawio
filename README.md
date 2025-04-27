[![Build Status](https://github.com/jgraph/docker-drawio/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/jgraph/docker-drawio/actions)
[![Build Status](https://github.com/jgraph/docker-drawio/workflows/Docker%20image-export%20CI/badge.svg)](https://github.com/jgraph/docker-drawio/actions)


## Introduction

[draw.io](https://github.com/jgraph/drawio) is a whiteboarding / diagramming software application. This project contains various docker implementations of draw.io and associated tools:

* draw.io docker image that is always up-to-date with draw.io releases
* draw.io export server image which allow exporting draw.io diagrams to pdf and images
* docker-compose to run draw.io with the export server
* docker-compose to run draw.io integrated within nextcloud
* docker-compose to run draw.io self-contained without any dependency on diagrams.net website (with the export server, plantUml, Google Drive support, OneDrive support, and EMF conversion support (for VSDX export)

## Description

The Dockerfile builds from `tomcat:9-jre11` (see <https://hub.docker.com/_/tomcat/>)

**Note: Starting from version 16.5.3, alpine and debian images are no longer maintained. We changed to a single image that uses the tomcat image with the least security vulnerabilities.**

Forked from [fjudith/draw.io](https://github.com/fjudith/docker-draw.io)

## Features

* Based on Tomcat so it can be used directly or behind a reverse-proxy
* Self-Signed certificate autogen
* Let's encrypt certificate autogen
* Support SSL Keystore mount to `/user/local/tomcat/.keystore`

## Quick Start

Run the container.

```bash
docker run -it --rm --name="draw" -p 8080:8080 -p 8443:8443 jgraph/drawio
```

Start a web browser session to <http://localhost:8080/?offline=1&https=0> or <https://localhost:8443/?offline=1>

If you're running `Docker Toolbox` then start a web browser session to <http://192.168.99.100:8080/?offline=1&https=0> or <https://192.168.99.100:8443/?offline=1>

> `?offline=1` is a security feature that disables support of cloud storage.

## Environment variables

* **LETS_ENCRYPT_ENABLED**: Enables Let's Encrypt certificate instead of self-signed; default `false`
* **PUBLIC_DNS**: DNS domain to be used as certificate "CN" record; default `draw.example.com`
* **ORGANISATION_UNIT**: Organisation unit to be used as certificate "OU" record; default `Cloud Native Application`
* **ORGANISATION**: Organisation name to be used as certificate "O" record; default `example inc`
* **CITY**: City name to be used as certificate "L" record; default `Paris`
* **STATE**: State name to be used as certificate "ST" record; default `Paris`
* **COUNTRY_CODE**: Country code to be used as certificate "C" record; default `FR`
* **KEYSTORE_PASS**: ".keystore"/.jks" store password; default `V3ry1nS3cur3P4ssw0rd`
* **KEY_PASS**: Private key password; default `<ref:KEYSTORE_PASS>`

## HTTPS SSL Certificate via Let's Encrypt

### Prerequisites:

1. A Linux machine connected to the Internet with ports 443 and 80 open
1. A domain/subdomain name pointing to this machine's IP address. (e.g., drawio.example.com)

### Method:

1. Create a directory to store the letsencrypt data. (e.g., /opt/docker/drawiodata/letsencrypt-log, /opt/docker/drawiodata/letsencrypt-etc, /opt/docker/drawiodata/letsencrypt-lib)
2. Using jgraph/drawio docker image, run the following command
```bash
docker run -it -m1g -v "/opt/docker/drawiodata/letsencrypt-log:/var/log/letsencrypt/" -v "/opt/docker/drawiodata/letsencrypt-etc:/etc/letsencrypt/" -v "/opt/docker/drawiodata/letsencrypt-lib:/var/lib/letsencrypt" -e LETS_ENCRYPT_ENABLED=true -e PUBLIC_DNS=drawio.example.com --rm --name="draw" -p 80:80 -p 443:8443 jgraph/drawio
```
Notice that mapping port 80 to container's port 80 allows certbot to work in stand-alone mode. Mapping port 443 to container's port 8443 allows the container tomcat to serve https requests directly.

## Changing draw.io configuration

Configuration is managed by `DRAWIO_*` environment variables. For example, these variables allow enabling integration with Google Drive, OneDrive, ...

* **DRAWIO_GITLAB_ID**: blablabla; default ``
* **DRAWIO_CSP_HEADER**: blablabla; default ``
* **DRAWIO_SELF_CONTAINED**: blablabla; default ``
* **DRAWIO_SERVER_URL**: blablabla; default ``
* **DRAWIO_BASE_URL**: blablabla; default ``
* **DRAWIO_VIEWER_URL**: blablabla; default ``
* **DRAWIO_LIGHTBOX_URL**: blablabla; default ``
* **DRAWIO_GOOGLE_CLIENT_ID**: blablabla; default ``
* **DRAWIO_GOOGLE_APP_ID**: blablabla; default ``
* **DRAWIO_GOOGLE_CLIENT_SECRET**: blablabla; default ``
* **DRAWIO_GOOGLE_VIEWER_CLIENT_ID**: blablabla; default ``
* **DRAWIO_MSGRAPH_CLIENT_ID**: blablabla; default ``
* **DRAWIO_MSGRAPH_CLIENT_SECRET**: blablabla; default ``
* **DRAWIO_MSGRAPH_TENANT_ID**: blablabla; default ``
* **DRAWIO_GITLAB_ID**: blablabla; default ``
* **DRAWIO_GITLAB_URL**: blablabla; default ``
* **DRAWIO_GITLAB_SECRET**: blablabla; default ``
* **DRAWIO_CLOUD_CONVERT_APIKEY**: blablabla; default ``


For any missing variables, check the `docker-entrypoint.sh` file in the `main` directory.
## SOC 2

This repo is not covered by the JGraph SOC 2 process.

## Reference

* <https://github.com/jgraph/drawio>
