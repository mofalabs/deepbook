#!/usr/bin/env bash
# Deploys the FULL DeepBook V3 stack to a running localnet and writes
# tool/localnet/localnet_ids.json for the *_localnet_test.dart suites:
#
#   token (DEEP) → wormhole → pyth (patched w/ test oracle) → deepbook
#   → dusdc → tusdc → deepbook_margin → margin_liquidation,
#   plus Currency migrations (DEEP/TUSDC) and test-coin mints.
#
# Prereqs:
#   - sui >= 1.76 (https://github.com/MystenLabs/sui/releases)
#   - a running localnet with SHORT EPOCHS (stake activation needs an epoch
#     boundary):  sui start --force-regenesis --with-faucet --epoch-duration-ms 60000
#   - a clone of https://github.com/MystenLabs/deepbookv3 prepared as follows:
#       * packages/deepbook:        token dep → { local = "../token" }
#       * packages/deepbook_margin: token dep → { local = "../token", override = true }
#                                   pyth dep  → { local = "../../vendor/pyth" }
#       * vendor/wormhole:  wormhole.git sui/mainnet → sui/wormhole
#       * vendor/pyth:      pyth-crosschain.git sui-contract-mainnet →
#                           target_chains/sui/contracts, wormhole dep →
#                           { local = "../wormhole" }, plus the
#                           new_test_price_info_object patch in price_info.move
#       * vendor/tusdc:     legacy-style test USDC (see repo history)
#
# Usage: tool/localnet/setup.sh <path-to-deepbookv3-repo> [sui-binary]
set -euo pipefail

REPO=${1:?usage: setup.sh <deepbookv3-repo> [sui-binary]}
SUI=${2:-sui}
OUT="$(cd "$(dirname "$0")" && pwd)/localnet_ids.json"
PUBFILE="$REPO/localnet_pub.toml"
TMP=$(mktemp -d)

$SUI client new-env --alias localnet --rpc http://127.0.0.1:9000 2>/dev/null || true
$SUI client switch --env localnet
ADDR=$($SUI client active-address)
$SUI client faucet && sleep 3

# Publication records are chain-scoped; clear stale ones after a regenesis.
rm -f "$PUBFILE"
find "$REPO" -name "Pub.localnet.toml" -delete

publish() { # dir name
  (cd "$1" && $SUI client test-publish --build-env mainnet \
      --pubfile-path "$PUBFILE" --json) > "$TMP/$2.json"
  echo "published $2"
}

publish "$REPO/packages/token" token
publish "$REPO/vendor/wormhole" wormhole
publish "$REPO/vendor/pyth" pyth
publish "$REPO/packages/deepbook" deepbook
publish "$REPO/packages/dusdc" dusdc
publish "$REPO/vendor/tusdc" tusdc
publish "$REPO/packages/deepbook_margin" deepbook_margin
publish "$REPO/packages/margin_liquidation" margin_liquidation

ADMIN_KEY=$($SUI keytool export --key-identity "$ADDR" --json | python3 -c \
  "import json,sys; print(json.load(sys.stdin)['exportedPrivateKey'])")

python3 - "$TMP" "$OUT" "$ADMIN_KEY" <<'EOF'
import json, sys
tmp, out_path, admin_key = sys.argv[1], sys.argv[2], sys.argv[3]
ids = {"endpoint": "http://127.0.0.1:9000", "adminKey": admin_key}
def load(name):
    raw = open(f"{tmp}/{name}.json").read()
    return json.loads(raw[raw.find("{"):])
def scan(name, pkg_key, created=None):
    d = load(name)
    assert d["effects"]["status"]["status"] == "success", name
    for ch in d.get("objectChanges", []):
        if ch.get("type") == "published":
            ids[pkg_key] = ch["packageId"]
        elif ch.get("type") == "created" and created:
            ot, owner = ch.get("objectType", ""), ch.get("owner", {})
            for key, (suffix, shared) in created.items():
                if suffix in ot and "Upgrade" not in ot:
                    if shared and not (isinstance(owner, dict) and "Shared" in owner):
                        continue
                    ids[key] = ch["objectId"]
scan("token", "tokenPackageId", {"deepTreasuryId": ("ProtectedTreasury", True),
                                  "deepMetadata": ("CoinMetadata", False)})
scan("wormhole", "wormholePackageId")
scan("pyth", "pythPackageId")
scan("deepbook", "deepbookPackageId", {"registryId": ("registry::Registry", True),
                                        "adminCap": ("DeepbookAdminCap", False)})
scan("dusdc", "dusdcPackageId", {"dusdcTreasuryCap": ("TreasuryCap", False)})
scan("tusdc", "tusdcPackageId", {"tusdcTreasuryCap": ("TreasuryCap", False),
                                  "tusdcMetadata": ("CoinMetadata", False)})
scan("deepbook_margin", "marginPackageId",
     {"marginRegistryId": ("MarginRegistry", True),
      "marginAdminCap": ("MarginAdminCap", False)})
scan("margin_liquidation", "liquidationPackageId",
     {"liquidationAdminCap": ("LiquidationAdminCap", False)})
json.dump(ids, open(out_path, "w"), indent=2)
print("wrote", out_path)
EOF

get() { python3 -c "import json;print(json.load(open('$OUT'))['$1'])"; }

# Currency migrations (shared Currency objects for the margin oracle).
migrate() { # coin-type metadata-id ids-key
  $SUI client ptb --move-call "0x2::coin_registry::migrate_legacy_metadata<$1>" \
      @0xc @"$2" --json > "$TMP/mig.json" 2>&1
  python3 - "$TMP/mig.json" "$OUT" "$3" <<'EOF'
import json, sys
raw = open(sys.argv[1]).read()
d = json.loads(raw[raw.find("{"):])
assert d["effects"]["status"]["status"] == "success"
for ch in d.get("objectChanges", []):
    if "Currency" in ch.get("objectType", ""):
        ids = json.load(open(sys.argv[2]))
        ids[sys.argv[3]] = ch["objectId"]
        json.dump(ids, open(sys.argv[2], "w"), indent=2)
        print(sys.argv[3], ch["objectId"])
EOF
}
migrate "$(get tokenPackageId)::deep::DEEP" "$(get deepMetadata)" deepCurrencyId
migrate "$(get tusdcPackageId)::tusdc::TUSDC" "$(get tusdcMetadata)" tusdcCurrencyId

# Mint test coins to the admin.
$SUI client call --package 0x2 --module coin --function mint_and_transfer \
  --type-args "$(get dusdcPackageId)::dusdc::DUSDC" \
  --args "$(get dusdcTreasuryCap)" 1000000000000 "$ADDR" > /dev/null
$SUI client call --package 0x2 --module coin --function mint_and_transfer \
  --type-args "$(get tusdcPackageId)::tusdc::TUSDC" \
  --args "$(get tusdcTreasuryCap)" 1000000000000 "$ADDR" > /dev/null
echo "minted DUSDC + TUSDC to $ADDR"

# Fresh chain, fresh margin bootstrap state.
rm -f "$(dirname "$OUT")/margin_state.json"
echo "done"
