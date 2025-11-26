#!/usr/bin/env bash
#
# Helper to deploy a fresh Escrow implementation and upgrade the existing
# proxy on Base Sepolia. Expects the repo root to contain `.env.deploy`
# (see template inside the repo) and either an exported PROXY_ADDRESS or a
# PROXY_ADDRESS entry in that env file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure foundry binaries are on PATH when running from non-login shells.
export PATH="$HOME/.foundry/bin:$PATH"
export FOUNDRY_CACHE_PATH="$REPO_ROOT/.foundry-cache"

ENV_FILE="${1:-"$REPO_ROOT/.env.deploy"}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file '$ENV_FILE' was not found. Populate one with at least RPC_URL, PRIVATE_KEY." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${RPC_URL:?RPC_URL is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
PROXY_ADDRESS="${PROXY_ADDRESS:-${ESCROW_PROXY_ADDRESS:-}}"
if [[ -z "$PROXY_ADDRESS" ]]; then
  echo "Set PROXY_ADDRESS in the environment or inside $ENV_FILE before running this script." >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
ARTIFACT_PATH="$REPO_ROOT/latest-escrow-impl-$TIMESTAMP.json"
TMP_ARTIFACT="$ARTIFACT_PATH.tmp"
rm -f "$TMP_ARTIFACT"
trap 'rm -f "$TMP_ARTIFACT"' EXIT

echo ">> Compiling contracts"
forge build

echo ">> Deploying Escrow implementation (artifact: $ARTIFACT_PATH)"
FOUNDRY_AUTO_COMPILE=0 forge create contracts/modules/escrow/Escrow.sol:Escrow \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --json | tee "$TMP_ARTIFACT"

mv "$TMP_ARTIFACT" "$ARTIFACT_PATH"
trap - EXIT

ADDRESS_OUTPUT="$(python3 - <<'PY' "$ARTIFACT_PATH"
import json, sys
path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
addr = data.get("deployedTo") or data.get("deployed_to") or data.get("contractAddress")
sender = ""
nonce = ""
if not addr:
    tx = data.get("transaction") or {}
    sender = tx.get("from") or ""
    tx_nonce = tx.get("nonce")
    if tx_nonce is not None and sender:
        if isinstance(tx_nonce, str):
            tx_nonce = int(tx_nonce, 16) if tx_nonce.startswith(("0x", "0X")) else int(tx_nonce)
        else:
            tx_nonce = int(tx_nonce)
        nonce = str(tx_nonce)
print(addr or "")
print((sender or "").lower())
print(nonce)
PY
)"

NEW_IMPLEMENTATION="$(printf '%s\n' "$ADDRESS_OUTPUT" | sed -n '1p')"
SENDER="$(printf '%s\n' "$ADDRESS_OUTPUT" | sed -n '2p')"
NONCE="$(printf '%s\n' "$ADDRESS_OUTPUT" | sed -n '3p')"

if [[ -z "$NEW_IMPLEMENTATION" ]]; then
  if [[ -z "$SENDER" || -z "$NONCE" ]]; then
    echo "Failed to determine implementation address from forge output." >&2
    exit 1
  fi
  echo ">> Deriving implementation address from sender/nonce"
  NEW_IMPLEMENTATION="$(cast compute-address --from "$SENDER" --nonce "$NONCE")"
fi

python3 - <<'PY' "$ARTIFACT_PATH" "$NEW_IMPLEMENTATION"
import json, sys
path, address = sys.argv[1:]
with open(path) as fh:
    data = json.load(fh)
data["deployedTo"] = address
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

echo ">> New implementation deployed to: $NEW_IMPLEMENTATION"

echo ">> Running UUPS upgrade via scripts/UpgradeModuleUUPS.s.sol"
NEW_IMPLEMENTATION="$NEW_IMPLEMENTATION" \
PROXY_ADDRESS="$PROXY_ADDRESS" \
PRIVATE_KEY="$PRIVATE_KEY" \
forge script scripts/UpgradeModuleUUPS.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation

echo ">> Upgrade broadcast. Verify implementation slot:"
IMPL_SLOT=0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC
cast storage "$PROXY_ADDRESS" "$IMPL_SLOT" --rpc-url "$RPC_URL"

echo ">> Done. If upgrade succeeded, consider removing generated keystores and artifacts when no longer needed."
