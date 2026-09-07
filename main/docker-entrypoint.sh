#!/bin/bash
#set -e

LETS_ENCRYPT_ENABLED=${LETS_ENCRYPT_ENABLED:-false}
PUBLIC_DNS=${PUBLIC_DNS:-'draw.example.com'}
ORGANISATION_UNIT=${ORGANISATION_UNIT:-'Cloud Native Application'}
ORGANISATION=${ORGANISATION:-'example inc'}
CITY=${CITY:-'Paris'}
STATE=${STATE:-'Paris'}
COUNTRY_CODE=${COUNTRY_CODE:-'FR'}
KEYSTORE_PASS=${KEYSTORE_PASS:-'V3ry1nS3cur3P4ssw0rd'}
KEY_PASS=${KEY_PASS:-$KEYSTORE_PASS}

#Every step below writes into CATALINA_HOME. When the container runs as a
#UID without write access (a user:/runAsUser override lacking GID 0), each
#write would fail with its own cryptic error, so give one clear warning and
#start Tomcat with the configuration baked in at build time instead.
#[jgraph/docker-drawio#186]
if ! touch $CATALINA_HOME/webapps/draw/js/PreConfig.js 2>/dev/null; then
    echo "WARNING: No write access to $CATALINA_HOME (running as UID $(id -u), GID $(id -g))."
    echo "         Skipping runtime configuration: DRAWIO_* environment variables, SSL and the"
    echo "         context path will NOT be applied. To run as an arbitrary user, give it GID 0,"
    echo "         e.g. 'docker run --user 1234:0', compose 'group_add: [\"0\"]' or kubernetes"
    echo "         'runAsGroup: 0' / 'supplementalGroups: [0]'. See README: Running as non-root."
    exec "$@"
fi

echo "Init PreConfig.js"
#Add CSP to prevent calls to draw.io
echo "(function() {" > $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "  try {" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "	    var s = document.createElement('meta');" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
if [[ -z "${DRAWIO_GITLAB_ID}" ]]; then
    echo "	    s.setAttribute('content', '${DRAWIO_CSP_HEADER:-default-src \'self\'; script-src \'self\' https://storage.googleapis.com https://apis.google.com https://docs.google.com https://code.jquery.com \'unsafe-inline\'; connect-src \'self\' https://*.dropboxapi.com https://api.trello.com https://api.github.com https://raw.githubusercontent.com https://*.googleapis.com https://*.googleusercontent.com https://graph.microsoft.com https://*.1drv.com https://*.sharepoint.com https://gitlab.com https://*.google.com https://fonts.gstatic.com https://fonts.googleapis.com; img-src * data:; media-src * data:; font-src * about:; style-src \'self\' \'unsafe-inline\' https://fonts.googleapis.com; frame-src \'self\' https://*.google.com;}');" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
else
    echo "	    s.setAttribute('content', '${DRAWIO_CSP_HEADER:-default-src \'self\'; script-src \'self\' https://storage.googleapis.com https://apis.google.com https://docs.google.com https://code.jquery.com \'unsafe-inline\'; connect-src \'self\' $DRAWIO_GITLAB_URL https://*.dropboxapi.com https://api.trello.com https://api.github.com https://raw.githubusercontent.com https://*.googleapis.com https://*.googleusercontent.com https://graph.microsoft.com https://*.1drv.com https://*.sharepoint.com https://gitlab.com https://*.google.com https://fonts.gstatic.com https://fonts.googleapis.com; img-src * data:; media-src * data:; font-src * about:; style-src \'self\' \'unsafe-inline\' https://fonts.googleapis.com; frame-src \'self\' https://*.google.com;}');" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
fi
echo "	    s.setAttribute('http-equiv', 'Content-Security-Policy');" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo " 	    var t = document.getElementsByTagName('meta')[0];" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "      t.parentNode.insertBefore(s, t);" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "  } catch (e) {} // ignore" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "})();" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
#DRAWIO_SERVER_URL is the deployment URL with a trailing slash, e.g. https://www.example.com/drawio/
#DRAWIO_BASE_URL is the same URL without the trailing slash, used by the viewer/lightbox/embed code paths.
#Either may be set on its own; the other is derived from it. If both are set, both are used as given.
if [[ -n "$DRAWIO_SERVER_URL" ]]; then
  DRAWIO_SERVER_URL_VALUE="${DRAWIO_SERVER_URL}"
  DRAWIO_BASE_URL_VALUE="${DRAWIO_BASE_URL:-${DRAWIO_SERVER_URL%/}}"
