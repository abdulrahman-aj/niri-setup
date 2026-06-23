#!/usr/bin/env bash
# Pure, dependency-free git checkout validation. Safe to source from the
# installer, install.sh, or any bin/ command (no installer state, no sudo).

# Return 0 if <dir> is a Git checkout whose origin matches any expected URL.
git_remote_matches() {
    local dir=$1 remote expected
    shift
    [[ -d "$dir/.git" ]] || return 1
    remote="$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)"
    for expected in "$@"; do
        [[ "$remote" == "$expected" ]] && return 0
    done
    return 1
}
