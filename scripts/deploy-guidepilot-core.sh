#!/usr/bin/env bash
# Deploys the GuidePilot core (force-app/, via manifest/guidepilot-core.xml) to any org.
# Contains no objects, layouts, forms or scheduled jobs, so it doesn't clash with the org's own setup.
#
#   scripts/deploy-guidepilot-core.sh <org-alias>
set -euo pipefail
ORG="${1:?usage: scripts/deploy-guidepilot-core.sh <org-alias>}"
cd "$(dirname "$0")/.."
sf project deploy start --manifest manifest/guidepilot-core.xml --target-org "$ORG" \
    --test-level RunSpecifiedTests --tests GuidePilotControllerTest