elif [[ -n "$DRAWIO_BASE_URL" ]]; then
  DRAWIO_SERVER_URL_VALUE="${DRAWIO_BASE_URL%/}/"
  DRAWIO_BASE_URL_VALUE="${DRAWIO_BASE_URL}"
else
  DRAWIO_SERVER_URL_VALUE=""
  DRAWIO_BASE_URL_VALUE="http://localhost:8080"
fi

# Write it to PreConfig.js
echo "window.DRAWIO_SERVER_URL = '${DRAWIO_SERVER_URL_VALUE}';" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "window.DRAWIO_BASE_URL = '${DRAWIO_BASE_URL_VALUE}';" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js

# Dynamically update Tomcat context path if the deployment URL ends in a subpath
URL_PATH=$(echo "${DRAWIO_SERVER_URL_VALUE}" | sed -E 's|^https?://[^/]+||; s|[?#].*$||; s|/$||')
if [ -z "$URL_PATH" ]; then
  CONTEXT_PATH=""
else
  CONTEXT_PATH="/$(basename "$URL_PATH")"
fi

if [ -n "$DRAWIO_SERVER_URL_VALUE" ] && [ -n "$CONTEXT_PATH" ]; then
  echo "Updating Tomcat context path to '${CONTEXT_PATH}'"
  xmlstarlet ed -P -S -L \
    -u '/Server/Service/Engine/Host/Context/@path' -v "${CONTEXT_PATH}" \
    -u '/Server/Service/Engine/Host/Context/@docBase' -v 'draw' \
    conf/server.xml
else
  echo "Tomcat context remains at root '/'"
fi
#DRAWIO_VIEWER_URL is path to the viewer js, e.g. https://www.example.com/js/viewer.min.js
echo "window.DRAWIO_VIEWER_URL = '${DRAWIO_VIEWER_URL}';" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
#DRAWIO_LIGHTBOX_URL Replace with your lightbox URL, eg. https://www.example.com
echo "window.DRAWIO_LIGHTBOX_URL = '${DRAWIO_LIGHTBOX_URL}';" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "window.DRAW_MATH_URL = 'math4/es5';" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
#No export server ships with this image. null tells the editor that no export service exists,
#so Export as > PDF uses the browser's print dialog and the server-rendered PNG/JPEG export is
#hidden. Leaving it unset would fall back to convert.diagrams.net, which rejects requests from
#other hosts, and the editor would post every export to a dead URL in a new tab.
echo "window.EXPORT_URL = null;" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
#Custom draw.io configurations. For more details, https://www.drawio.com/doc/faq/configure-diagram-editor
#DRAWIO_CONFIG_FILE names a JSON file inside the container (bind mount, ConfigMap) and takes
#precedence over the inline DRAWIO_CONFIG value. The value is written verbatim into PreConfig.js,
#so anything that is not a JavaScript object literal (a file path, a quoted string) breaks the
#whole script, and with it every DRAWIO_* setting, without any error at startup. The checks
#below catch the common mistakes and log them. [jgraph/docker-drawio#155]
DRAWIO_CONFIG_VALUE="${DRAWIO_CONFIG}"
if [[ -n "${DRAWIO_CONFIG_FILE}" ]]; then
    if [[ -r "${DRAWIO_CONFIG_FILE}" ]]; then
        if [[ -n "${DRAWIO_CONFIG_VALUE}" ]]; then
            echo "NOTICE: Both DRAWIO_CONFIG_FILE and DRAWIO_CONFIG are set, using DRAWIO_CONFIG_FILE."
        fi
        DRAWIO_CONFIG_VALUE="$(cat "${DRAWIO_CONFIG_FILE}")"
    else
        echo "WARNING: DRAWIO_CONFIG_FILE '${DRAWIO_CONFIG_FILE}' does not exist or is not readable, ignoring it."
    fi
