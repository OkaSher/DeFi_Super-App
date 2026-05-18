# DeFi Super-App: Multi-Chain Governance-Enabled Protocol

## 🎯 Project Overview

**DeFi Super-App** is a comprehensive decentralized finance protocol combining an automated market maker (AMM), time-locked DAO governance, yield-bearing vault, chainlink price oracle integration, and on-chain event indexing via The Graph. Built on **Arbitrum Sepolia (L2 testnet)** with a full React frontend, this project demonstrates enterprise-grade DeFi architecture with advanced testing methodologies and security best practices.

**Target Deployment**: Arbitrum Sepolia (Testnet)  
**Chain ID**: 421614  
**Stack**: Solidity → Foundry → React/Vite → The Graph

---

## ✨ Core Features

### 1. **Automated Market Maker (AMM)**
- **Model**: Constant-product pool (x·y ≥ k, Uniswap v2-style)
- **Features**:
  - Multi-hop swaps via factory routing
  - 0.3% transaction fees
  - Optimized storage (packed uint112 reserves)
  - K-invariant protection via Yul assembly
  - Slippage validation with minAmountOut

### 2. **Governance & DAO**
- **Framework**: OpenZeppelin Governor with modular voting
- **Configuration**:
  - Voting delay: 1 day (~7200 blocks)
  - Voting period: 7 days (~50,400 blocks)
  - Quorum: 4% of delegated votes
  - Proposal threshold: 10,000 GOV tokens
- **Execution**: 2-day timelock for security via ProtocolTimelock
- **Vote Delegation**: Self-delegatable voting power

### 3. **ERC4626 Yield Vault**
- Tokenized vault for yield aggregation
- 9-decimal inflation-attack protection
- Support for any ERC20 asset
- Standardized deposit/withdraw interface

### 4. **Chainlink Price Oracle**
- **Pattern**: UUPS upgradeable (ERC1967 proxy)
- **Features**:
  - Staleness validation (1-day default threshold)
  - Multi-feed support (token → Chainlink aggregator mapping)
  - Owner-configurable thresholds
  - Protected upgrade path

### 5. **ERC721 Governance Badge**
- NFT-based governance rewards
- Minting restricted to Governor/Timelock
- Commemorates on-chain governance participation

### 6. **The Graph Subgraph**
- Indexes proposals, votes, and swaps
- Real-time governance analytics
- Transparent transaction history
- GraphQL query interface

---

## 📁 Project Structure

```
.
├── src/
│   ├── core/
│   │   ├── AMM.sol               # Constant-product liquidity pool
│   │   └── AMMFactory.sol        # Pool deployment & routing
│   ├── governance/
│   │   ├── ProtocolGovernor.sol  # DAO voting & proposal execution
│   │   └── ProtocolTimelock.sol  # 2-day execution delay
│   ├── tokens/
│   │   ├── GovToken.sol          # ERC20 + Votes governance token
│   │   ├── YieldVault.sol        # ERC4626 tokenized vault
│   │   └── GovernanceBadge.sol   # ERC721 governance rewards
│   ├── oracles/
│   │   └── PriceOracle.sol       # Chainlink price feed integration
│   └── interfaces/
│       ├── IAMM.sol              # AMM interface
│       ├── IAMMFactory.sol        # Factory interface
│       ├── IOracle.sol           # Oracle interface
│       └── IVault.sol            # Vault interface
├── test/
│   ├── core/
│   │   ├── AMM.t.sol             # AMM unit tests
│   │   ├── AMMInvariant.t.sol    # K-invariant fuzzing
│   │   └── YieldVault.t.sol      # Vault unit tests
│   ├── governance/
│   │   └── DAO.t.sol             # Governance flow tests
│   ├── oracles/
│   │   └── PriceOracle.t.sol     # Oracle validation tests
│   ├── integration/
│   │   ├── Fork.t.sol            # Fork-based integration
│   │   └── ForkSepolia.t.sol     # Live testnet validation
│   └── mocks/
│       └── MockAggregatorV3.sol  # Chainlink price feed mock
├── script/
│   ├── Deploy.s.sol              # L2 deployment script
│   └── VerifyDeployment.s.sol    # Deployment validation
├── frontend/
│   ├── src/
│   │   ├── components/
│   │   │   ├── Swap.jsx          # Token swap UI
│   │   │   ├── AddLiquidity.jsx  # LP provision UI
│   │   │   ├── RemoveLiquidity.jsx # LP withdrawal UI
│   │   │   └── DAO.jsx           # Governance voting UI
│   │   ├── utils/
│   │   │   └── web3.js           # Ethers.js utilities
│   │   ├── App.jsx               # Main component
│   │   └── index.css             # Cyberpunk theme
│   ├── package.json
│   └── vite.config.js
├── subgraph/
│   ├── subgraph.yaml             # Subgraph configuration
│   ├── schema.graphql            # Entity schema (Proposal, Vote, PoolSwap, User)
│   └── src/
│       └── mapping.ts            # Event handlers
├── foundry.toml                  # Foundry configuration
├── package.json                  # NPM dependencies
└── slither.config.json           # Security analyzer config
```

