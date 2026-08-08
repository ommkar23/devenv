#!/usr/bin/env bash
# Run on the GCE host as user op. Stops the development container without deleting it.
set -euo pipefail

docker stop devenv