fi
#Trim surrounding whitespace so the checks see the first real character
DRAWIO_CONFIG_VALUE="${DRAWIO_CONFIG_VALUE#"${DRAWIO_CONFIG_VALUE%%[![:space:]]*}"}"
DRAWIO_CONFIG_VALUE="${DRAWIO_CONFIG_VALUE%"${DRAWIO_CONFIG_VALUE##*[![:space:]]}"}"
case "${DRAWIO_CONFIG_VALUE}" in
    ''|null)
        DRAWIO_CONFIG_VALUE="null"
        ;;
    \{*)
        ;;
    \'*\')
        #docker compose keeps the quotes in the list syntax (- DRAWIO_CONFIG='{...}'), which turns
        #the value into a JavaScript string that the editor silently ignores. A JSON object never
        #starts with a quote, so stripping a matching pair cannot break a valid value.
        echo "NOTICE: Stripping the single quotes around DRAWIO_CONFIG. In docker compose use the map syntax (DRAWIO_CONFIG: '{...}') so the quotes do not end up in the value."
        DRAWIO_CONFIG_VALUE="${DRAWIO_CONFIG_VALUE:1:-1}"
        ;;
    *)
        echo "WARNING: DRAWIO_CONFIG must be an inline JSON object such as {\"defaultFonts\":[\"Helvetica\"]}. To load it from a file, set DRAWIO_CONFIG_FILE to the file's path inside the container."
        ;;
