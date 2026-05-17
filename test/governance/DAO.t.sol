// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovToken} from "../../src/tokens/GovToken.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract DAOTest is Test {
    GovToken public govToken;
    ProtocolTimelock public timelock;
    ProtocolGovernor public governor;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant PROPOSAL_THRESHOLD = 10_000 * 1e18;
    uint48 public constant VOTING_DELAY = 7200;
    uint32 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        govToken = new GovToken(INITIAL_SUPPLY);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new ProtocolTimelock(2 days, proposers, executors, address(this));

        governor = new ProtocolGovernor(
            IVotes(address(govToken)),
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD
        );

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, address(this));
    }

    function test_SuccessfulProposalFlow() public {
        govToken.delegate(address(this));
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(0x123);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory description = "Proposal #1: Send dummy tx";

        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.warp(block.timestamp + 7 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + 2 days + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }
}
