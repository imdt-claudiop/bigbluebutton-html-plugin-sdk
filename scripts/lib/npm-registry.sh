#!/bin/bash

# The npm side of a release: the read-only checks that a release has to pass before anything is
# published, and the wait that follows the publish. Sourced by publish-version.sh; the blocking
# checks report through its record_or_stop, so a dry run collects them like any other finding.

# Seconds. Overridable from the environment, for the same reason the stage toggles are: a release
# waiting on a slow registry must not need an edit, which would dirty the tree.
NPM_PUBLISH_WAIT_TIMEOUT="${NPM_PUBLISH_WAIT_TIMEOUT:-600}"
NPM_PUBLISH_SETTLE_SECONDS="${NPM_PUBLISH_SETTLE_SECONDS:-120}"
NPM_PUBLISH_POLL_SECONDS=10

# The version the registry serves, empty when it has none. --prefer-online, because a cached
# answer from before the publish is exactly the one this must not give.
published_version() {
    npm view --prefer-online "$1@$2" version 2> /dev/null || true
}

# Checked before the release writes anything, because npm refusing the publish afterwards leaves
# the tree bumped, half the release done and the rest to undo by hand.
check_npm_preconditions() {
    local package="$1" version="$2" npm_user

    if ! npm_user=$(npm whoami 2> /dev/null); then
        record_or_stop "npm is not logged in, so this release cannot publish $package" \
            "Log in as a user with publish rights on the package:" \
            "    npm login"
    elif ! npm access list collaborators "$package" 2> /dev/null | grep -qxF "$npm_user: read-write"; then
        # A warning, not a refusal: the list holds individual grants only, so publish rights held
        # through an organization team are real and still absent from it.
        echo "Warning: npm user $npm_user is not listed as a collaborator with write access on $package."
        echo "The check is best-effort; rights granted through an organization team do not show up in that list."
    fi

    if [ -n "$(published_version "$package" "$version")" ]; then
        record_or_stop "$package@$version is already published on npm" \
            "Release a version the registry does not have, or, if this version's publish already succeeded," \
            "finish that release with PUBLISH_TO_NPMJS=false (see the header of publish-version.sh)."
    fi
}

# The samples install the version right after this returns, so the run waits for the registry to
# serve it, then gives it the settle time on top: being served once is not being served everywhere.
wait_for_published_version() {
    local package="$1" version="$2" waited=0

    echo "Waiting up to ${NPM_PUBLISH_WAIT_TIMEOUT}s for npm to serve $package@$version"

    while [ -z "$(published_version "$package" "$version")" ]; do
        if [ "$waited" -ge "$NPM_PUBLISH_WAIT_TIMEOUT" ]; then
            echo "Error: npm did not serve $package@$version within ${NPM_PUBLISH_WAIT_TIMEOUT}s."
            echo "The publish itself succeeded, so do not publish again; finish this release with:"
            echo "    PUBLISH_TO_NPMJS=false ./scripts/publish-version.sh"
            exit 1
        fi

        sleep "$NPM_PUBLISH_POLL_SECONDS"
        waited=$((waited + NPM_PUBLISH_POLL_SECONDS))
    done

    echo "npm is serving $package@$version; giving it ${NPM_PUBLISH_SETTLE_SECONDS}s to replicate internally"
    sleep "$NPM_PUBLISH_SETTLE_SECONDS"
}
