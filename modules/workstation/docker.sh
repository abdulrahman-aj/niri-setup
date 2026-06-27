#!/usr/bin/env bash

enable_docker_repository() {
    if ! dnf repolist 2>/dev/null | grep -Eq '^docker-ce-stable([[:space:]]|$)'; then
        s dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
    fi
}

install_docker_packages() {
    s dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_toggle() {
    local sudoers=/etc/sudoers.d/toggle-docker
    local plugin_dir="$REAL_HOME/.config/DankMaterialShell/plugins/dockerToggle"
    local temp
    temp="$(mktemp)"
    trap 'rm -f "${temp:-}"; trap - RETURN' RETURN
    printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start docker.service docker.socket, /usr/bin/systemctl stop docker.service docker.socket\n' "$REAL_USER" >"$temp"
    visudo -cf "$temp" &>/dev/null || { err "Generated Docker sudoers rule is invalid."; return 1; }
    install_root_file_with_backup "$temp" "$sudoers" 0440
    install_symlink_with_backup "$ROOT_DIR/assets/dms-plugins/toggle-docker" "$plugin_dir"
}

configure_docker_access() {
    s systemctl disable --now docker.service docker.socket
    if ! id -nG "$REAL_USER" | tr ' ' '\n' | grep -Fxq docker; then
        s usermod -aG docker "$REAL_USER"
    fi
}

verify_docker_disabled() {
    [[ "$(systemctl is-enabled docker.service 2>/dev/null || true)" == disabled ]]
    [[ "$(systemctl is-enabled docker.socket 2>/dev/null || true)" == disabled ]]
    ! systemctl is-active --quiet docker.service
    ! systemctl is-active --quiet docker.socket
}

install_docker() {
    enable_docker_repository
    install_docker_packages
    install_docker_toggle
    configure_docker_access
    verify_docker_disabled
}
