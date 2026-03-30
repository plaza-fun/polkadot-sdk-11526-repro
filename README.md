# polkadot-sdk#11526 — BlobTooLarge Reproduction

Minimal reproduction for [polkadot-sdk#11526](https://github.com/paritytech/polkadot-sdk/issues/11526).

## ⚠️ Resolution (2026-03-31)

**This issue was caused by incorrect Hardhat configuration on our side, not a chain bug.**

`@parity/hardhat-polkadot` v0.2.0 renamed the network config field from `polkavm` to `polkadot` (breaking change, no deprecation warning). Our config used the old `polkavm: true` field, so `resolc` was never invoked — all deployments used standard solc EVM bytecode, subject to the 24KB EIP-170 limit.

After fixing the config to `polkadot: true`:
- `resolc` correctly compiles PVM bytecode (prefix `0x50564d00`)
- **All three contracts deploy successfully** — PVM `BLOB_BYTES` limit is 1MB

See [correction on the issue](https://github.com/paritytech/polkadot-sdk/issues/11526#issuecomment-4158811385).

## Contracts

| Contract | EVM (solc) | PVM (resolc) | Bloat | EVM 24KB | PVM 1MB |
|---|---|---|---|---|---|
| `SmallContract` | 5,231 B | 52,407 B | 10x | within | within |
| `MediumContract` | 31,507 B | 341,664 B | 10.8x | **OVER** | within |
| `LargeContract` | 49,123 B | 555,536 B | 11.3x | **OVER** | within |

## Results

### Original results (2026-03-28) — WRONG CONFIG (`polkavm: true`, resolc not triggered)

Deployed EVM bytecode. MediumContract and LargeContract hit 24KB EIP-170 limit. **This was expected behavior for EVM bytecode — not a bug.**

| Contract | codeType | Deploy |
|----------|----------|--------|
| SmallContract | Evm | ✅ at `0xD7CE866e9efDE512FBBFCE0c726468c54C5dc85A` |
| MediumContract | Evm | ❌ BlobTooLarge (EIP-170 24KB) |
| LargeContract | Evm | ❌ BlobTooLarge (EIP-170 24KB) |

### Corrected results (2026-03-31) — CORRECT CONFIG (`polkadot: true`, resolc compiles PVM)

Deployed genuine PVM bytecode. All contracts deploy within 1MB limit.

| Contract | codeType | Deploy |
|----------|----------|--------|
| SmallContract | **Pvm** | ✅ at `0x961Ea3C4141F652a1958eE398b178F0BCcD95020` |
| MediumContract | **Pvm** | ✅ at `0x5711bD503D73Dcc37094B6F10D21bF24124d5aB3` |
| LargeContract | **Pvm** | ✅ at `0x93F01AaD7d42F660499E4f747FCB61826e34ece7` |

## Root Cause

`@parity/hardhat-polkadot` plugin checks `network.config.polkadot` (not `network.config.polkavm`) to decide whether to use resolc:

```javascript
// v0.1.x: checked polkavm
if (!hre.network.config.polkavm) return await runSuper(args);

// v0.2.x: checks polkadot
if (!hre.network.config.polkadot) return await runSuper(args);
```

The rename happened without backwards compatibility or deprecation warning. Projects upgrading from 0.1.x to 0.2.x silently stop using resolc.

## Remaining Issue: Error Messages

While the BlobTooLarge behavior is correct for EVM bytecode, the **error message is still not actionable**:

```
Module(ModuleError { index: 100, error: [28, 0, 0, 0], message: Some("BlobTooLarge") })
```

A better error would include the actual size and the applicable limit.

## Setup

### Install

```bash
npm install
```

### Configure

```bash
cp .env.example .env
# Fill in DEPLOYER_PRIVATE_KEY and optional TEST_SEED
```

### Compile (PVM bytecode)

```bash
npx hardhat compile --network polkadotHubTestnet --force
```

**Important**: Must specify `--network polkadotHubTestnet` to trigger resolc. Default `hardhat compile` uses the `hardhat` network which compiles with solc.

### Deploy

```bash
node scripts/deploy-pvm.js    # Deploy PVM bytecode via EVM RPC
node scripts/deploy.js         # Deploy EVM bytecode via EVM RPC (original test)
```

## Environment

- Chain: Polkadot Asset Hub Paseo Testnet (Chain ID 420420417)
- `@parity/hardhat-polkadot`: 0.2.7
- `@parity/resolc`: 1.0.0 (downloads resolc 0.5.0)
- Solidity: 0.8.28

## Related

- [polkadot-sdk#11526](https://github.com/paritytech/polkadot-sdk/issues/11526)
- [polkadot-sdk#11525](https://github.com/paritytech/polkadot-sdk/issues/11525) — PVM call chain revert
- [EIP-170: Contract code size limit](https://eips.ethereum.org/EIPS/eip-170)