esac
#Only values that at least look like an object get the JSON check (the other cases warned above).
#python3 is present as a certbot dependency; without it the check is skipped, not failed.
if [[ "${DRAWIO_CONFIG_VALUE}" == \{* ]] && command -v python3 >/dev/null 2>&1; then
    JSON_ERROR=$(printf '%s' "${DRAWIO_CONFIG_VALUE}" | python3 -c '
import json, sys
try:
    json.load(sys.stdin)
except ValueError as e:
    print(e)
    sys.exit(1)
')
    if [[ $? -ne 0 ]]; then
        echo "WARNING: DRAWIO_CONFIG is not valid JSON (${JSON_ERROR}). If the browser cannot parse it, PreConfig.js fails to load and ALL DRAWIO_* settings are ignored."
    fi
fi
printf 'window.DRAWIO_CONFIG = %s;\n' "${DRAWIO_CONFIG_VALUE}" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
#Default UI language. Init.js resolves the language as the lang URL parameter, then the choice the
#user saved in the editor (.drawio-config in localStorage), then the browser language. Presetting
#window.mxLanguage unconditionally would override the first two, so the default only applies when
#neither is present. There is no language key in DRAWIO_CONFIG. [jgraph/docker-drawio#155]
if [[ -n "${DRAWIO_LANG}" ]]; then
    if [[ "${DRAWIO_LANG}" =~ ^[A-Za-z]{2,3}(-[A-Za-z]{2})?$ ]]; then
        cat >> $CATALINA_HOME/webapps/draw/js/PreConfig.js <<EOF
(function() {
  try {
    if (urlParams['lang'] == null) {
      var saved = (window.isLocalStorage) ? localStorage.getItem('.drawio-config') : null;
      if (saved == null || !JSON.parse(saved).language) {
        window.mxLanguage = '${DRAWIO_LANG,,}'; //DRAWIO_LANG default
      }
    }
  } catch (e) {} // ignore
})();
EOF
    else
        echo "WARNING: DRAWIO_LANG '${DRAWIO_LANG}' is not a language code such as 'es' or 'pt-br', ignoring it."
    fi
fi
#Real-time configuration
echo "urlParams['sync'] = 'manual'; //Disable Real-Time" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js

#Disable unsupported services
echo "urlParams['db'] = '0'; //dropbox" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "urlParams['gh'] = '0'; //github" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
echo "urlParams['tr'] = '0'; //trello" >> $CATALINA_HOME/webapps/draw/js/PreConfig.js

#Google Drive 
if [[ -z "${DRAWIO_GOOGLE_CLIENT_ID}" ]]; then
    echo "urlParams['gapi'] = '0'; //Google Drive"  >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
else
    #Google drive application id and client id for the editor
    echo "window.DRAWIO_GOOGLE_APP_ID = '${DRAWIO_GOOGLE_APP_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
    echo "window.DRAWIO_GOOGLE_CLIENT_ID = '${DRAWIO_GOOGLE_CLIENT_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
    echo -n "${DRAWIO_GOOGLE_CLIENT_ID}" > $CATALINA_HOME/webapps/draw/WEB-INF/google_client_id
    echo -n "${DRAWIO_GOOGLE_CLIENT_SECRET}" > $CATALINA_HOME/webapps/draw/WEB-INF/google_client_secret
    #If you want to use the editor as a viewer also, you can create another app with read-only access. You can use the same info as above if write-access is not an issue. 
    if [[ "${DRAWIO_GOOGLE_VIEWER_CLIENT_ID}" ]]; then
        echo "window.DRAWIO_GOOGLE_VIEWER_APP_ID = '${DRAWIO_GOOGLE_VIEWER_APP_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
        echo "window.DRAWIO_GOOGLE_VIEWER_CLIENT_ID = '${DRAWIO_GOOGLE_VIEWER_CLIENT_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
        echo -n "/:::/${DRAWIO_GOOGLE_VIEWER_CLIENT_ID}" >> $CATALINA_HOME/webapps/draw/WEB-INF/google_client_id
        echo -n "/:::/${DRAWIO_GOOGLE_VIEWER_CLIENT_SECRET}" >> $CATALINA_HOME/webapps/draw/WEB-INF/google_client_secret
    fi
fi

#Microsoft OneDrive
if [[ -z "${DRAWIO_MSGRAPH_CLIENT_ID}" ]]; then
    echo "urlParams['od'] = '0'; //OneDrive"  >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
else
    #Google drive application id and client id for the editor
    echo "window.DRAWIO_MSGRAPH_CLIENT_ID = '${DRAWIO_MSGRAPH_CLIENT_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
    echo -n "${DRAWIO_MSGRAPH_CLIENT_ID}" > $CATALINA_HOME/webapps/draw/WEB-INF/msgraph_client_id
    echo -n "${DRAWIO_MSGRAPH_CLIENT_SECRET}" > $CATALINA_HOME/webapps/draw/WEB-INF/msgraph_client_secret

    if [[ "${DRAWIO_MSGRAPH_TENANT_ID}" ]]; then
        echo "window.DRAWIO_MSGRAPH_TENANT_ID = '${DRAWIO_MSGRAPH_TENANT_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
        echo -n "${DRAWIO_MSGRAPH_TENANT_ID}" > $CATALINA_HOME/webapps/draw/WEB-INF/msgraph_tenant_id
    fi
fi

#Gitlab
if [[ -z "${DRAWIO_GITLAB_ID}" ]]; then
    echo "urlParams['gl'] = '0'; //Gitlab"  >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
else
    #Gitlab url and id for the editor
    echo "window.DRAWIO_GITLAB_URL = '${DRAWIO_GITLAB_URL}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js
    echo "window.DRAWIO_GITLAB_ID = '${DRAWIO_GITLAB_ID}'; " >> $CATALINA_HOME/webapps/draw/js/PreConfig.js

    #Gitlab server flow auth (since 14.6.7)
    echo -n "${DRAWIO_GITLAB_URL}/oauth/token" > $CATALINA_HOME/webapps/draw/WEB-INF/gitlab_auth_url
    echo -n "${DRAWIO_GITLAB_ID}" > $CATALINA_HOME/webapps/draw/WEB-INF/gitlab_client_id
    echo -n "${DRAWIO_GITLAB_SECRET}" > $CATALINA_HOME/webapps/draw/WEB-INF/gitlab_client_secret
fi

cat $CATALINA_HOME/webapps/draw/js/PreConfig.js

echo "Init PostConfig.js"

#null'ing of global vars need to be after init.js
echo "window.ICONSEARCH_PATH = null;" >> $CATALINA_HOME/webapps/draw/js/PostConfig.js
echo "EditorUi.enableLogging = false; //Disable logging" >> $CATALINA_HOME/webapps/draw/js/PostConfig.js

#Allow self-hosted GitLab URLs. GitLabClient.authenticate() refuses any non-default
#DRAWIO_GITLAB_URL unless Editor.enableCustomGitLabUrl is true, failing silently with
#an access-denied error. The check uses exact string equality against https://gitlab.com,
#so strip a trailing slash before comparing.
if [[ -n "${DRAWIO_GITLAB_URL}" && "${DRAWIO_GITLAB_URL%/}" != "https://gitlab.com" ]]; then
    echo "Editor.enableCustomGitLabUrl = true; //Allow self-hosted GitLab" >> $CATALINA_HOME/webapps/draw/js/PostConfig.js
fi

#Treat this domain as a draw.io domain
echo "App.prototype.isDriveDomain = function() { return true; }" >> $CATALINA_HOME/webapps/draw/js/PostConfig.js

cat $CATALINA_HOME/webapps/draw/js/PostConfig.js

if ! [ -f $CATALINA_HOME/.keystore ] && [ "$LETS_ENCRYPT_ENABLED" == "true" ]; then
    echo "Generating Let's Encrypt certificate"
    
    keytool -genkey -noprompt -alias tomcat -dname "CN=${PUBLIC_DNS}, OU=${ORGANISATION_UNIT}, O=${ORGANISATION}, L=${CITY}, S=${STATE}, C=${COUNTRY_CODE}" -keystore $CATALINA_HOME/.keystore -storepass "${KEYSTORE_PASS}" -KeySize 2048 -keypass "${KEY_PASS}" -keyalg RSA -storetype pkcs12

    keytool -list -keystore $CATALINA_HOME/.keystore -v -storepass "${KEYSTORE_PASS}"

    keytool -certreq -alias tomcat -file request.csr -keystore $CATALINA_HOME/.keystore -storepass "${KEYSTORE_PASS}"

    certbot certonly --csr $CATALINA_HOME/request.csr --standalone --register-unsafely-without-email --agree-tos

    keytool -import -trustcacerts -alias tomcat -file 0001_chain.pem -keystore $CATALINA_HOME/.keystore -storepass "${KEYSTORE_PASS}"
fi

if ! [ -f $CATALINA_HOME/.keystore ] && [ "$LETS_ENCRYPT_ENABLED" == "false" ]; then
    echo "Generating Self-Signed certificate"

    keytool -genkey -noprompt -alias selfsigned -dname "CN=${PUBLIC_DNS}, OU=${ORGANISATION_UNIT}, O=${ORGANISATION}, L=${CITY}, S=${STATE}, C=${COUNTRY_CODE}" -keystore $CATALINA_HOME/.keystore -storepass "${KEYSTORE_PASS}" -KeySize 2048 -keypass "${KEY_PASS}" -keyalg RSA -validity 3600 -storetype pkcs12
    
    keytool -list -keystore $CATALINA_HOME/.keystore -v -storepass "${KEYSTORE_PASS}"
fi

# Update SSL port configuration if it does'nt exists
#
UUID="$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 1 | head -n 1)$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 7 | head -n 1)"
VAR=$(cat conf/server.xml | grep "$CATALINA_HOME/.keystore")

if [ -f $CATALINA_HOME/.keystore ] && [ -z $VAR ]; then
     echo "Append https connector to server.xml"

    xmlstarlet ed \
        -P -S -L \
        -s '/Server/Service' -t 'elem' -n "${UUID}" \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'port' -v '8443' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'protocol' -v 'org.apache.coyote.http11.Http11NioProtocol' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'SSLEnabled' -v 'true' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'maxThreads' -v '150' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'scheme' -v 'https' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'secure' -v 'true' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'clientAuth' -v 'false' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'sslProtocol' -v 'TLS' \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'KeystoreFile' -v "$CATALINA_HOME/.keystore" \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'KeystorePass' -v "${KEY_PASS}" \
        -i "/Server/Service/${UUID}" -t 'attr' -n 'defaultSSLHostConfigName' -v "${PUBLIC_DNS:-'draw.example.com'}" \
        -s "/Server/Service/${UUID}" -t 'elem' -n 'SSLHostConfig' \
        -i "/Server/Service/${UUID}/SSLHostConfig" -t 'attr' -n 'hostName' -v "${PUBLIC_DNS:-'draw.example.com'}" \
        -i "/Server/Service/${UUID}/SSLHostConfig" -t 'attr' -n 'protocols' -v 'TLSv1.2' \
        -s "/Server/Service/${UUID}/SSLHostConfig" -t 'elem' -n 'Certificate' \
        -i "/Server/Service/${UUID}/SSLHostConfig/Certificate" -t 'attr' -n 'certificateKeystoreFile' -v "$CATALINA_HOME/.keystore" \
        -i "/Server/Service/${UUID}/SSLHostConfig/Certificate" -t 'attr' -n 'certificateKeystorePassword' -v "${KEY_PASS}" \
        -r "/Server/Service/${UUID}" -v 'Connector' \
    conf/server.xml
fi


exec "$@"
