#!/usr/bin/env bash
exec "$(dirname "$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")")/scripts/launcher.sh" "$@"
