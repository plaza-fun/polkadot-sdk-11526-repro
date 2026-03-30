/**
 * Deploy PVM bytecode (resolc-compiled) to Polkadot Hub testnet
 * Must compile with: npx hardhat compile --network polkadotHubTestnet --force
 * (requires polkadot: true in network config)
 */
require('dotenv').config();
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

const RPC_URL = process.env.EVM_RPC || 'https://services.polkadothub-rpc.com/testnet';
const PRIV_KEY = process.env.DEPLOYER_PRIVATE_KEY;

function loadArtifact(name) {
  const p = path.join(__dirname, '..', 'artifacts', 'contracts', `${name}.sol`, `${name}.json`);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

async function deploy(provider, wallet, name) {
  const art = loadArtifact(name);
  const bytecode = art.bytecode;
  const deployed = (art.deployedBytecode.length - 2) / 2;
  const prefix = art.deployedBytecode.slice(0, 10);
  const isPvm = prefix === '0x50564d00';

  console.log(`\n=== ${name} ===`);
  console.log(`  Bytecode: ${deployed} bytes (${(deployed/1024).toFixed(1)} KB)`);
  console.log(`  Type: ${isPvm ? 'PVM (0x50564d00)' : 'EVM (0x608060xx)'}`);
  console.log(`  EVM 24KB: ${deployed <= 24576 ? 'within' : 'OVER (' + ((deployed/24576*100).toFixed(0)) + '%)'}`);
  console.log(`  PVM 1MB: within (${(deployed/1048576*100).toFixed(1)}%)`);

  try {
    const factory = new ethers.ContractFactory(art.abi, bytecode, wallet);
    const tx = await factory.getDeployTransaction();
    const gasEstimate = await provider.estimateGas({ ...tx, from: wallet.address }).catch(() => null);
    console.log(`  Gas estimate: ${gasEstimate || 'failed'}`);

    const contract = await factory.deploy({
      gasPrice: 20000000000000n,
      type: 0,
      gasLimit: gasEstimate ? gasEstimate * 150n / 100n : 10000000n,
    });
    const receipt = await contract.deploymentTransaction().wait();
    console.log(`  ✅ Deployed at: ${await contract.getAddress()}`);
    console.log(`  Gas used: ${receipt.gasUsed}`);

    // Verify on-chain code type
    const onchainCode = await provider.getCode(await contract.getAddress());
    const onchainSize = (onchainCode.length - 2) / 2;
    const onchainPrefix = onchainCode.slice(0, 10);
    console.log(`  On-chain: ${onchainSize} bytes, prefix: ${onchainPrefix}`);

    return { success: true, address: await contract.getAddress(), size: onchainSize };
  } catch (err) {
    const msg = err.message || '';
    if (msg.includes('BlobTooLarge')) {
      console.log(`  ❌ BlobTooLarge — PVM bytecode rejected at ${deployed} bytes`);
    } else if (msg.includes('CodeRejected')) {
      console.log(`  ❌ CodeRejected — chain rejected the PVM blob`);
    } else {
      console.log(`  ❌ Failed: ${msg.slice(0, 150)}`);
    }
    return { success: false, error: msg.slice(0, 100) };
  }
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIV_KEY, provider);
  const balance = await provider.getBalance(wallet.address);

  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║  PVM Bytecode Deployment Test (#11526)            ║');
  console.log('╚══════════════════════════════════════════════════╝');
  console.log(`Deployer: ${wallet.address}`);
  console.log(`Balance: ${ethers.formatEther(balance)} DOT`);
  console.log(`RPC: ${RPC_URL}`);

  const results = {};
  for (const name of ['SmallContract', 'MediumContract', 'LargeContract']) {
    results[name] = await deploy(provider, wallet, name);
  }

  console.log('\n═══════════════════════════════════════════════════');
  console.log('  Results');
  console.log('═══════════════════════════════════════════════════');
  for (const [name, r] of Object.entries(results)) {
    console.log(`  ${name.padEnd(20)} ${r.success ? '✅ ' + r.address : '❌ ' + r.error}`);
  }
}

main().catch(console.error);
