const fs = require('fs');
const path = require('path');

const EVM_LIMIT  = 24 * 1024;       // 24 576 bytes — EIP-170
const PVM_LIMIT  = 100 * 1024;      // 102 400 bytes — PolkaVM (Parity claim)

const artifactsDir = path.join(__dirname, '..', 'artifacts', 'contracts');

// ── Helpers ─────────────────────────────────────────────────────────────────

function hexByteLen(hex) {
  if (!hex || hex === '0x') return 0;
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  return Math.floor(clean.length / 2);
}

function kb(bytes) {
  return (bytes / 1024).toFixed(2) + ' KB';
}

function statusEvm(bytes) {
  return bytes > EVM_LIMIT ? 'EXCEEDS EVM 24KB' : 'within EVM limit';
}

function statusPvm(bytes) {
  return bytes > PVM_LIMIT ? 'EXCEEDS PVM 100KB' : 'within PVM limit';
}

function bar(bytes, limit, width = 40) {
  const fill = Math.min(Math.round((bytes / limit) * width), width);
  const over = bytes > limit;
  const filled = (over ? '!' : '=').repeat(fill);
  const empty  = ' '.repeat(Math.max(0, width - fill));
  return `[${filled}${empty}]`;
}

// ── Discovery ───────────────────────────────────────────────────────────────

function findArtifacts(dir, results = []) {
  if (!fs.existsSync(dir)) return results;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      findArtifacts(full, results);
    } else if (entry.name.endsWith('.json') && !entry.name.endsWith('.dbg.json')) {
      results.push(full);
    }
  }
  return results;
}

// ── Main ────────────────────────────────────────────────────────────────────

const artifactFiles = findArtifacts(artifactsDir);

if (artifactFiles.length === 0) {
  console.error('\nNo artifacts found. Run `npx hardhat compile` first.\n');
  process.exit(1);
}

const contracts = [];

for (const file of artifactFiles) {
  let artifact;
  try {
    artifact = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    continue;
  }
  if (!artifact.contractName || !artifact.deployedBytecode) continue;
  // Skip interface/abstract artifacts with no bytecode
  if (artifact.deployedBytecode === '0x' || artifact.deployedBytecode === '') continue;

  const deployedBytes  = hexByteLen(artifact.deployedBytecode);
  const creationBytes  = hexByteLen(artifact.bytecode);

  contracts.push({
    name: artifact.contractName,
    deployedBytes,
    creationBytes,
  });
}

if (contracts.length === 0) {
  console.error('\nNo compiled contracts with bytecode found. Run `npx hardhat compile` first.\n');
  process.exit(1);
}

// Sort by deployed size descending
contracts.sort((a, b) => b.deployedBytes - a.deployedBytes);

// ── Print table ─────────────────────────────────────────────────────────────

const LINE = '─'.repeat(90);

console.log('\n' + LINE);
console.log(' Contract Bytecode Size Report');
console.log(LINE);
console.log(
  ' Contract'.padEnd(30) +
  'Deployed'.padStart(12) +
  'Creation'.padStart(12) +
  '  EVM (24KB)'.padEnd(20) +
  'PVM (100KB)'
);
console.log(LINE);

for (const c of contracts) {
  const evmLabel  = c.deployedBytes > EVM_LIMIT  ? '  OVER' : '  ok';
  const pvmLabel  = c.deployedBytes > PVM_LIMIT  ? '  OVER' : '  ok';
  console.log(
    (' ' + c.name).padEnd(30) +
    kb(c.deployedBytes).padStart(12) +
    kb(c.creationBytes).padStart(12) +
    (evmLabel + '  ' + bar(c.deployedBytes, EVM_LIMIT, 12)).padEnd(20) +
    pvmLabel + '  ' + bar(c.deployedBytes, PVM_LIMIT, 20)
  );
}

console.log(LINE);

// ── Detailed per-contract breakdown ─────────────────────────────────────────

console.log('\n── Detailed Analysis ──────────────────────────────────────────────────────────\n');

for (const c of contracts) {
  const evmPct = ((c.deployedBytes / EVM_LIMIT) * 100).toFixed(1);
  const pvmPct = ((c.deployedBytes / PVM_LIMIT) * 100).toFixed(1);

  console.log(`  ${c.name}`);
  console.log(`    Deployed bytecode : ${c.deployedBytes.toLocaleString()} bytes  (${kb(c.deployedBytes)})`);
  console.log(`    Creation bytecode : ${c.creationBytes.toLocaleString()} bytes  (${kb(c.creationBytes)})`);
  console.log(`    EVM  limit (24KB) : ${evmPct}% used  — ${statusEvm(c.deployedBytes)}`);
  console.log(`    PVM  limit (100KB): ${pvmPct}% used  — ${statusPvm(c.deployedBytes)}`);
  if (c.deployedBytes > EVM_LIMIT && c.deployedBytes <= PVM_LIMIT) {
    console.log(`    *** This contract SHOULD deploy on PVM but CANNOT deploy on EVM ***`);
    console.log(`        If Passet Hub rejects it with BlobTooLarge, that is issue #11526.`);
  }
  console.log();
}

// ── Summary ─────────────────────────────────────────────────────────────────

const overEvm = contracts.filter(c => c.deployedBytes > EVM_LIMIT);
const overPvm = contracts.filter(c => c.deployedBytes > PVM_LIMIT);

console.log(LINE);
console.log(` Summary`);
console.log(LINE);
console.log(` Total contracts analysed : ${contracts.length}`);
console.log(` Over EVM 24KB limit      : ${overEvm.length}  (${overEvm.map(c => c.name).join(', ') || 'none'})`);
console.log(` Over PVM 100KB limit     : ${overPvm.length}  (${overPvm.map(c => c.name).join(', ') || 'none'})`);
console.log();

if (overEvm.length > 0 && overPvm.length === 0) {
  console.log(' EXPECTED OUTCOME:');
  console.log('   - Contracts over 24KB should fail on standard EVM (EIP-170).');
  console.log('   - All contracts are under the 100KB PVM limit, so they SHOULD deploy on Passet Hub.');
  console.log('   - If Passet Hub returns BlobTooLarge for these contracts, it confirms issue #11526:');
  console.log('     the EVM 24KB limit is being incorrectly enforced on PVM deployments,');
  console.log('     and/or the error message lacks actionable size information.');
}
console.log(LINE + '\n');
