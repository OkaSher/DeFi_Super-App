DEFI SUPER-APP PROTOCOL — TEAM CAPSTONE PROJECT

Welcome to the DeFi Super-App (Option A) Team Capstone repository, the culminating project of the Blockchain Technologies 2 course. This repository contains a production-grade, audited, and gas-optimized decentralized financial suite deployed on an L2-ready architecture.

---

1. PROJECT OVERVIEW

The DeFi Super-App integrates several core decentralized financial primitives into a single secure ecosystem:
1. Constant-Product AMM (AMMFactory and AMM): Custom constant-product pool (x * y = k) supporting salted predictive CREATE2 and standard CREATE deployments, custom slippage calculations, and gas-efficient pool operations.
2. ERC-4626 Yield-Staking Vault (YieldVault): Yield-bearing wrapper for the governance token (GovToken) incorporating a custom 9-decimals offset to shield early depositors from vault inflation/donation attacks.
3. UUPS Upgradeable Price Oracle (PriceOracle): Adapter reading from Chainlink decentralization feeds, normalizing results to 18-decimal precision, and executing strict staleness reviews (stalenessThreshold = 1 hour).
4. DAO Governance Stack (ProtocolGovernor and ProtocolTimelock and GovernanceBadge): On-chain voting and execution protocol with a 2-day maturation delay on proposal execution and ERC-721 badge rewards for participating addresses.

---

2. DIRECTORY STRUCTURE AND KEY FILES

```
DeFi_Super-App/
├── src/                          # Smart Contract Source Files
│   ├── core/                     # Swap Pool Primitives
│   │   ├── AMM.sol               # Constant-Product Exchange Pool
│   │   └── AMMFactory.sol        # Classic & CREATE2 Factory Registrar
│   ├── governance/               # DAO Stack
│   │   ├── ProtocolGovernor.sol  # OpenZeppelin Governor v5 Adapter
│   │   └── ProtocolTimelock.sol  # Multi-Day Maturation delay Controller
│   ├── oracles/                  # Price Adapter Primitives
│   │   ├── PriceOracle.sol       # UUPS V1 upgradeable adapter
│   │   └── PriceOracleV2.sol     # V2 upgrade implementation target
│   ├── security/                 # Case Study Vulnerabilities
│   │   ├── VulnerableBank.sol    # Exploit target (Reentrancy / Access Control)
│   │   └── SecureBank.sol        # Mitigated target (Checks-Effects-Interactions)
│   └── tokens/                   # Protocol Assets
│       ├── GovToken.sol          # ERC20Votes Governance Token
│       ├── GovernanceBadge.sol   # ERC-721 Participation Reward
│       └── YieldVault.sol        # ERC-4626 decimals-offset Yield Vault
├── test/                         # Foundry Automated Test Suites
│   ├── core/                     # Swap and Vault Unit & Invariant Fuzzing
│   ├── governance/               # DAO lifecycle and consensus verification
│   ├── integration/              # Live Ethereum mainnet fork testing
│   ├── security/                 # Vulnerability studies exploit tests
│   └── tokens/                   # ERC-721 participation badge unit tests
├── script/                       # Deployment and Auditing Scripts
│   ├── Deploy.s.sol              # Standard local/live setup script
│   ├── VerifyDeployment.s.sol    # Programmatic post-deployment audit script
│   └── deployment_verification.txt# Terminal verification success transcript
├── frontend/                     # React Cyberpunk CRT Web Interface
│   ├── src/
│   │   ├── components/           # Swap, Liquidity, Vault, and DAO React views
│   │   ├── utils/                # Ethers.js and web3 contract linkages
│   │   └── App.jsx               # Dashboard Hub & Navigation Tabs
│   └── package.json              # UI Node.js dependencies configuration
├── architecture_document.md      # Detailed system context and sequence ADRs
├── security_audit_report.md      # Professional smart contract audit report
├── gas_report.md                 # Yul Sqrt vs Solidity benchmarks and slot layouts
└── coverage_report.md            # Line-by-line coverage metrics summary
```

---

3. QUICKSTART AND LOCAL INSTALLATION

Prerequisites
* Install Foundry (includes forge, cast, anvil):

  curl -L https://foundry.paradigm.xyz | bash
  foundryup

* Install Node.js (v18+ recommended) and npm.

Step 1 - Repository Setup and Dependencies Compilation
Clone the repository, enter the workspace, and pull Node.js dependencies:

npm install
forge install

Step 2 - Compile the Smart Contracts
Verify that all source contracts compile without warnings:

forge build

---

4. RUNNING THE TEST SUITES

The codebase contains a massive 123 tests cover set, running unit, fuzzy, state invariants, vulnerability exploit, proxy upgrades, and mainnet fork checks.

* Execute the entire Test Suite:

  forge test

* Execute Invariant State Fuzzing only:

  forge test --match-contract AMMInvariantTest

* Execute Live Fork Integration checks (requires internet connectivity to query mainnet state):

  forge test --match-contract ForkTest

---

5. GAS OPTIMIZATION BENCHMARKS

To view our inline Yul assembly gas benchmarks comparing the Yul Babylonian square root method against pure-Solidity math:

forge test --match-test testGas_Yul_vs_Solidity_Sqrt -vv

Benchmark Summary
* Solidity Pure Sqrt: 11,497 gas per call.
* Yul Inline Assembly Sqrt: 3,461 gas per call.
* Gas Saved: 8,036 gas per call (~70% savings)!

---

6. RUNNING VULNERABILITY EXPLOIT CASE STUDIES

To verify our reentrancy and access control before/after exploits:

forge test --match-contract VulnerabilityStudiesTest -vv

* testVulnerability_ReentrancyExploitVulnerableBank: Demonstrates the successful drain of 11 ETH from the vulnerable contract using a recursive contract callback.
* testMitigation_ReentrancyRevertsSecureBank: Demonstrates that the secure bank, using Checks-Effects-Interactions and ReentrancyGuard, successfully blocks the attack.

---

7. LAUNCHING THE FRONTEND CYBERPUNK WEB APP

The DeFi Super-App features a premium cyberpunk CRT dashboard letting users swap, manage pool liquidity, stake in the yield vault, self-delegate voting power, and cast governance ballots.

Step 1 - Boot up a local node (Anvil)

anvil

Step 2 - Deploy contracts locally to Anvil

forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

Step 3 - Launch the React Web Portal

Open a new shell window:

cd frontend
npm install
npm run dev

Open http://localhost:5173 in your browser. Configure MetaMask or another Web3 browser extension to point to Localhost network (RPC: http://127.0.0.1:8545, Chain ID: 31337).