#!/bin/bash
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/deploy_vercel.sh"
