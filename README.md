[![Build Status](https://github.com/jgraph/docker-drawio/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/jgraph/docker-drawio/actions)
[![Build Status](https://github.com/jgraph/docker-drawio/workflows/Docker%20image-export%20CI/badge.svg)](https://github.com/jgraph/docker-drawio/actions)


## Introduction

[draw.io](https://github.com/jgraph/drawio) is a whiteboarding / diagramming software application. This project contains various docker implementations of draw.io and associated tools:

* draw.io docker image that is always up-to-date with draw.io releases
* draw.io export server image which allow exporting draw.io diagrams to pdf and images
* docker-compose to run draw.io with the export server
* docker-compose to run draw.io integrated within nextcloud
* docker-compose to run draw.io self-contained without any dependency on diagrams.net website (with the export server, Google Drive support, and OneDrive support)

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

## Running as a non-root user

Both images already run as a dedicated non-root user by default — `tomcat` (UID `1001`, GID `999`) in `jgraph/drawio` and `pptruser` (UID `999`) in `jgraph/export-server` — so nothing needs to be configured just to avoid root.

+This image also works with Podman (including rootless Podman).

To run under a *different* UID (a compose `user:` override, Kubernetes `runAsUser`, or OpenShift's arbitrary UIDs), the user must carry the **root group (GID `0`)**. Configuration is applied at startup by rewriting files inside the container ([`main/docker-entrypoint.sh`](main/docker-entrypoint.sh)), and both images grant GID `0` owner-equivalent permissions on those paths, following the OpenShift image guidelines. Membership of group `0` grants no other privileges — it is not root.

```bash
docker run -it --rm -p 8080:8080 --user 1234:0 jgraph/drawio
```

docker-compose — either set group `0` directly or keep your own GID and add it as a supplementary group:

```yaml
services:
  drawio:
    image: jgraph/drawio
    user: "1234:1234"
    group_add:
      - "0"
```

Kubernetes:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1234
  runAsGroup: 0        # or keep your own runAsGroup and add supplementalGroups: [0]
```

On OpenShift, restricted SCCs already run pods with an arbitrary UID and GID `0`, so both images work there without any extra configuration.

Without GID `0` the main container still starts, but the entrypoint logs a warning and skips all runtime configuration (`DRAWIO_*` variables, SSL, context path), and the export server fails to render because Chrome cannot write its profile directory.

> `readOnlyRootFilesystem: true` is not currently supported, since configuration is written into the webapp at startup.

## Environment variables

All container behaviour is controlled by environment variables, processed by [`main/docker-entrypoint.sh`](main/docker-entrypoint.sh) at startup and written into `PreConfig.js` / `PostConfig.js` inside the deployed webapp.

### Certificate and SSL

* **LETS_ENCRYPT_ENABLED**: Enables Let's Encrypt certificate instead of self-signed; default `false`
* **PUBLIC_DNS**: DNS domain to be used as certificate "CN" record; default `draw.example.com`
* **ORGANISATION_UNIT**: Organisation unit to be used as certificate "OU" record; default `Cloud Native Application`
* **ORGANISATION**: Organisation name to be used as certificate "O" record; default `example inc`
* **CITY**: City name to be used as certificate "L" record; default `Paris`
* **STATE**: State name to be used as certificate "ST" record; default `Paris`
* **COUNTRY_CODE**: Country code to be used as certificate "C" record; default `FR`
* **KEYSTORE_PASS**: ".keystore"/".jks" store password; default `V3ry1nS3cur3P4ssw0rd`
* **KEY_PASS**: Private key password; default `<ref:KEYSTORE_PASS>`

### Deployment URL

* **DRAWIO_SERVER_URL**: Public deployment URL **with a trailing slash**, e.g. `https://drawio.example.com/`, or `https://www.example.com/drawio/` if deployed into a sub-path. When a sub-path is present the entrypoint also updates the Tomcat context path automatically. Default unset (the webapp is served at `/`).
* **DRAWIO_BASE_URL**: (Optional, backwards-compat) Same URL **without** a trailing slash, used by the viewer/lightbox/embed code paths. Only needed if `DRAWIO_SERVER_URL` is not set; the entrypoint derives whichever one is missing. If both are set, both pass through unchanged.
* **DRAWIO_VIEWER_URL**: Optional URL of a hosted viewer JS bundle, e.g. `https://drawio.example.com/js/viewer.min.js`.
* **DRAWIO_LIGHTBOX_URL**: Optional lightbox URL, e.g. `https://drawio.example.com`.

### Editor configuration

* **DRAWIO_CONFIG**: JSON configuration object for the diagram editor — written verbatim into `window.DRAWIO_CONFIG`. See <https://www.drawio.com/doc/faq/configure-diagram-editor>. Must be valid JSON, not arbitrary JavaScript.
* **DRAWIO_CSP_HEADER**: Override the default Content-Security-Policy `<meta>` injected into the page. Defaults to a hard-coded policy in [`docker-entrypoint.sh`](main/docker-entrypoint.sh) — start from that policy when customising.
* **ENABLE_DRAWIO_PROXY**: Set to `1` to enable the `/proxy` endpoint (ProxyServlet) which allows embedding images from external URLs; default disabled.

**Enabling AI diagram generation:** the AI options (`enableAi`, `gptApiKey`, `geminiApiKey`, `claudeApiKey`, `aiModels`, `aiConfigs`, ...) are editor configuration settings, not standalone environment variables — there is no `DRAWIO_ENABLE_AI`. Set them inside `DRAWIO_CONFIG`, for example:

```bash
DRAWIO_CONFIG={"enableAi":true,"claudeApiKey":"sk-ant-...","aiModels":[{"name":"Claude 4.5 Sonnet","model":"claude-sonnet-4-5","config":"claude"}]}
```

`enableAi` defaults to `true` only on app.diagrams.net, and the custom AI actions only appear once an API key and model are configured, so a self-hosted deployment needs both `enableAi: true` **and** a key. See [Customise LLM backends for diagram generation](https://www.drawio.com/doc/faq/configure-ai-options) for the full list of options.

### Export server integration

* **DRAWIO_SELF_CONTAINED**: Set to `1` to route export requests through Tomcat's `ExportProxyServlet` (`/service/0`) instead of calling the export server directly. Use this when the export server is only reachable inside the docker network.
* **EXPORT_URL**: Without `DRAWIO_SELF_CONTAINED`, set this to any value to make the webapp call `/service/0` for exports. With `DRAWIO_SELF_CONTAINED=1` the same routing is enabled automatically. The actual upstream URL is read by the proxy servlet from `web.xml`.

### Google Drive integration

See [`self-contained/README.md`](self-contained/README.md#google-drive) for how to register the OAuth app.

* **DRAWIO_GOOGLE_CLIENT_ID**: OAuth client ID. Unset = Google Drive integration disabled.
* **DRAWIO_GOOGLE_CLIENT_SECRET**: OAuth client secret.
* **DRAWIO_GOOGLE_APP_ID**: Google project number (the numeric prefix of the client ID, before the first `-`).
* **DRAWIO_GOOGLE_VIEWER_CLIENT_ID** / **DRAWIO_GOOGLE_VIEWER_CLIENT_SECRET** / **DRAWIO_GOOGLE_VIEWER_APP_ID**: Optional separate read-only credentials for a viewer deployment.

### Microsoft OneDrive integration

See [`self-contained/README.md`](self-contained/README.md#microsoft-onedrive) for redirect-URI requirements.

* **DRAWIO_MSGRAPH_CLIENT_ID**: Azure app client ID. Unset = OneDrive integration disabled.
* **DRAWIO_MSGRAPH_CLIENT_SECRET**: Azure app client secret.
* **DRAWIO_MSGRAPH_TENANT_ID**: Tenant ID for single-tenant Azure apps.

### GitLab integration

See [`self-contained/README.md`](self-contained/README.md#gitlab) for OAuth-app setup.

* **DRAWIO_GITLAB_ID**: OAuth application ID. Unset = GitLab integration disabled.
* **DRAWIO_GITLAB_SECRET**: OAuth application secret.
* **DRAWIO_GITLAB_URL**: GitLab base URL **without** any path, e.g. `https://gitlab.com` or `https://gitlab.example.com`. The entrypoint appends `/oauth/token` itself for server-side auth, and uses this value as the base of the client-side `/oauth/authorize` URL — adding a path here breaks both. When this is set to anything other than `https://gitlab.com` the entrypoint also writes `Editor.enableCustomGitLabUrl = true;` into `PostConfig.js`, which is required by the client to allow self-hosted instances.

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

All draw.io configuration is driven by the `DRAWIO_*` environment variables listed in the [Environment variables](#environment-variables) section above. For integrations that need an OAuth app (Google Drive, Microsoft OneDrive, GitLab), the step-by-step app-registration instructions live in [`self-contained/README.md`](self-contained/README.md).

## Reference

* <https://github.com/jgraph/drawio>
