#!/usr/bin/env bash

webapp_install_cmd() { /usr/local/bin/webapp-install "$@"; }

install_webapps() {
    local manifest="$ROOT_DIR/assets/webapps.json"
    local id name url domain
    jq_cmd -e 'type == "array" and all(.[]; (.id | type == "string") and (.name | type == "string") and (.url | type == "string") and (.domain | type == "string"))' \
        "$manifest" &>/dev/null || { err "Invalid web-app manifest: ${manifest}"; return 1; }
    while IFS=$'\t' read -r id name url domain; do
        webapp_install_cmd "$id" "$name" "$url" "$domain"
    done < <(jq_cmd -r '.[] | [.id, .name, .url, .domain] | @tsv' "$manifest")
    log "Web apps installed"
}
