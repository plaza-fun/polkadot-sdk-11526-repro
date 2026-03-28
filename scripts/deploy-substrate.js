/**
 * Deploy contracts directly via pallet_revive.instantiateWithCode (Substrate extrinsic).
 *
 * This bypasses the ETH RPC adapter entirely to determine whether the 24KB limit
 * is enforced by pallet_revive on-chain or by the ETH RPC translation layer.
 *
 * If this script ALSO fails with BlobTooLarge → the limit is on-chain in pallet_revive.
 * If this script SUCCEEDS → the limit is in the ETH RPC adapter, not pallet_revive.
 *
 * Usage: node scripts/deploy-substrate.js
 */

require('dotenv').config();
const { ApiPromise, WsProvider, Keyring } = require('@polkadot/api');
const { keccakAsU8a } = require('@polkadot/util-crypto');
const fs = require('fs');
const path = require('path');

const SUBSTRATE_WS_RPC = process.env.SUBSTRATE_WS_RPC || 'wss://sys.ibp.network/asset-hub-paseo';

function loadArtifact(name) {
  const p = path.join(__dirname, '..', 'artifacts', 'contracts', `${name}.sol`, `${name}.json`);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function hexByteLen(hex) {
  if (!hex || hex === '0x') return 0;
  return Math.floor((hex.startsWith('0x') ? hex.slice(2) : hex).length / 2);
}

function kb(bytes) {
  return (bytes / 1024).toFixed(2) + ' KB';
}

async function deployViaSubstrate(api, account, contractName) {
  console.log(`\n${'─'.repeat(60)}`);
  console.log(`  Deploying ${contractName} via revive.instantiateWithCode`);
  console.log(`  (Direct Substrate extrinsic — bypasses ETH RPC adapter)`);
  console.log(`${'─'.repeat(60)}`);

  const artifact = loadArtifact(contractName);
  const bytecode = artifact.bytecode;
  const size = hexByteLen(bytecode);
  console.log(`  Bytecode size: ${size.toLocaleString()} bytes (${kb(size)})`);
  console.log(`  EVM 24KB:  ${size > 24576 ? '❌ EXCEEDS' : '✅ OK'}`);
  console.log(`  PVM 100KB: ${size > 102400 ? '❌ EXCEEDS' : '✅ OK'}`);

  const gasLimit = {
    refTime: '1000000000000',
    proofSize: '1024000',
  };
  const storageDeposit = '1000000000000'; // 100 DOT

  // Constructor data: empty for no-arg constructors, or ABI-encoded for constructors with args
  // SmallContract/MediumContract/LargeContract all have no-arg constructors
  const constructorData = '0x';

  // Salt: unique per deployment to avoid address collision
  const salt = '0x' + Buffer.from(contractName + '_' + Date.now()).toString('hex').padEnd(64, '0').slice(0, 64);

  const tx = api.tx.revive.instantiateWithCode(
    0,                  // value: no DOT sent to constructor
    gasLimit,           // weightLimit
    storageDeposit,     // storageDepositLimit
    bytecode,           // code: the PVM blob
    constructorData,    // data: constructor calldata
    salt,               // salt: for deterministic address
  );

  return new Promise((resolve) => {
    tx.signAndSend(account, { era: 0, nonce: -1 }, ({ status, events, dispatchError }) => {
      if (!status.isInBlock) return;

      console.log(`  Block: ${status.asInBlock.toHex().slice(0, 18)}`);

      if (dispatchError) {
        if (dispatchError.isModule) {
          const decoded = api.registry.findMetaError(dispatchError.asModule);
          console.log(`  ❌ FAILED: ${decoded.section}.${decoded.name}`);
          console.log(`     ${decoded.docs?.join(' ') || ''}`);
          console.log(`\n  Error details:`);
          console.log(`     Module index: ${dispatchError.asModule.index.toString()}`);
          console.log(`     Error index:  ${dispatchError.asModule.error.toString()}`);
          console.log(`     Error name:   ${decoded.name}`);
          console.log(`     Contains size info: NO`);
          console.log(`     Contains limit info: NO`);
        } else {
          console.log(`  ❌ FAILED: ${dispatchError.toString()}`);
        }
        const errName = dispatchError.isModule
          ? api.registry.findMetaError(dispatchError.asModule).name
          : dispatchError.toString();
        resolve({ success: false, error: errName });
        return;
      }

      // Look for instantiation events
      let contractAddr = null;
      for (const { event } of events) {
        if (event.section === 'revive' && event.method === 'Instantiated') {
          const [deployer, contract] = event.data;
          contractAddr = contract.toString();
          console.log(`  ✅ SUCCESS`);
          console.log(`  Contract: ${contractAddr}`);
        }
      }

      if (!contractAddr) {
        // Check if contract reverted
        for (const { event } of events) {
          if (event.section === 'revive' && event.method === 'ContractReverted') {
            console.log(`  ❌ ContractReverted during instantiation`);
            resolve({ success: false, error: 'ContractReverted' });
            return;
          }
        }
        console.log(`  ⚠️  No Instantiated event found`);
        // Print all events for debugging
        for (const { event } of events) {
          console.log(`     Event: ${event.section}.${event.method}`);
        }
      }

      resolve({ success: !!contractAddr, address: contractAddr });
    }).catch((err) => {
      console.log(`  ❌ Send failed: ${err.message?.slice(0, 200)}`);
      resolve({ success: false, error: err.message });
    });
  });
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  polkadot-sdk#11526 — Deploy via Substrate Extrinsic');
  console.log('  Bypasses ETH RPC adapter to test pallet_revive directly');
  console.log('═══════════════════════════════════════════════════════════\n');

  if (!process.env.TEST_SEED) {
    console.error('TEST_SEED required in .env (sr25519 seed phrase)');
    process.exit(1);
  }

  const wsProvider = new WsProvider(SUBSTRATE_WS_RPC);
  const api = await ApiPromise.create({
    provider: wsProvider,
    throwOnConnect: false,
    throwOnUnknown: false,
    noInitWarn: true,
  });
  console.log('Connected:', (await api.rpc.system.chain()).toString());

  const keyring = new Keyring({ type: 'sr25519' });
  const account = keyring.addFromUri(process.env.TEST_SEED);
  const h160 = '0x' + Buffer.from(keccakAsU8a(account.publicKey).slice(-20)).toString('hex');
  console.log(`Account: ${account.address}`);
  console.log(`H160:    ${h160}`);

  const results = [];
  const WAIT = 20000; // Wait between deployments for nonce

  for (const name of ['SmallContract', 'MediumContract', 'LargeContract']) {
    const result = await deployViaSubstrate(api, account, name);
    results.push({ name, ...result });

    if (name !== 'LargeContract') {
      console.log(`\n  Waiting ${WAIT / 1000}s for next block...\n`);
      await new Promise((r) => setTimeout(r, WAIT));
    }
  }

  // Summary
  console.log(`\n${'═'.repeat(60)}`);
  console.log('  SUMMARY — Substrate Direct Deployment');
  console.log(`${'═'.repeat(60)}\n`);

  for (const r of results) {
    const artifact = loadArtifact(r.name);
    const size = hexByteLen(artifact.bytecode);
    const icon = r.success ? '✅' : '❌';
    const status = r.success ? `at ${r.address}` : `${r.error}`;
    console.log(`  ${icon} ${r.name.padEnd(18)} ${kb(size).padEnd(10)} ${status}`);
  }

  const evm_failed = results.filter(r => !r.success && hexByteLen(loadArtifact(r.name).bytecode) <= 102400);
  if (evm_failed.length > 0) {
    console.log(`\n  CONCLUSION:`);
    console.log(`  Contracts within PVM 100KB limit ALSO fail via direct Substrate extrinsic.`);
    console.log(`  → The 24KB limit is enforced ON-CHAIN in pallet_revive,`);
    console.log(`    not in the ETH RPC adapter.`);
    console.log(`  → This contradicts the documented PVM 100KB limit.`);
  } else if (results.every(r => r.success)) {
    console.log(`\n  CONCLUSION:`);
    console.log(`  All contracts deploy successfully via direct Substrate extrinsic!`);
    console.log(`  → The 24KB limit is in the ETH RPC adapter, NOT pallet_revive.`);
    console.log(`  → The fix should be in the ETH RPC translation layer.`);
  }

  console.log(`\n  See: https://github.com/paritytech/polkadot-sdk/issues/11526`);

  await api.disconnect();
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
