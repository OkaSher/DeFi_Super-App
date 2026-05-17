// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {GovToken} from "../../src/tokens/GovToken.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title ForkSepoliaTest - Live integration tests against Arbitrum Sepolia state
/// @notice Skipped automatically when ARBITRUM_SEPOLIA_RPC_URL is not configured
contract ForkSepoliaTest is Test {
    uint256 internal constant ARBITRUM_SEPOLIA_CHAIN_ID = 42_161_614;

    // Chainlink ETH/USD on Arbitrum Sepolia (docs.chain.link)
    address internal constant ETH_USD_FEED = 0xd30E2101A97dCB626D31F4F4Bc8130789b1D6976;
    address internal constant WETH = 0x980b62DA83eFF3d58d51A311148CDfb7C2fC0751;

    PriceOracle oracle;
    GovToken govToken;
    ProtocolTimelock timelock;
    ProtocolGovernor governor;

    address deployer = makeAddr("deployer");
    address proposer = makeAddr("proposer");
    address voter = makeAddr("voter");

    bool forkActive;

    function setUp() public {
        forkActive = _tryForkArbitrumSepolia();
        if (!forkActive) return;

        govToken = new GovToken(1_000_000 * 1e18);

        address[] memory noRoles = new address[](0);
        timelock = new ProtocolTimelock(2 days, noRoles, noRoles, deployer);

        governor = new ProtocolGovernor(
            govToken,
            timelock,
            7200,
            50_400,
            10_000 * 1e18
        );

        PriceOracle impl = new PriceOracle();
        bytes memory initData = abi.encodeCall(PriceOracle.initialize, (deployer));
        oracle = PriceOracle(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(deployer);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        oracle.setMaxStalenessThreshold(1 days);
        oracle.setPriceFeed(WETH, ETH_USD_FEED);
        vm.stopPrank();

        govToken.transfer(proposer, 50_000 * 1e18);
        govToken.transfer(voter, 200_000 * 1e18);

        vm.prank(proposer);
        govToken.delegate(proposer);
        vm.prank(voter);
        govToken.delegate(voter);

        vm.roll(block.number + 1);
    }

    function test_ForkSepoliaChainlinkEthUsdPrice() public {
        if (!forkActive) vm.skip(true);

        int256 price = oracle.getPriceWithStalenessCheck(WETH, 1 days);
        assertGt(price, 0, "ETH/USD price should be positive");

        (,,, uint256 updatedAt,) = oracle.getLatestPrice(WETH);
        assertGt(updatedAt, 0, "round timestamp should be set");

        console2.log("ETH/USD price (8 decimals):", price);
    }

    function test_ForkSepoliaGovernorExecutesViaTimelock() public {
        if (!forkActive) vm.skip(true);

        address[] memory targets = new address[](1);
        targets[0] = address(oracle);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(PriceOracle.setMaxStalenessThreshold, (7200));

        string memory description = "Update oracle staleness threshold to 2 hours";

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 7200 + 1);
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(voter);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 50_400 + 1);
        vm.warp(block.timestamp + 7 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + 2 days + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(oracle.maxStalenessThreshold(), 7200);
    }

    function _tryForkArbitrumSepolia() internal returns (bool) {
        string memory rpc = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return false;

        vm.createSelectFork(rpc);
        return block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID;
    }
}
