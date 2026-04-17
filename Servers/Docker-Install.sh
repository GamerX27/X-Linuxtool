#!/usr/bin/env bash

# recommended to see the source before running the script https://get.docker.com/

set -euo pipefail

echo "Installing Docker from Docker site"

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh



echo "Adding docker group if not made"
if ! getent group docker > /dev/null 2>&1; then
    sudo groupadd docker
else
    echo "docker group already exists"
fi

echo "Adding current user to the docker group"
sudo usermod -aG docker $USER

echo ""
echo "IMPORTANT: Please log out and log back in (or restart your session) for the group changes to take effect."
