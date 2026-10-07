[![Build Status](https://github.com/jgraph/docker-drawio/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/jgraph/docker-drawio/actions)


## Introduction

[draw.io](https://github.com/jgraph/drawio) is a whiteboarding / diagramming software application. This project packages draw.io for Docker:

* `jgraph/drawio`, a draw.io docker image that is always up-to-date with draw.io releases
* a [docker-compose](docker-compose.yml) to run draw.io with the Google Drive, Microsoft OneDrive and GitLab integrations
* a [docker-compose](nextcloud/) to run draw.io integrated within Nextcloud

The separate export server image (`jgraph/export-server`) has reached end of life and is no longer built or configured by this project, see [Removed variables](#removed-variables).

## Description

The Dockerfile builds from `tomcat:9.0-jdk11-temurin` (see <https://hub.docker.com/_/tomcat/>)

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

Start a web browser session to <http://localhost:8080/?offline=1> or <https://localhost:8443/?offline=1>

If you're running `Docker Toolbox` then start a web browser session to <http://192.168.99.100:8080/?offline=1> or <https://192.168.99.100:8443/?offline=1>

> `?offline=1` is a security feature that disables support of cloud storage.

## Docker Compose

[`docker-compose.yml`](docker-compose.yml) runs the same image and passes every `DRAWIO_*` variable listed under [Environment variables](#environment-variables) through from the environment, so the configuration lives in a `.env` file next to it:

```
DRAWIO_SERVER_URL=https://drawio.example.com/
DRAWIO_GITLAB_ID=...
DRAWIO_GITLAB_SECRET=...
DRAWIO_GITLAB_URL=https://gitlab.example.com
```

```bash
docker compose up -d
```

Variables you leave unset are passed through empty, which the image treats as unset.

### AWS ECS

The compose file can be deployed to AWS ECS by following this [tutorial](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-cli-tutorial-ec2.html) (we recommend EC2 deployment). Change the port mapping to 80 and 443 in `docker-compose.yml` to support the standard HTTP and HTTPS ports, allow access to these ports in the security group inbound rules, and set `DRAWIO_SERVER_URL` to your public deployment URL.

## Running as a non-root user

The image already runs as a dedicated non-root user by default — `tomcat` (UID `1001`, GID `999`) — so nothing needs to be configured just to avoid root.

[Users have reported](https://github.com/jgraph/docker-drawio/issues/210) it working with [rootless] Podman, but we haven't tested ourselves.

To run under a *different* UID (a compose `user:` override, Kubernetes `runAsUser`, or OpenShift's arbitrary UIDs), the user must carry the **root group (GID `0`)**. Configuration is applied at startup by rewriting files inside the container ([`main/docker-entrypoint.sh`](main/docker-entrypoint.sh)), and the image grants GID `0` owner-equivalent permissions on those paths, following the OpenShift image guidelines. Membership of group `0` grants no other privileges — it is not root.

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

On OpenShift, restricted SCCs already run pods with an arbitrary UID and GID `0`, so the image works there without any extra configuration.

Without GID `0` the container still starts, but the entrypoint logs a warning and skips all runtime configuration (`DRAWIO_*` variables, SSL, context path).

> `readOnlyRootFilesystem: true` is not currently supported, since configuration is written into the webapp at startup.

## Environment variables

All container behaviour is controlled by environment variables, processed by [`main/docker-entrypoint.sh`](main/docker-entrypoint.sh) at startup and written into `PreConfig.js` / `PostConfig.js` inside the deployed webapp.

### Certificate and SSL

| Variable               | Default                    | Description                                              |
| ---------------------- | -------------------------- | -------------------------------------------------------- |
| `LETS_ENCRYPT_ENABLED` | `false`                    | Enables Let's Encrypt certificate instead of self-signed |
| `PUBLIC_DNS`           | `draw.example.com`         | DNS domain to be used as certificate "CN" record         |
| `ORGANISATION_UNIT`    | `Cloud Native Application` | Organisation unit to be used as certificate "OU" record  |
| `ORGANISATION`         | `example inc`              | Organisation name to be used as certificate "O" record   |
| `CITY`                 | `Paris`                    | City name to be used as certificate "L" record           |
| `STATE`                | `Paris`                    | State name to be used as certificate "ST" record         |
| `COUNTRY_CODE`         | `FR`                       | Country code to be used as certificate "C" record        |
| `KEYSTORE_PASS`        | `V3ry1nS3cur3P4ssw0rd`     | `.keystore` / `.jks` store password                      |
| `KEY_PASS`             | same as `KEYSTORE_PASS`    | Private key password                                     |

### Deployment URL

* **DRAWIO_SERVER_URL**: Public deployment URL **with a trailing slash**, e.g. `https://drawio.example.com/`, or `https://www.example.com/drawio/` if deployed into a sub-path. When a sub-path is present the entrypoint also updates the Tomcat context path automatically. Default unset (the webapp is served at `/`).
* **DRAWIO_BASE_URL**: (Optional, backwards-compat) Same URL **without** a trailing slash, used by the viewer/lightbox/embed code paths. Only needed if `DRAWIO_SERVER_URL` is not set; the entrypoint derives whichever one is missing. If both are set, both pass through unchanged.
* **DRAWIO_VIEWER_URL**: Optional URL of a hosted viewer JS bundle, e.g. `https://drawio.example.com/js/viewer.min.js`.
* **DRAWIO_LIGHTBOX_URL**: Optional lightbox URL, e.g. `https://drawio.example.com`.
* **DRAWIO_USE_HTTP**: (Optional and INSECURE) If your setup uses http only and you understand the risks (for example, sending OAuth tokens over http), set `DRAWIO_USE_HTTP=1`. **Caution: Use at your own risk**.

**Sign-in under a sub-path:** Google Drive, OneDrive and GitLab sign-in under a sub-path needs an image newer than 31.5.2. Register the OAuth redirect URIs under `DRAWIO_SERVER_URL`, e.g. `https://www.example.com/drawio/gitlab`. The Tomcat context path is only the last segment of the sub-path (`https://www.example.com/tools/drawio/` is served at `/drawio`), and the sign-in cookies are scoped to it. If your reverse proxy maps a different public path onto it, also rewrite the cookie paths, or sign-in fails with a 401:

* nginx: `proxy_cookie_path /drawio/ /tools/drawio/;`
* Apache (mod_headers): `Header edit Set-Cookie "(?i)(;\s*path=)/drawio/" "$1/tools/drawio/"`

### Editor configuration

* **DRAWIO_CONFIG**: JSON configuration object for the diagram editor — written verbatim into `window.DRAWIO_CONFIG`. See <https://www.drawio.com/doc/faq/configure-diagram-editor>. Must be valid JSON, not arbitrary JavaScript, and must be the JSON itself, not the path of a file (see `DRAWIO_CONFIG_FILE`). The entrypoint logs a warning at startup when the value does not parse as JSON. In a compose file use the map syntax, `DRAWIO_CONFIG: '{"defaultFonts":["Helvetica"]}'` — with the list syntax (`- DRAWIO_CONFIG='{...}'`) the quotes become part of the value and the editor ignores it (the entrypoint strips a matching pair of single quotes and logs a notice).
* **DRAWIO_CONFIG_FILE**: Path inside the container of a file holding that same JSON object, for a bind mount or a Kubernetes ConfigMap. Takes precedence over `DRAWIO_CONFIG` when both are set. For example:

  ```bash
  docker run -p 8080:8080 -v ./drawio-config.json:/config/drawio-config.json:ro -e DRAWIO_CONFIG_FILE=/config/drawio-config.json jgraph/drawio
  ```

* **DRAWIO_LANG**: Default language of the editor UI as a draw.io language code, e.g. `es`, `de` or `pt-br` (the codes behind the editor's *Language* menu). Used when the URL has no `lang` parameter and the user has not picked a language in the editor; both of those still win. Unset = English. draw.io only follows the browser language on its own domains (app.diagrams.net and similar), never on a self-hosted one. There is no language key in `DRAWIO_CONFIG`.
* **DRAWIO_CSP_HEADER**: Override the default Content-Security-Policy `<meta>` injected into the page. Defaults to a hard-coded policy in [`docker-entrypoint.sh`](main/docker-entrypoint.sh) — start from that policy when customising.
* **ENABLE_DRAWIO_PROXY**: Set to `1` to enable the `/proxy` endpoint (ProxyServlet) which allows embedding images from external URLs; default disabled.

**Enabling AI diagram generation:** the AI options (`enableAi`, `gptApiKey`, `geminiApiKey`, `claudeApiKey`, `aiModels`, `aiConfigs`, ...) are editor configuration settings, not standalone environment variables — there is no `DRAWIO_ENABLE_AI`. Set them inside `DRAWIO_CONFIG`, for example:

```bash
DRAWIO_CONFIG={"enableAi":true,"claudeApiKey":"sk-ant-...","aiModels":[{"name":"Claude 4.5 Sonnet","model":"claude-sonnet-4-5","config":"claude"}]}
```

`enableAi` defaults to `true` only on app.diagrams.net, and the custom AI actions only appear once an API key and model are configured, so a self-hosted deployment needs both `enableAi: true` **and** a key. See [Customise LLM backends for diagram generation](https://www.drawio.com/doc/faq/configure-ai-options) for the full list of options.

### Custom fonts

The editor renders text in the user's browser, which can only use fonts installed on the viewer's device or loaded over HTTP(S) — mounting font files into this container does **not** make them appear in the editor. Make a web font selectable in the font picker with `defaultFonts` (or `customFonts`, which prepends to the list) inside `DRAWIO_CONFIG`:

```bash
DRAWIO_CONFIG={"defaultFonts":["Helvetica",{"fontFamily":"My Font","fontUrl":"https://drawio.example.com/fonts/MyFont.woff2"}]}
```

Plain string entries must be installed on every viewer's device; entries with `fontFamily` + `fontUrl` (a direct font file or a Google-Fonts-style CSS URL) are downloaded by the browser, and the URL is stored in the diagram so other viewers and exports can resolve it — use an absolute URL reachable from every browser that will open the diagram. To serve font files from this container, mount them into the webapp: `-v ./fonts:/usr/local/tomcat/webapps/draw/fonts` serves them at `https://your-host/fonts/…`.

`fontCss` (also inside `DRAWIO_CONFIG`) injects raw `@font-face` rules; it makes text using that family render, but does **not** add anything to the font picker — combine it with a plain font name in `defaultFonts`/`customFonts`, or just use a `fontUrl` entry instead. The default CSP allows fonts from any origin (`font-src *`); if you override **DRAWIO_CSP_HEADER**, keep your font host allowed there.

See the draw.io documentation on [external fonts](https://www.drawio.com/docs/manual/text/external-fonts/) for how fonts behave in the editor itself.

### Google Drive integration

Create a project at the [Google API Console](https://console.developers.google.com/apis) and create [Credentials](https://console.developers.google.com/apis/credentials) of type "Create OAuth client ID" -> Web Application. This option is disabled until you create the "OAuth consent screen" from the link in the warning message bar; there, enter the "Application name" and "Authorized domains". In the "Create OAuth client ID" configuration, set "Authorized redirect URIs" to `[your-draw.io-hostname]/google` and "Authorized JavaScript origins" to your hostname. For example, if you host draw.io at `https://drawio.example.com`, the redirect URI is `https://drawio.example.com/google` and the JavaScript origin is `https://drawio.example.com`.

* **DRAWIO_GOOGLE_CLIENT_ID**: OAuth client ID. Unset = Google Drive integration disabled.
* **DRAWIO_GOOGLE_CLIENT_SECRET**: OAuth client secret.
* **DRAWIO_GOOGLE_APP_ID**: Google project number (the numeric prefix of the client ID, before the first `-`). For example, if the client ID is `123456789-abc...`, the app ID is `123456789`.
* **DRAWIO_GOOGLE_VIEWER_CLIENT_ID** / **DRAWIO_GOOGLE_VIEWER_CLIENT_SECRET** / **DRAWIO_GOOGLE_VIEWER_APP_ID**: Optional separate read-only credentials for a viewer deployment. If you also host a draw.io viewer, create another client ID for it; the viewer has read-only access to Drive files.

### Microsoft OneDrive integration

Register an application to use the MS Graph APIs, see [how to register your app](https://docs.microsoft.com/en-us/graph/auth-register-app-v2) and [how to use the APIs](https://docs.microsoft.com/en-us/graph/use-the-api). In the Azure portal select the new app, then "Authentication", and add the redirect URI `[your-draw.io-hostname]/microsoft` under the "Web" platform. For example, if you host draw.io at `https://drawio.example.com`, the redirect URI is `https://drawio.example.com/microsoft`. Sign-in uses the authorization code flow, with the token exchange done by the server using the client secret, so the implicit grant ("Access tokens" and "ID tokens" under "Advanced settings") can stay off. Create the client secret under "Certificates & secrets" ("+ New client secret"); the "Application (client) ID" is on the "Overview" page.

* **DRAWIO_MSGRAPH_CLIENT_ID**: Azure app client ID. Unset = OneDrive integration disabled.
* **DRAWIO_MSGRAPH_CLIENT_SECRET**: Azure app client secret.
* **DRAWIO_MSGRAPH_TENANT_ID**: Tenant ID for single-tenant Azure apps, used for both the sign-in page and the server's token requests. Unset = `common` (multi-tenant).

Older setups also registered `[your-draw.io-hostname]/onedrive3.html` as a redirect URI and enabled the implicit grant. Only the legacy OneDrive file picker uses those, and only when it is switched on with the `inlinePicker=0` URL parameter or `"oneDriveInlinePicker": false` in `DRAWIO_CONFIG`. The default picker does not need them.

### GitLab integration

Create a new OAuth app in GitLab (Settings -> Applications). Set the "Redirect URI" to `[your-draw.io-hostname]/gitlab`, e.g. `https://drawio.example.com/gitlab`, and the "Scopes" to `api`, `read_repository` and `write_repository`.

* **DRAWIO_GITLAB_ID**: OAuth application ID. Unset = GitLab integration disabled.
* **DRAWIO_GITLAB_SECRET**: OAuth application secret.
* **DRAWIO_GITLAB_URL**: GitLab base URL **without** any path, e.g. `https://gitlab.com` or `https://gitlab.example.com`. The entrypoint appends `/oauth/token` itself for server-side auth, and uses this value as the base of the client-side `/oauth/authorize` URL — adding a path here breaks both. When this is set to anything other than `https://gitlab.com` the entrypoint also writes `Editor.enableCustomGitLabUrl = true;` into `PostConfig.js`, which is required by the client to allow self-hosted instances; without it the OAuth flow fails with an "access denied" dialog before any request is made.

### Removed variables

* **EXPORT_URL** and **DRAWIO_SELF_CONTAINED** no longer have any effect. They pointed the editor at the separate `jgraph/export-server` image, which has reached end of life and is no longer built from this repository. The entrypoint writes `window.EXPORT_URL = null` into `PreConfig.js` instead, which tells the editor that no export service exists: *Export as > PDF* uses the browser's print dialog (so the *Include a copy of my diagram* option is not offered for PDF) and the server-rendered PNG/JPEG export is hidden. PNG, JPEG and SVG export rendered in the browser are unaffected.

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

## License

This project — the Docker packaging for draw.io in this repository — is licensed under the
GNU General Public License v3. See [LICENSE](LICENSE).

Software included in the built image is covered by its own licence terms, not by this one.

## Reference

* <https://github.com/jgraph/drawio>
