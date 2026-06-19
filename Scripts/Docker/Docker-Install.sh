#!/usr/bin/env bash

# recommended to see the source before running the script https://get.docker.com/

set -euo pipefail

echo "Installing Docker from Docker site"

# Make sure the installer script is removed when this script exits (success or failure)
cleanup() {
    rm -f get-docker.sh
}
trap cleanup EXIT

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh



echo "Adding docker group if not made"
if ! getent group docker > /dev/null 2>&1; then
    sudo groupadd docker
else
    echo "docker group already exists"
fi

echo "Adding current user to the docker group"
sudo usermod -aG docker "$USER"

echo ""
echo "Activating the docker group for the current session..."

# usermod only updates the group database; the current shell still uses the old
# group set until you re-login. Instead of forcing a logout, we drop the user
# into a new shell that already has the docker group active (same idea as newgrp).
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    echo "docker group is already active in this session."
else
    echo "Starting a new shell with the docker group enabled."
    echo "Run 'docker run hello-world' to verify, and type 'exit' to return."
    echo ""
    # exec replaces the current process so the new group set takes effect cleanly.
    exec sg docker "$SHELL"
fi
