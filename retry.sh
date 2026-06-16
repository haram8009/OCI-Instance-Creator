#!/usr/bin/env bash
set -Eeuo pipefail

APP_HOME="${APP_HOME:-/app}"

exec "$APP_HOME/scripts/bin/supervisor.sh"
