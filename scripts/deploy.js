require('dotenv').config();
const { ethers } = require('ethers');
const fs   = require('fs');
const path = require('path');

// ── Config ───────────────────────────────────────────────────────────────────

const RPC_URL    = process.env.EVM_RPC || 'https://services.polkadothub-rpc.com/testnet';
const CHAIN_ID   = 420420417;
const PRIV_KEY   = process.env.DEPLOYER_PRIVATE_KEY;

if (!PRIV_KEY) {
  console.error('\nError: DEPLOYER_PRIVATE_KEY not set in .env\n');
  process.exit(1);
}

// ── Artifact helpers ─────────────────────────────────────────────────────────

function loadArtifact(contractName) {
  // Hardhat stores artifacts at artifacts/contracts/<Name>.sol/<Name>.json
  const candidate = path.join(
    __dirname, '..', 'artifacts', 'contracts',
    `${contractName}.sol`, `${contractName}.json`
  );
  if (!fs.existsSync(candidate)) {
    throw new Error(`Artifact not found: ${candidate}\nRun 'npx hardhat compile' first.`);
  }
  return JSON.parse(fs.readFileSync(candidate, 'utf8'));
}

function hexByteLen(hex) {
  if (!hex || hex === '0x') return 0;
  return Math.floor((hex.startsWith('0x') ? hex.slice(2) : hex).length / 2);
}

function kb(bytes) {
  return (bytes / 1024).toFixed(2) + ' KB';
}

// ── Logging utilities ─────────────────────────────────────────────────────────

const LINE = '─'.repeat(70);

function section(title) {
  console.log('\n' + LINE);
  console.log(` ${title}`);
  console.log(LINE);
}

function printErrorFull(label, err) {
  console.log(`\n  [ERROR] ${label}`);
  console.log('  Raw error object dump:');
  // Print every enumerable property to show how little info is available
  const props = {};
  for (const key of Object.getOwnPropertyNames(err)) {
    const val = err[key];
    if (key === 'stack') continue; // skip stack trace noise
    props[key] = val;
  }
  console.log(JSON.stringify(props, (k, v) => {
    if (typeof v === 'bigint') return v.toString();
    return v;
  }, 2));
  console.log('\n  err.message  :', err.message);
  console.log('  err.code     :', err.code     ?? '(none)');
  console.log('  err.reason   :', err.reason   ?? '(none)');
  console.log('  err.data     :', err.data     ?? '(none)');
  console.log('  err.info     :', JSON.stringify(err.info ?? null));
  if (err.error) {
    console.log('  err.error    :', JSON.stringify(err.error, null, 4));
  }
  if (err.shortMessage) console.log('  shortMessage :', err.shortMessage);
  if (err.transaction)  console.log('  transaction  :', JSON.stringify(err.transaction));
  if (err.receipt)      console.log('  receipt      :', JSON.stringify(err.receipt));
}

// ── Core deploy function ──────────────────────────────────────────────────────

