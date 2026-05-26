#!/bin/bash
# 非互動部署：優先測試既有 Relay，否則執行 auto_deploy_relay.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/auto_deploy_relay.sh"
