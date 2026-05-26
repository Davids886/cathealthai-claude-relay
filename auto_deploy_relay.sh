#!/bin/bash
# 部署 Vercel Edge Claude Relay 並更新 OpenRouterService.swift
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/deploy_vercel.sh"