async function deployContract(wallet, contractName, provider) {
  const artifact      = loadArtifact(contractName);
  const deployedSize  = hexByteLen(artifact.deployedBytecode);
  const creationSize  = hexByteLen(artifact.bytecode);
  const EVM_LIMIT     = 24 * 1024;
  const PVM_LIMIT     = 100 * 1024;

  section(`Deploying: ${contractName}`);
  console.log(`  Deployed bytecode : ${deployedSize.toLocaleString()} bytes  (${kb(deployedSize)})`);
  console.log(`  Creation bytecode : ${creationSize.toLocaleString()} bytes  (${kb(creationSize)})`);
  console.log(`  EVM limit (24KB)  : ${deployedSize > EVM_LIMIT ? 'EXCEEDS' : 'ok'}`);
  console.log(`  PVM limit (100KB) : ${deployedSize > PVM_LIMIT ? 'EXCEEDS' : 'ok'}`);

  if (deployedSize > EVM_LIMIT && deployedSize <= PVM_LIMIT) {
    console.log(`\n  NOTE: This contract exceeds EIP-170 (EVM 24KB) but is under the PVM 100KB limit.`);
    console.log(`        It SHOULD be deployable on PolkaVM / Passet Hub.`);
    console.log(`        If it fails with BlobTooLarge, that is issue #11526.`);
  }

  // Estimate gas before sending — also reveals size-related errors early
  console.log(`\n  Estimating gas ...`);
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const deployTx = await factory.getDeployTransaction();

  let gasEstimate;
  try {
    gasEstimate = await provider.estimateGas({ ...deployTx, from: wallet.address });
    console.log(`  Gas estimate : ${gasEstimate.toLocaleString()}`);
  } catch (estimateErr) {
    console.log(`\n  Gas estimation FAILED (often the first sign of BlobTooLarge):`);
    printErrorFull('estimateGas failure', estimateErr);
    console.log(`\n  Attempting to send the transaction anyway to capture the on-chain error ...`);
  }

  // Build Legacy (type 0) transaction — required by Passet Hub / pallet_revive
  const feeData = await provider.getFeeData();
  const nonce   = await provider.getTransactionCount(wallet.address);

  const txOverrides = {
    type: 0,
    gasPrice: feeData.gasPrice ?? 1_000_000_000_000n,
    gasLimit: gasEstimate ?? 30_000_000n,  // generous fallback if estimate failed
    nonce,
  };

  console.log(`\n  Sending deployment transaction (type 0 / legacy) ...`);
  console.log(`  From     : ${wallet.address}`);
  console.log(`  Gas price: ${txOverrides.gasPrice.toString()}`);
  console.log(`  Gas limit: ${txOverrides.gasLimit.toString()}`);

  let tx, receipt, contractAddress;
  try {
    const contract = await factory.deploy(txOverrides);
    tx = contract.deploymentTransaction();
    console.log(`  TX hash  : ${tx?.hash ?? '(unknown)'}`);
    console.log(`  Waiting for confirmation ...`);
    receipt = await contract.waitForDeployment();
    contractAddress = await contract.getAddress();
    console.log(`\n  SUCCESS`);
    console.log(`  Contract address : ${contractAddress}`);
    console.log(`  TX hash          : ${tx?.hash}`);
    console.log(`  Gas used         : ${receipt.deploymentTransaction()?.gasLimit?.toString() ?? 'n/a'}`);
    return { success: true, address: contractAddress, txHash: tx?.hash };
  } catch (deployErr) {
    console.log(`\n  DEPLOYMENT FAILED`);
    console.log(`  ╔══════════════════════════════════════════════════════════════╗`);
    console.log(`  ║  ISSUE #11526 REPRODUCTION — Full error dump follows        ║`);
    console.log(`  ╚══════════════════════════════════════════════════════════════╝`);
    printErrorFull(`deploy ${contractName}`, deployErr);

    // Analysis: what info does the error actually give us?
    console.log(`\n  ── Error Actionability Analysis ─────────────────────────────`);
    const msg = (deployErr.message ?? '') + JSON.stringify(deployErr.info ?? {});
    const hasSizeInfo  = /\d+\s*(byte|kb)/i.test(msg);
    const hasLimitInfo = /limit|max|maximum/i.test(msg);
    const hasBlobMsg   = /blob/i.test(msg);
    console.log(`  Contains "Blob*"         : ${hasBlobMsg   ? 'YES' : 'no'}`);
    console.log(`  Contains size in bytes   : ${hasSizeInfo  ? 'YES' : 'no (MISSING — this is the bug)'}`);
    console.log(`  Contains limit value     : ${hasLimitInfo ? 'YES' : 'no (MISSING — this is the bug)'}`);
    if (!hasSizeInfo && !hasLimitInfo) {
      console.log(`\n  CONCLUSION: The error gives no indication of actual bytecode size`);
      console.log(`              or what the limit is. A developer receiving this error`);
      console.log(`              has no way to know how much they need to reduce the`);
      console.log(`              contract, or whether the limit is 24KB or 100KB.`);
      console.log(`              This is the core problem reported in issue #11526.`);
    }
    return { success: false, error: deployErr };
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\n' + '═'.repeat(70));
  console.log(' polkadot-sdk#11526 Reproduction Script');
  console.log(' BlobTooLarge: missing size info on contract deployment failure');
  console.log('═'.repeat(70));
  console.log(`\n  RPC URL  : ${RPC_URL}`);
  console.log(`  Chain ID : ${CHAIN_ID}`);

  const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'passet-hub' });
  const wallet   = new ethers.Wallet(PRIV_KEY, provider);

  console.log(`  Deployer : ${wallet.address}`);

  let balance;
  try {
    balance = await provider.getBalance(wallet.address);
    console.log(`  Balance  : ${ethers.formatEther(balance)} DOT`);
    if (balance === 0n) {
      console.warn('\n  WARNING: Deployer balance is 0. Deployments will likely fail with gas errors.');
      console.warn('  Fund the deployer address on Paseo testnet before running this script.\n');
    }
  } catch (e) {
    console.warn('\n  WARNING: Could not fetch balance:', e.message);
  }

  const results = [];

  // ── 1. SmallContract (~10KB) — control group ────────────────────────────
  console.log('\n\n  CONTRACT 1/3: SmallContract (control group — ~10KB)');
  console.log('  This should deploy successfully on both EVM and PVM.');
  const r1 = await deployContract(wallet, 'SmallContract', provider);
  results.push({ name: 'SmallContract', ...r1 });

  // ── 2. MediumContract (~25-30KB) — over EVM limit ──────────────────────
  console.log('\n\n  CONTRACT 2/3: MediumContract (~25-30KB)');
  console.log('  Over EVM 24KB limit. Should succeed on PVM (100KB limit).');
  const r2 = await deployContract(wallet, 'MediumContract', provider);
  results.push({ name: 'MediumContract', ...r2 });

  // ── 3. LargeContract (~45-50KB) — well over EVM limit ──────────────────
  console.log('\n\n  CONTRACT 3/3: LargeContract (~45-50KB)');
  console.log('  Well over EVM 24KB limit. Still under PVM 100KB limit — should deploy on PVM.');
  const r3 = await deployContract(wallet, 'LargeContract', provider);
  results.push({ name: 'LargeContract', ...r3 });

  // ── Final report ─────────────────────────────────────────────────────────
  section('Deployment Results Summary');
  for (const r of results) {
    const status = r.success ? 'SUCCESS' : 'FAILED';
    const detail = r.success ? `at ${r.address}` : r.error?.message?.slice(0, 80) ?? '';
    console.log(`  ${r.name.padEnd(20)} ${status.padEnd(10)} ${detail}`);
  }

  const allSuccess = results.every(r => r.success);
  const overEVMFailed = results.some(r => !r.success);

  console.log();
  if (overEVMFailed) {
    console.log('  One or more deployments failed. If the failures are for contracts over 24KB');
    console.log('  and the error is BlobTooLarge with no size/limit info, issue #11526 is reproduced.');
    console.log('  See the error dumps above for the exact (unhelpful) error messages returned.');
  } else if (allSuccess) {
    console.log('  All contracts deployed successfully. If the PVM limit truly is 100KB, this');
    console.log('  is the expected outcome — no BlobTooLarge should occur for <100KB contracts.');
  }
  console.log(LINE + '\n');
}

main().catch(err => {
  console.error('\nFatal error:', err);
  process.exit(1);
});
