#!/usr/bin/env bash
# Stop httpd, rebuild zt-ocp-ops-app-management, and serve again.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/stop.sh"
"${SCRIPT_DIR}/build.sh"
"${SCRIPT_DIR}/serve.sh"
