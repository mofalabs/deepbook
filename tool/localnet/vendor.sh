#!/usr/bin/env bash
# Prepares the deepbookv3 repo clone for localnet deployment (one-time):
#  - vendors wormhole + pyth locally (single-instance dependency graph),
#  - patches pyth with a localnet-only test oracle constructor,
#  - creates the legacy-style TUSDC test coin,
#  - rewires the Move.toml dependency chain to local paths.
# Then run setup.sh against a fresh localnet.
#
# Usage: tool/localnet/vendor.sh <path-to-deepbookv3-repo>
set -euo pipefail

REPO=${1:?usage: vendor.sh <deepbookv3-repo>}
VENDOR="$REPO/vendor"
mkdir -p "$VENDOR"

# 1. Vendor wormhole + pyth at the revs pyth expects.
if [ ! -d "$VENDOR/wormhole" ]; then
  git clone --depth 1 --branch sui/mainnet \
    https://github.com/wormhole-foundation/wormhole.git "$VENDOR/wormhole-src"
  cp -R "$VENDOR/wormhole-src/sui/wormhole" "$VENDOR/wormhole"
  rm -rf "$VENDOR/wormhole-src" "$VENDOR/wormhole/Move.lock"
fi
if [ ! -d "$VENDOR/pyth" ]; then
  git clone --depth 1 --branch sui-contract-mainnet \
    https://github.com/pyth-network/pyth-crosschain.git "$VENDOR/pyth-src"
  cp -R "$VENDOR/pyth-src/target_chains/sui/contracts" "$VENDOR/pyth"
  rm -rf "$VENDOR/pyth-src" "$VENDOR/pyth/Move.lock"
  # pyth's wormhole dep → local vendor (single wormhole instance).
  python3 - "$VENDOR/pyth/Move.toml" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('''[dependencies.Wormhole]
git = "https://github.com/wormhole-foundation/wormhole.git"
subdir = "sui/wormhole"
rev = "sui/mainnet"''', '''[dependencies.Wormhole]
local = "../wormhole"''')
open(p, 'w').write(s)
EOF
  # Localnet-only test oracle: mint/update PriceInfoObjects without VAAs.
  python3 - "$VENDOR/pyth/sources/price_info.move" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
patch = '''
    // ------------------------------------------------------------------
    // LOCALNET TEST HARNESS ONLY (added by the deepbook Dart SDK tests).
    // Creates / updates shared PriceInfoObjects with arbitrary prices,
    // bypassing the wormhole/VAA machinery. Never deploy beyond localnet.
    // ------------------------------------------------------------------
    public fun new_test_price_info_object(
        price_identifier_bytes: vector<u8>,
        price_magnitude: u64,
        price_negative: bool,
        conf: u64,
        expo_magnitude: u64,
        expo_negative: bool,
        timestamp_secs: u64,
        ctx: &mut TxContext,
    ) {
        let identifier = pyth::price_identifier::from_byte_vec(price_identifier_bytes);
        let price = pyth::price::new(
            pyth::i64::new(price_magnitude, price_negative),
            conf,
            pyth::i64::new(expo_magnitude, expo_negative),
            timestamp_secs,
        );
        let feed = price_feed::new(identifier, price, price);
        let price_info = new_price_info(timestamp_secs, timestamp_secs, feed);
        let price_info_object = PriceInfoObject {
            id: object::new(ctx),
            price_info,
        };
        sui::transfer::share_object(price_info_object);
    }

    public fun update_test_price_info_object(
        self: &mut PriceInfoObject,
        price_magnitude: u64,
        price_negative: bool,
        conf: u64,
        expo_magnitude: u64,
        expo_negative: bool,
        timestamp_secs: u64,
    ) {
        let identifier = price_feed::get_price_identifier(&self.price_info.price_feed);
        let price = pyth::price::new(
            pyth::i64::new(price_magnitude, price_negative),
            conf,
            pyth::i64::new(expo_magnitude, expo_negative),
            timestamp_secs,
        );
        let feed = price_feed::new(identifier, price, price);
        self.price_info = new_price_info(timestamp_secs, timestamp_secs, feed);
    }
'''
anchor = '    public(friend) fun new_price_info_object('
if 'new_test_price_info_object' not in s:
    s = s.replace(anchor, patch + '\n' + anchor, 1)
open(p, 'w').write(s)
EOF
fi

# 2. Legacy-style test USDC (classic create_currency, so its CoinMetadata can
# be migrated to a SHARED Currency via coin_registry::migrate_legacy_metadata).
if [ ! -d "$VENDOR/tusdc" ]; then
  mkdir -p "$VENDOR/tusdc/sources"
  cat > "$VENDOR/tusdc/Move.toml" <<'EOF'
[package]
name = "tusdc"
edition = "2024.beta"

[dependencies]

[addresses]
tusdc = "0x0"
EOF
  cat > "$VENDOR/tusdc/sources/tusdc.move" <<'EOF'
/// Legacy-style test USDC for localnet margin tests.
module tusdc::tusdc;

use sui::coin;

public struct TUSDC has drop {}

fun init(witness: TUSDC, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        6,
        b"TUSDC",
        b"Test USDC",
        b"Localnet test USDC",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury_cap, ctx.sender());
}
EOF
fi

# 3. Rewire deepbookv3 package deps to local paths.
python3 - "$REPO" <<'EOF'
import sys
repo = sys.argv[1]
def rewrite(path, old, new):
    s = open(path).read()
    if old in s:
        open(path, 'w').write(s.replace(old, new))
rewrite(f'{repo}/packages/deepbook/Move.toml',
        'token = { git = "https://github.com/MystenLabs/deepbookv3.git", subdir = "packages/token", rev = "main"}',
        'token = { local = "../token" }')
rewrite(f'{repo}/packages/deepbook_margin/Move.toml',
        'token = { git = "https://github.com/MystenLabs/deepbookv3.git", subdir = "packages/token", rev = "main"}',
        'token = { local = "../token", override = true }')
rewrite(f'{repo}/packages/deepbook_margin/Move.toml',
        'pyth = { git = "https://github.com/pyth-network/pyth-crosschain.git", subdir = "target_chains/sui/contracts", rev = "sui-contract-mainnet" }',
        'pyth = { local = "../../vendor/pyth" }')
rewrite(f'{repo}/packages/margin_liquidation/Move.toml',
        'token = { git = "https://github.com/MystenLabs/deepbookv3.git", subdir = "packages/token", rev = "main"}',
        'token = { local = "../token", override = true }')
rewrite(f'{repo}/packages/margin_liquidation/Move.toml',
        'pyth = { git = "https://github.com/pyth-network/pyth-crosschain.git", subdir = "target_chains/sui/contracts", rev = "sui-contract-mainnet" }',
        'pyth = { local = "../../vendor/pyth" }')
print('rewired')
EOF
echo "vendor ready — now: sui start --force-regenesis --with-faucet --epoch-duration-ms 60000 && tool/localnet/setup.sh $REPO"
