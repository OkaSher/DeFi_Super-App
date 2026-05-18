ARCHITECTURE AND DESIGN DOCUMENT — DEFI SUPER-APP SYSTEM

This document outlines the system architecture, design decisions, sequence flows, data models, and trust assumptions for the DeFi Super-App (Option A). The protocol combines a constant-product Automated Market Maker (AMM), an ERC-4626 Yield-Bearing Vault, a UUPS Upgradeable Price Oracle, and an on-chain DAO Governance system governed by a Timelock Controller.

---

1. SYSTEM CONTEXT DIAGRAM

The DeFi Super-App consists of five main sub-systems working in tandem. Below is the topological context diagram:

```
                  ┌─────────────────────────────────────┐
                  │            USER / WALLET            │
                  └───────┬───────────────────────┬─────┘
                          │                       │
     Swaps & Liquidity    │                       │ Governance & Staking
                          ▼                       ▼
      ┌───────────────────────────────┐       ┌───────────────────────────────┐
      │          AMM ENGINE           │       │        DAO GOVERNANCE         │
      │    (AMMFactory / Pools)       │       │   (ProtocolGovernor / Permit) │
      └──────────────┬────────────────┘       └───────────────┬───────────────┘
                     │                                        │
                     │ Refers Underlying                      │ Triggers Executions
                     ▼                                        ▼
      ┌───────────────────────────────┐       ┌───────────────────────────────┐
      │        ERC-4626 VAULT         │◄──────┤       TIMELOCK CONTROL        │
      │   (YieldVault / yTokens)      │       │     (ProtocolTimelock)        │
      └───────────────────────────────┘       └───────────────────────────────┘
                     ▲                                        │
                     │ Reads Collateral Prices                │ Admin Controls
                     ▼                                        ▼
      ┌───────────────────────────────┐       ┌───────────────────────────────┐
      │       UPGRADEABLE ORACLE      │◄──────┘     GOVERNANCE REWARDS NFT    │
      │   (PriceOracle - UUPS)        │             (GovernanceBadge ERC721)  │
      └───────────────────────────────┘       └───────────────────────────────┘
```

---

2. COMPONENT ARCHITECTURE AND RELATIONSHIPS

2.1 Constant-Product AMM (AMMFactory and AMM)

* AMMFactory: Deploys pools deterministically using both standard CREATE (createPoolClassic) and salted CREATE2 (createPool) opcodes. It maintains a bilateral mapping getPool[tokenA][tokenB] ensuring a single unique pool per token pair.
* AMM Pool: A constant-product core exchange primitive (x * y = k). It incorporates inline Yul assembly for Babylonian square root (_sqrt) and gas-optimized K-invariant validation during swaps. It is fully guarded against reentrancy using ReentrancyGuard and incorporates SafeERC20 for all asset transfers.

2.2 Tokenized Yield Vault (YieldVault)

* YieldVault: A standard ERC-4626 yield-bearing contract wrapping the DAO's governance token (GovToken).
* decimals Offset: Implements a decimals offset of 9 (_decimalsOffset() => 9). This increases share scaling, which successfully mitigates the "inflation attack" (share donation attack) common in new vaults.

2.3 UUPS Upgradeable Price Oracle (PriceOracle)

* PriceOracle: A Universal Upgradeable Proxy Standard (UUPS) compliant oracle.
* Upgrade Mechanics: Upgrades are authorized via _authorizeUpgrade which is restricted strictly to the onlyOwner role.
* Price Feeds: Reads from @chainlink/contracts aggregator interfaces. It normalizes all asset prices to standard 18-decimal precision.
* Staleness Check: Reverts with StalePrice() if the price update timestamp exceeds stalenessThreshold (default: 3600 seconds), protecting the protocol from stale market feeds.

2.4 Governance Stack (GovToken, ProtocolGovernor, ProtocolTimelock, GovernanceBadge)

* GovToken: ERC-20 token with ERC20Votes checkpoint tracking and ERC20Permit signature-based delegation.
* ProtocolGovernor: Handles proposals, vote counting (using standard FOR, AGAINST, ABSTAIN options), and quorum checks (4% fraction).
* ProtocolTimelock: A 2-day minimum delay controller (TimelockController) acting as the ultimate owner of the system.
* GovernanceBadge: ERC-721 token minted as participation rewards to users. Minting rights are restricted to the Governor and Timelock.

---

3. CORE PROTOCOL SEQUENCE DIAGRAMS

3.1 Constant-Product Swap Sequence

This diagram details the swap lifecycle in the AMM pool contract, including reserves checks, inline assembly math, and K-invariant verification:

```
User               AMM Pool Contract               Token0 (In)            Token1 (Out)
 │                         │                            │                      │
 ├──── swap(amtIn) ───────►│                            │                      │
 │                         ├──── transferFrom ─────────►│                      │
 │                         │     (takes tokenIn)        │                      │
 │                         │                            │                      │
 │                         ├──── Transfer out ──────────┼─────────────────────►│
 │                         │     (sends tokenOut)       │                      │
 │                         │                            │                      │
 │                         ├──── inline Yul Check ──────┤                      │
 │                         │     (calculates K)         │                      │
 │                         │                            │                      │
 │                         │     [Assert K_new >= K_old]│                      │
 │                         │                            │                      │
 ◄──── Swap success ───────┤                            │                      │
```

