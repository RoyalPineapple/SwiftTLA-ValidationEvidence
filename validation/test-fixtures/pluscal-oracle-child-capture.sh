#!/usr/bin/env bash
set -euo pipefail

printf '%s\0' "$@" >> "$PLUSCAL_ORACLE_CAPTURE"
