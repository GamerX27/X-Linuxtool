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

echo "Making sure the docker service is started and enabled on boot"
sudo systemctl enable --now docker

echo "Adding docker group if not made"
if ! getent group docker > /dev/null 2>&1; then
    sudo groupadd docker
else
    echo "docker group already exists"
fi

echo "Adding current user to the docker group"
sudo usermod -aG docker "$USER"

echo ""
echo "Verifying docker access using the new group (without needing a re-login yet)..."

# usermod only updates the group database. Processes that are already running
# (this shell AND your graphical session) keep their old group set until you
# re-login, so 'newgrp'/'sg' can only activate the group for a single new shell.
# We use 'sg' here just to prove docker works for your user right now.
if sg docker -c 'docker ps' > /dev/null 2>&1; then
    echo "Success: docker works for user '$USER' (verified via the docker group)."
else
    echo "Could not run 'docker ps' via the docker group. Check 'systemctl status docker'."
fi

echo ""
echo "IMPORTANT:"
echo "  Your current terminals and graphical session still use the OLD group set,"
echo "  so 'docker' commands there will fail with a permission error until you"
echo "  fully LOG OUT and LOG BACK IN (or reboot)."
echo ""
echo "  To use docker immediately in THIS terminal only, run:"
echo "      newgrp docker"
