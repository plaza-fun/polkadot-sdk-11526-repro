require('dotenv').config();
require('@nomicfoundation/hardhat-toolbox');
require('@parity/hardhat-polkadot');

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
      metadata: { bytecodeHash: 'none' },
    },
  },
  resolc: { compilerSource: 'npm' },
  networks: {
    hardhat: {},
    // PVM target: polkadot: true triggers resolc compilation
    // Note: "polkavm" was the field name in v0.1.x, renamed to "polkadot" in v0.2.x
    polkadotHubTestnet: {
      polkadot: true,
      url: process.env.EVM_RPC || 'https://services.polkadothub-rpc.com/testnet',
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
      chainId: 420420417,
    },
  },
};
