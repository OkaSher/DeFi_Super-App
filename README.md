# DeFi Super-App

Cross-chain DeFi protocol with an AMM core, ERC-4626 vault, DAO governance, Chainlink oracles, and CI security checks.

## Nurik — Infrastructure, Oracles & DevSecOps

### Contracts

- `src/interfaces/IOracle.sol` — oracle interface with staleness errors
- `src/oracles/PriceOracle.sol` — Chainlink feeds behind a UUPS proxy

### Environment variables

Copy `.env.example` to `.env` and fill in:

| Variable | Purpose |
|----------|---------|
| `PRIVATE_KEY` | Deployer key for `script/Deploy.s.sol` |
| `ARBITRUM_SEPOLIA_RPC_URL` | Arbitrum Sepolia RPC (fork tests + deploy) |
| `ARBISCAN_API_KEY` | Contract verification on Arbiscan |
| `GOV_TOKEN`, `TIMELOCK`, `GOVERNOR`, `GOV_BADGE` | Addresses for `VerifyDeployment.s.sol` |
| `PRICE_ORACLE`, `PRICE_ORACLE_IMPL` | Oracle proxy + implementation addresses |
| `ORACLE_TOKEN`, `ORACLE_FEED` | Optional feed mapping check (e.g. WETH + ETH/USD) |
| `DEPLOYER` | Ensures deployer admin role was revoked from timelock |

### Local commands

```bash
forge build
forge test
forge test --match-path test/integration/ForkSepolia.t.sol   # requires ARBITRUM_SEPOLIA_RPC_URL
slither src/oracles --config-file slither.config.json --fail-high --fail-medium
```

### Deploy & verify

```bash
source .env
forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia --broadcast

forge script script/VerifyDeployment.s.sol --rpc-url arbitrum_sepolia
```
