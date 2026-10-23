#!/usr/bin/env bash
# Deploys the personal-org extras (demo-org/) to your dev org. Never run this against a client org.
# The keep-alive job blocks redeploying its own class, so it's stopped first and restarted after.
#
#   scripts/deploy-demo-org.sh [org-alias]     (default: sfdevorg)
set -euo pipefail
ORG="${1:-sfdevorg}"
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Stopping GuidePilot keep-alive jobs in $ORG ..."
echo 'GuidePilotKeepAlive.stop();' > "$TMP/stop.apex"
sf apex run --file "$TMP/stop.apex" --target-org "$ORG" >/dev/null 2>&1 || echo "  (none running yet)"

echo "Deploying demo-org/ ..."
sf project deploy start --source-dir demo-org --target-org "$ORG" \
    --test-level RunSpecifiedTests --tests GuidePilotKeepAliveTest

echo "Restarting keep-alive jobs ..."
echo 'GuidePilotKeepAlive.start();' > "$TMP/start.apex"
sf apex run --file "$TMP/start.apex" --target-org "$ORG" >/dev/null
echo "Done."