3.2 Governance Proposal Lifecycle

The sequence below illustrates the process from proposal creation to multi-day timelock delay execution:

```
Proposer           ProtocolGovernor           ProtocolTimelock            Target Contract
   │                       │                          │                           │
   ├──── propose() ───────►│                          │                           │
   │     [Checks threshold]│                          │                           │
   │                       │                          │                           │
   │                       ├─ (Wait 1 day voting delay)                           │
   │                       │                          │                           │
   │                       ├─ (Users cast votes)      │                           │
   │                       │                          │                           │
   │                       ├─ (Assert 4% Quorum)      │                           │
   │                       │                          │                           │
   ├──── queue() ─────────►│                          │                           │
   │                       ├──── schedule proposal ──►│                           │
   │                       │     (Sets 2-day delay)   │                           │
   │                       │                          │                           │
   │                       │◄──── (Wait 2 days) ──────┤                           │
   │                       │                          │                           │
   ├──── execute() ───────►│                          │                           │
   │                       ├──── execute transaction ─►│                           │
   │                       │                          ├──── Execute payload ─────►│
   ◄──── Executed ─────────┴──────────────────────────┴───────────────────────────┘
```

---

4. UPGRADE MECHANISM AND STORAGE SAFETY

The UUPS upgradeable proxy pattern separates state (stored in the proxy contract) from execution logic (stored in the implementation contract). 

4.1 Storage Collision Prevention

To prevent storage collisions during upgrades from V1 to V2, we utilize two techniques:
1. Inheritance Tracking: Both PriceOracle and PriceOracleV2 inherit from the same base class sequence: Initializable -> UUPSUpgradeable -> OwnableUpgradeable.
2. Standard OZ Slots: OpenZeppelin's upgradeable contracts use namespaces and namespaced storage layouts to isolate base state variables (e.g. Initializable's initialization state is saved in specific reserved slots like 0xc5f16f0f... and Ownable's storage slot is resolved dynamically), avoiding variable collisions.

4.2 Storage Layout Structure

```
Proxy Contract State Slots:
---------------------------------------------------------------------------------
| Slot Address                | Variable Name             | Type                |
|-----------------------------|---------------------------|---------------------|
| 0x000000...0000             | priceFeeds (mapping)      | mapping(addr=>addr) |
| 0x000000...0001             | stalenessThreshold        | uint256             |
| ...                         | ...                       | ...                 |
| 0x360894a13ba1a3210667c828..| _IMPLEMENTATION_SLOT      | address (V1 -> V2)  |
---------------------------------------------------------------------------------
```

V2 introduces new functions (like version()) but must never insert or modify existing state variables at overlapping positions. New state variables must be added at the end of the storage layout or in a dedicated struct namespace.

---

5. TRUST ASSUMPTIONS AND SECURITY BOUNDARIES

1. Timelock Supremacy: The ProtocolTimelock is the ultimate root administrator of the protocol. It owns the AMMFactory, PriceOracle, YieldVault, and GovernanceBadge. There are NO admin backdoors. All updates (such as updating price feeds or altering delay terms) must transit through the full multi-day DAO proposal lifecycle.
2. Oracle Reliability: We assume Chainlink oracles provide highly accurate price feeds. If the oracle feed halts, transactions depending on price updates will fail (fail-safe revert on StalePrice()), rather than executing at malicious pricing.
3. Double initialization Protection: The initialization functions are strictly guarded by @openzeppelin/contracts-upgradeable's initializer modifiers, preventing unauthorized double-configuration.

---

6. ARCHITECTURAL DECISION RECORDS (ADRS)

ADR 01: Universal Upgradeable Proxy Standard (UUPS) for PriceOracle

* Status: Accepted
* Context: We need to easily update the price oracle's feed logic or staleness margins if Chainlink changes their interfaces on Arbitrum, without breaking user integrations or migrating states.
* Decision: Adopt the UUPS pattern instead of Transparent Proxy. UUPS is more gas efficient (as the upgrade logic resides in the implementation, saving deployment and per-call overhead) and provides solid upgrade checks.
* Consequences: The implementation contract must implement the _authorizeUpgrade method. If this is missed or configured incorrectly, the contract will be frozen. We mitigate this by restricting it strictly to the Timelock controller and writing extensive proxy test suites.

ADR 02: 9-Decimals Offset for YieldVault (ERC-4626)

* Status: Accepted
* Context: Standard ERC-4626 vaults are susceptible to inflation attacks where early depositors can donate huge underlying assets, inflating the share price and forcing rounding errors to steal subsequent depositors' funds.
* Decision: Implement a custom _decimalsOffset() returning 9.
* Consequences: Shares are minted scaled by 10^9, making share donation financially impractical (as the cost to steal fractions of cents is orders of magnitude greater). This guarantees vault security for early depositors.
