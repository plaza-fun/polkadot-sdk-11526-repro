# polkadot-sdk#11526 — BlobTooLarge Reproduction

Minimal reproduction for [polkadot-sdk#11526](https://github.com/paritytech/polkadot-sdk/issues/11526).

## Issue

When deploying contracts compiled with `resolc` (Solidity → PolkaVM blob) to Asset Hub (Passet Hub testnet), two problems occur together:

1. **No actionable size information.** The `BlobTooLarge` error provides neither the actual bytecode size nor the enforced limit. A developer receiving this error has no way to know how much to trim the contract, or which limit applies.

2. **Possible 24KB EVM limit incorrectly applied to PVM.** Parity documentation states the PolkaVM deployment limit is 100KB, but in practice contracts between 24KB and 100KB receive `BlobTooLarge`. If confirmed, the EVM EIP-170 limit (24 576 bytes) is being enforced on PVM deployments instead of the PVM limit.

## Contracts

| Contract | Target size | EVM (24KB) | PVM (100KB) | Expected result |
|---|---|---|---|---|
| `SmallContract` | ~10 KB | within | within | Deploy OK on both |
| `MediumContract` | ~25–30 KB | **OVER** | within | Fail EVM, **deploy OK on PVM** |
| `LargeContract` | ~45–50 KB | **OVER** | within | Fail EVM, **deploy OK on PVM** |

## Setup

### Prerequisites

- Node.js 18+
- pnpm or npm

### Install dependencies

```bash
npm install
```

### Configure environment

```bash
cp .env.example .env
```

Edit `.env` and fill in:

```
DEPLOYER_PRIVATE_KEY=0x...   # EVM private key with testnet DOT for gas
EVM_RPC=https://services.polkadothub-rpc.com/testnet
TEST_SEED=                   # sr25519 seed phrase for direct Substrate deployment test
SUBSTRATE_WS_RPC=wss://sys.ibp.network/asset-hub-paseo
```

Fund both the EVM deployer and the Substrate account with testnet DOT from the [Paseo faucet](https://faucet.polkadot.io/).

## Reproduction Steps

### 1. Compile all contracts

```bash
npm run compile
# or: npx hardhat compile
```

This uses `resolc` (via `@parity/hardhat-polkadot`) to compile Solidity to PolkaVM blobs.

### 2. Check bytecode sizes

```bash
npm run check-size
```

Expected output confirms MediumContract and LargeContract exceed 24KB (EVM limit) but remain under 100KB (PVM limit).

### 3. Deploy via EVM RPC (standard path)

```bash
npm run deploy
```

### 4. Deploy via direct Substrate extrinsic (bypasses ETH RPC adapter)

```bash
node scripts/deploy-substrate.js
```

This uses `api.tx.revive.instantiateWithCode()` directly — no ETH RPC adapter in the path.

## Verified Results (2026-03-28, Paseo Asset Hub)

These are **actual on-chain results**, not expectations.

### Via EVM RPC (`eth_sendRawTransaction`)

| Contract | Deployed Size | EVM 24KB | PVM 100KB | Deploy Result |
|----------|--------------|----------|-----------|---------------|
| SmallContract | 5.11 KB | ✅ within | ✅ within | ✅ **Success** at `0xD7CE866e9efDE512FBBFCE0c726468c54C5dc85A` |
| MediumContract | 30.77 KB | ❌ over | ✅ within | ❌ **`BlobTooLarge`** |
| LargeContract | 47.97 KB | ❌ over | ✅ within | ❌ **`BlobTooLarge`** |

### Via direct Substrate extrinsic (`revive.instantiateWithCode`)

| Contract | Deployed Size | EVM 24KB | PVM 100KB | Deploy Result |
|----------|--------------|----------|-----------|---------------|
| SmallContract | 5.16 KB | ✅ within | ✅ within | ✅ **Success** at `0xdcff4eebd00c9fb2a23571e3a5883f584d794a1d` |
| MediumContract | 30.86 KB | ❌ over | ✅ within | ❌ **`revive.BlobTooLarge`** |
| LargeContract | 48.09 KB | ❌ over | ✅ within | ❌ **`revive.BlobTooLarge`** |

**Both deployment paths produce the same result.** The limit is enforced on-chain in `pallet_revive`, not in the ETH RPC adapter.

### Issue Confirmed

Contracts that are **well within the PVM 100KB limit** but exceed the EVM 24KB limit are rejected with `BlobTooLarge`. This confirms:

1. **The 24KB limit is enforced on-chain in `pallet_revive`**, not in the ETH RPC adapter or Hardhat tooling. Direct `revive.instantiateWithCode` substrate extrinsics also fail. The error message itself says: _"The code blob supplied is larger than `limits::code::BLOB_BYTES`"_ — this is a runtime constant, not tooling.

2. **This contradicts the [Polkadot documentation](https://docs.polkadot.com/smart-contracts/for-eth-devs/evm-vs-pvm/#current-memory-limits)** which states the PVM limit is 100KB.

3. **The error message is not actionable.** The actual raw error from the chain:

```
Module(ModuleError { index: 100, error: [28, 0, 0, 0], message: Some("BlobTooLarge") })
```

No indication of:
- The actual bytecode size submitted
- The limit that was violated
- Whether this is the EVM 24KB or PVM 100KB limit

## What Good Error Output Would Look Like

An actionable `BlobTooLarge` error should include:

```
BlobTooLarge: contract blob is 28,431 bytes; maximum allowed for PolkaVM is 102,400 bytes (100 KB).
```

Or, if the 24 KB limit is intentional for the current runtime version:

```
BlobTooLarge: contract blob is 28,431 bytes; maximum allowed is 24,576 bytes (24 KB, EIP-170).
  Note: the PolkaVM 100 KB limit is not yet active on this network.
```

Either form gives the developer a clear next step.

## Environment

- Chain: Polkadot Asset Hub Paseo Testnet
- Chain ID: 420420417
- Compiler: `resolc` via `@parity/hardhat-polkadot`
- Solidity: 0.8.28
- `ethers`: v6

## Files

```
contracts/
  SmallContract.sol    # ~10 KB — control group
  MediumContract.sol   # ~25–30 KB — over EVM limit, under PVM limit
  LargeContract.sol    # ~45–50 KB — over EVM limit, under PVM limit
scripts/
  check-size.js        # Reports bytecode sizes vs EVM/PVM limits
  deploy.js            # Deploys via EVM RPC, dumps full error objects
  deploy-substrate.js  # Deploys via direct Substrate extrinsic (bypasses ETH RPC)
```

## Related

- [polkadot-sdk#11526](https://github.com/paritytech/polkadot-sdk/issues/11526)
- [EIP-170: Contract code size limit](https://eips.ethereum.org/EIPS/eip-170)
- [pallet_revive documentation](https://paritytech.github.io/polkadot-sdk/master/pallet_revive/index.html)
