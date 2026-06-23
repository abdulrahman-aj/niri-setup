#!/usr/bin/env bash

readonly DEBLOAT_EXACT=(
    gnome-tour gnome-maps gnome-weather gnome-calendar gnome-contacts
    gnome-clocks gnome-connections gnome-boxes simple-scan mediawriter
    gnome-software gnome-software-fedora-langpacks gnome-text-editor
    gnome-logs gnome-characters gnome-system-monitor yelp yelp-libs yelp-xsl
)
readonly BOOTSTRAP_PACKAGES=(git pciutils)

install_bootstrap_packages() {
    install_required_group "bootstrap prerequisites" "${BOOTSTRAP_PACKAGES[@]}"
}

optimize_dnf() {
    local conf="${DNF_CONF:-/etc/dnf/dnf.conf}" generated
    generated="$(mktemp)"
    trap 'rm -f "${generated:-}"; trap - RETURN' RETURN
    awk '
        BEGIN { parallel = 0; default_yes = 0 }
        /^[[:space:]]*max_parallel_downloads[[:space:]]*=/ { if (!parallel++) print "max_parallel_downloads=10"; next }
        /^[[:space:]]*defaultyes[[:space:]]*=/ { if (!default_yes++) print "defaultyes=True"; next }
        { print }
        END { if (!parallel) print "max_parallel_downloads=10"; if (!default_yes) print "defaultyes=True" }
    ' "$conf" >"$generated"
    cmp -s "$generated" "$conf" || s install -m 0644 "$generated" "$conf"
    log "DNF settings configured"
}

configure_timezone() {
    if [[ "$(timedatectl show --property=Timezone --value)" != Asia/Amman ]]; then
        s timedatectl set-timezone Asia/Amman
    fi
    [[ "$(timedatectl show --property=Timezone --value)" == Asia/Amman ]] || { err "Failed to set timezone to Asia/Amman."; return 1; }
    log "Timezone set to Asia/Amman"
}

locale_uses_12_hour_format() {
    local locale_conf="$1"
    if grep -Eq '^LC_TIME="?en_US\.UTF-8"?$' "$locale_conf" 2>/dev/null; then
        return 0
    fi
    grep -Eq '^LC_TIME=' "$locale_conf" 2>/dev/null && return 1
    grep -Eq '^LANG="?en_US\.UTF-8"?$' "$locale_conf" 2>/dev/null
}

configure_time_format() {
    local locale_conf="${LOCALE_CONF:-/etc/locale.conf}"
    if ! locale_uses_12_hour_format "$locale_conf"; then
        s localectl set-locale LC_TIME=en_US.UTF-8
    fi
    locale_uses_12_hour_format "$locale_conf" || {
        err "Failed to set LC_TIME to en_US.UTF-8."
        return 1
    }
    log "Time format set to 12-hour AM/PM"
}

install_chrome() {
    if ! rpm -q fedora-workstation-repositories &>/dev/null; then
        s dnf install -y fedora-workstation-repositories
    fi
    s dnf config-manager enable google-chrome
    if ! rpm -q google-chrome-stable &>/dev/null; then
        s dnf install -y google-chrome-stable
    fi
    have_command xdg-settings || { err "xdg-settings is required to select Chrome."; return 1; }
    xdg-settings set default-web-browser google-chrome.desktop
    [[ "$(xdg-settings get default-web-browser)" == google-chrome.desktop ]] || { err "Chrome was not selected as the default browser."; return 1; }
    log "Google Chrome installed and selected"
}

installed_debloat_packages() {
    local package
    while IFS= read -r package; do
        if [[ "$package" == libreoffice* || "$package" == firefox* ]]; then
            printf '%s\n' "$package"
            continue
        fi
        local candidate
        for candidate in "${DEBLOAT_EXACT[@]}"; do
            [[ "$package" == "$candidate" ]] && { printf '%s\n' "$package"; break; }
        done
    done < <(rpm -qa --qf '%{NAME}\n')
}

debloat_system() {
    local packages=()
    mapfile -t packages < <(installed_debloat_packages | sort -u)
    if ((${#packages[@]})); then
        s dnf remove -y --setopt=clean_requirements_on_remove=False "${packages[@]}"
        log "Removed selected Fedora/GNOME applications"
    else
        log "No selected debloat packages are installed"
    fi
}

system_update() { s dnf upgrade --refresh -y; log "System updated"; }

enable_danklinux_copr() {
    dnf repolist 2>/dev/null | grep -q 'avengemedia:dms' || s dnf copr enable -y avengemedia/dms
    dnf repolist 2>/dev/null | grep -q 'avengemedia:danklinux' || s dnf copr enable -y avengemedia/danklinux
    s dnf makecache -y
}

run_system_phase() {
    step "System preparation"
    optimize_dnf
    configure_timezone
    configure_time_format
    install_chrome
    debloat_system
    system_update
    enable_danklinux_copr
}
