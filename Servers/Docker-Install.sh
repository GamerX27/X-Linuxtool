#!/usr/bin/env bash

# recommended to see the source before running the script https://get.docker.com/

set -euo pipefail

echo "Installing Docker from Docker site"

curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh



echo "Adding docker group if not made"
sudo groupadd docker

echo "Adding current user to the docker group"
sudo usermod -aG docker $USER

