// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {GovToken} from "../src/tokens/GovToken.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {GovernanceBadge} from "../src/tokens/GovernanceBadge.sol";
import {PriceOracle} from "../src/oracles/PriceOracle.sol";

/// @title VerifyDeploymentScript
/// @notice Post-deployment checks for governance, timelock, and oracle integrity
contract VerifyDeploymentScript is Script {
    error StateVerificationFailed(string reason);

    bytes32 internal constant IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    function run() external view {
        console2.log("=== Initiating Post-Deployment Security Audit & Verification ===");

        address govTokenAddr = vm.envOr("GOV_TOKEN", address(0));
        address timelockAddr = vm.envOr("TIMELOCK", address(0));
        address governorAddr = vm.envOr("GOVERNOR", address(0));
        address badgeAddr = vm.envOr("GOV_BADGE", address(0));
        address priceOracleAddr = vm.envOr("PRICE_ORACLE", address(0));
        address priceOracleImplAddr = vm.envOr("PRICE_ORACLE_IMPL", address(0));
        address oracleToken = vm.envOr("ORACLE_TOKEN", address(0));
        address oracleFeed = vm.envOr("ORACLE_FEED", address(0));
        address deployerAddr = vm.envOr("DEPLOYER", address(0));

        if (
            govTokenAddr == address(0) || timelockAddr == address(0) || governorAddr == address(0)
                || badgeAddr == address(0)
        ) {
            console2.log("[!] WARNING: Core contract env vars not set. Skipping verification.");
            return;
        }

        GovToken govToken = GovToken(payable(govTokenAddr));
        ProtocolTimelock timelock = ProtocolTimelock(payable(timelockAddr));
        ProtocolGovernor governor = ProtocolGovernor(payable(governorAddr));
        GovernanceBadge badge = GovernanceBadge(badgeAddr);

        console2.log("[+] Verifying Governor configuration...");
        if (address(governor.token()) != address(govToken)) {
            revert StateVerificationFailed("Governor has incorrect voting token reference");
        }
        if (address(governor.timelock()) != address(timelock)) {
            revert StateVerificationFailed("Governor has incorrect timelock reference");
        }

        console2.log("[+] Verifying Timelock maturation delay...");
        if (timelock.getMinDelay() != 2 days) {
            revert StateVerificationFailed("Timelock delay is not set to exactly 2 days");
        }

        console2.log("[+] Verifying GovernanceBadge access control...");
        if (badge.owner() != address(timelock)) {
            revert StateVerificationFailed("GovernanceBadge owner is not the Timelock controller");
        }
        if (badge.governor() != address(governor)) {
            revert StateVerificationFailed("GovernanceBadge governor reference mismatch");
        }
        if (badge.timelock() != address(timelock)) {
            revert StateVerificationFailed("GovernanceBadge timelock reference mismatch");
        }

        console2.log("[+] Checking Governor roles in the Timelock...");
        if (!timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor))) {
            revert StateVerificationFailed("Governor does not have Proposer role in Timelock");
        }
        if (!timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor))) {
            revert StateVerificationFailed("Governor does not have Canceller role in Timelock");
        }

        console2.log("[+] Auditing admin backdoors...");
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        if (deployerAddr != address(0)) {
            if (timelock.hasRole(adminRole, deployerAddr)) {
                revert StateVerificationFailed("SECURITY BREACH: Deployer still holds Timelock admin role");
            }
        }

        if (timelock.getRoleAdmin(adminRole) != adminRole) {
            revert StateVerificationFailed("Timelock admin role management is not self-contained");
        }

        if (priceOracleAddr != address(0)) {
            _verifyOracle(priceOracleAddr, priceOracleImplAddr, oracleToken, oracleFeed);
        } else {
            console2.log("[!] PRICE_ORACLE not set. Skipping oracle verification.");
        }

        console2.log("=== SECURE DEPLOYMENT VERIFIED SUCCESSFULLY ===");
    }

    function _verifyOracle(
        address proxy,
        address expectedImpl,
        address token,
        address feed
    ) internal view {
        console2.log("[+] Verifying PriceOracle proxy and configuration...");
        PriceOracle oracle = PriceOracle(proxy);

        if (oracle.owner() == address(0)) {
            revert StateVerificationFailed("PriceOracle has no owner - not initialized");
        }

        if (oracle.maxStalenessThreshold() == 0) {
            revert StateVerificationFailed("PriceOracle staleness threshold not set");
        }

        address impl = address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
        if (impl == address(0)) {
            revert StateVerificationFailed("PriceOracle proxy has no implementation");
        }

        if (expectedImpl != address(0) && impl != expectedImpl) {
            revert StateVerificationFailed("PriceOracle implementation mismatch");
        }

        if (token != address(0) && feed != address(0)) {
            if (oracle.priceFeeds(token) != feed) {
                revert StateVerificationFailed("PriceOracle feed mapping mismatch");
            }

            (, int256 price,,,) = oracle.getLatestPrice(token);
            if (price <= 0) {
                revert StateVerificationFailed("PriceOracle returned non-positive price");
            }
        }

        console2.log("    - Proxy implementation:", impl);
        console2.log("    - Staleness threshold:", oracle.maxStalenessThreshold());
        console2.log("    - PriceOracle checks: OK");
    }
}
