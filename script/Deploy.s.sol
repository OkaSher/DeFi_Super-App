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

        GovToken govToken = new GovToken(1_000_000 * 1e18);

        address[] memory tempArray = new address[](0);
        ProtocolTimelock timelock = new ProtocolTimelock(2 days, tempArray, tempArray, deployer);

        ProtocolGovernor governor = new ProtocolGovernor(
            IVotes(address(govToken)),
            timelock,
            7200,
            50_400,
            10_000 * 1e18
        );

        GovernanceBadge badge = new GovernanceBadge(address(governor), address(timelock));
        badge.transferOwnership(address(timelock));

        AMMFactory factory = new AMMFactory();

        YieldVault vault = new YieldVault(IERC20(address(govToken)), "Yield Vault", "yGOV");

        PriceOracle oracleImpl = new PriceOracle();
        bytes memory initData = abi.encodeCall(PriceOracle.initialize, (deployer));
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), initData);
        PriceOracle oracle = PriceOracle(address(oracleProxy));
        oracle.setMaxStalenessThreshold(3600);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        console2.log("=== Deployment complete (Arbitrum Sepolia target) ===");
        console2.log("GOV_TOKEN:", address(govToken));
        console2.log("TIMELOCK:", address(timelock));
        console2.log("GOVERNOR:", address(governor));
        console2.log("GOV_BADGE:", address(badge));
        console2.log("AMM_FACTORY:", address(factory));
        console2.log("YIELD_VAULT:", address(vault));
        console2.log("PRICE_ORACLE:", address(oracle));
        console2.log("PRICE_ORACLE_IMPL:", address(oracleImpl));
        console2.log("DEPLOYER:", deployer);
    }
}
