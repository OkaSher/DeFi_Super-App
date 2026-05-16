// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {GovToken} from "../src/tokens/GovToken.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {GovernanceBadge} from "../src/tokens/GovernanceBadge.sol";
import {AMMFactory} from "../src/core/AMMFactory.sol";
import {YieldVault} from "../src/tokens/YieldVault.sol";
import {PriceOracle} from "../src/oracles/PriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xabc123));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Core Governance Token
        GovToken govToken = new GovToken(1_000_000 * 1e18);

        // 2. Deploy ProtocolTimelock (2 days delay)
        address[] memory tempArray = new address[](0);
        ProtocolTimelock timelock = new ProtocolTimelock(2 days, tempArray, tempArray, deployer);

        // 3. Deploy ProtocolGovernor
        ProtocolGovernor governor = new ProtocolGovernor(
            IVotes(address(govToken)),
            timelock,
            7200,      // ~1 day delay
            50400,     // ~7 days period
            10_000 * 1e18 // 10k threshold
        );

        // 4. Deploy Badge ERC-721 and transfer ownership to the Timelock
        GovernanceBadge badge = new GovernanceBadge(address(governor), address(timelock));
        badge.transferOwnership(address(timelock));

        // 5. Deploy Core AMM Pool Factory
        new AMMFactory();

        // 6. Deploy YieldVault wrapping the GovToken
        YieldVault vault = new YieldVault(IERC20(address(govToken)), "Yield Vault", "yGOV");

        // 7. Deploy PriceOracle with UUPS proxy pattern
        {
            // Deploy implementation
            PriceOracle oracleImpl = new PriceOracle();

            // Deploy proxy with initialization
            bytes memory initData = abi.encodeCall(PriceOracle.initialize, (deployer));
            ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), initData);

            // Set maxStalenessThreshold through proxy
            PriceOracle oracle = PriceOracle(address(oracleProxy));
            oracle.setMaxStalenessThreshold(3600); // 1 hour default
        }

        // 7. Secure Roles (scoped block to avoid Stack Too Deep)
        // 8. Secure Roles (scoped block to avoid Stack Too Deep)
        {
            // Grant governor proposer and canceller privileges
            timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
            timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

            // Allow public execution of mature proposals
            timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

            // Revoke deployer admin privileges, locking down the Timelock
            timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        }

        vm.stopBroadcast();
    }
}
