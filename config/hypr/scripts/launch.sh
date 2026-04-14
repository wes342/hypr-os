#!/usr/bin/env bash
# Wrapper that calls the main launch script
exec "$(dirname "$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")")/scripts/launch.sh" "$@"