---

## 🛠️ Setup & Installation

### Prerequisites
- **Node.js** ≥18.0
- **Foundry** (forge, cast) - [Install](https://getfoundry.sh)
- **Git**

### Installation

```bash
# Clone repository
git clone https://github.com/OkaSher/DeFi_Super-App.git
cd DeFi_Super-App

# Install Foundry dependencies
forge install

# Install frontend dependencies
cd frontend && npm install && cd ..

# Install subgraph tools (optional, requires Docker for local indexing)
cd subgraph && npm install && cd ..
```

---

## 🧪 Testing

### Run All Tests
```bash
forge test
```

### Run Specific Test Suite
```bash
# Unit tests only
forge test --match-path "test/core/*" -v

# Governance tests
forge test --match-path "test/governance/*" -v

# Invariant/fuzz tests (AMMInvariant)
forge test --match-contract AMMInvariant -v

# Fork-based integration (requires RPC URL)
export ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
forge test --match-path "test/integration/Fork.t.sol" -v
```

### Test Coverage

| Module | Test Type | Count | Coverage |
|--------|-----------|-------|----------|
| **AMM** | Unit | 8 | Swap, liquidity, reserves, fee math |
| **AMM** | Invariant | 1 | 500 iterations, K-preservation |
| **Governance** | Unit | 5 | Proposal lifecycle, delegation, timelock |
| **Vault** | Unit | 6 | Deposit/withdraw, inflation protection |
| **Oracle** | Unit | 6 | Staleness, feed updates, upgrades |
| **Integration** | Fork | 2 | Full cross-component deployment |
| **Total** | - | 28 | **~95% smart contract coverage** |

---

## 🚀 Deployment

### Deploy to Arbitrum Sepolia

1. **Create `.env` in project root:**
```bash
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
PRIVATE_KEY=<your_private_key>
ARBISCAN_API_KEY=<arbitrumscan_key>
```

2. **Load `.env` into current shell (optional):**
```bash
source .env
```

3. **Run deployment script:**
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

4. **Verify deployment:**
```bash
forge script script/VerifyDeployment.s.sol:VerifyDeployment --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

5. **Verify contracts on Arbiscan:**
```bash
forge verify-contract <CONTRACT_ADDRESS> src/core/AMM.sol:AMM \
  --chain-id 421614 \
  --etherscan-api-key $ARBISCAN_API_KEY
```

### Deployment Addresses (Example - Testnet)
```
GovToken:           0x[...]
ProtocolTimelock:   0x[...]
ProtocolGovernor:   0x[...]
GovernanceBadge:    0x[...]
AMMFactory:         0x[...]
YieldVault:         0x[...]
PriceOracle (Proxy): 0x[...]
PriceOracle (Impl):  0x[...]
```

---

## 🎨 Frontend Usage

### Start Development Server

```bash
cd frontend
npm run dev
```

Server runs on `http://localhost:5173` by default.

### Features

1. **Swap**: Exchange tokens via AMM pools
2. **Add Liquidity**: Provide LP with both tokens, earn 0.3% fees
3. **Remove Liquidity**: Withdraw LP shares and redeem tokens
4. **DAO**: Vote on governance proposals, delegate voting power

### Connected Wallet
- MetaMask required
- Supports Arbitrum Sepolia testnet
- Hardcoded addresses point to testnet deployments

---

## 📊 The Graph Subgraph

### Deploy Subgraph (Optional)

```bash
cd subgraph

# Authenticate with The Graph
graph auth <YOUR_DEPLOY_KEY>

# Build subgraph
graph build

# Deploy to testnet
graph deploy --node https://api.thegraph.com/deploy/ \
  <YOUR_GITHUB_USERNAME>/defisuperapp
```

### Query Examples

```graphql
# Get all proposals
query {
  proposals(first: 10) {
    id
    proposer
    description
    startBlock
    endBlock
    forVotes
    againstVotes
    abstainVotes
    state
  }
}

# Get user votes
query {
  votes(where: { voter: "0x..." }, first: 20) {
    id
    proposal { id }
    voter
    support  # 0=AGAINST, 1=FOR, 2=ABSTAIN
    weight
  }
}

# Get swap history
query {
  poolSwaps(first: 50, orderBy: timestamp, orderDirection: desc) {
    id
    swapper
    tokenIn
    tokenOut
    amountIn
    amountOut
    timestamp
    transactionHash
  }
}
```

---

## 🔒 Security Considerations

### Code Review & Audit
- **Internal security audit** performed using **Slither** static analyzer
- See `SECURITY_AUDIT.md` for detailed findings and mitigations
- **Key protections**:
  - K-invariant enforced via Yul assembly
  - Reentrancy guards on external calls
  - Integer overflow/underflow (Solidity 0.8.x built-in)
  - Staleness validation for price feeds
  - Inflation-attack protection (ERC4626 decimals offset)
  - Timelock on governance execution

### Best Practices Implemented
- ✅ OpenZeppelin battle-tested contracts
- ✅ UUPS proxy pattern for oracle upgrades
- ✅ Role-based access control (Governor, Timelock)
- ✅ Event emission for transparency
- ✅ Mock contracts for testing
- ✅ Comprehensive test suite (unit + fuzz + integration)

---

## 📈 Gas Optimization Report

See `GAS_OPTIMIZATION_REPORT.md` for detailed before/after benchmarks, optimization strategies, and cost analysis.

**Key Optimizations:**
- Packed storage (uint112 reserves in single slot)
- Efficient array iteration in factory
- Minimal storage writes in swap operations
- Optimized constructor initialization
- Strategic view function caching

---

## 📋 Architecture & Design

See `ARCHITECTURE.md` for comprehensive 6+ page design document covering:
- System architecture diagrams
- Contract interaction flows
- Data flow diagrams
- Governance decision trees
- Deployment topology
- Scalability considerations

---

## 🔧 Configuration Files

### foundry.toml
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
test = "test"
script = "script"
optimizer = true
optimizer_runs = 200
```

### slither.config.json
```json
{
  "detectors": ["all"],
  "exclude": ["pragma", "naming-convention"],
  "filter_paths": ["lib/"]
}
```

---

## 📚 Key References

- **Uniswap V2 AMM**: https://docs.uniswap.org/contracts/v2/
- **OpenZeppelin Governor**: https://docs.openzeppelin.com/contracts/4.x/governance
- **ERC4626 Vault**: https://eips.ethereum.org/EIPS/eip-4626
- **Chainlink Price Feeds**: https://docs.chain.link/data-feeds/
- **The Graph**: https://thegraph.com/docs/en/

---

## 👥 Team & Contributing

**Project Lead**: OkaSher & Contributors

**Contributing**: 
- Fork the repository
- Create a feature branch (`git checkout -b feature/your-feature`)
- Commit changes with clear messages
- Push to branch and open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** - see LICENSE file for details.

---

## 🎓 Presentation & Documentation

- **Final Presentation**: See `PRESENTATION_SLIDES.pdf` (10 slides)
- **Security Audit**: See `SECURITY_AUDIT.md` (8+ pages)
- **Architecture**: See `ARCHITECTURE.md` (6+ pages)
- **Gas Analysis**: See `GAS_OPTIMIZATION_REPORT.md`

---

## 📞 Support & Contact

For issues, questions, or collaboration:
- Open a GitHub Issue
- Contact: [Project contact/email]

---

**Last Updated**: May 18, 2026  
**Network**: Arbitrum Sepolia (421614)  
**Status**: Production-Ready (Testnet)
