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
    // Custom error definitions matching OpenZeppelin v5 Governor and Timelock Controller
    error GovernorInvalidProposalLength(uint256 targets, uint256 calldatas, uint256 values);
    error GovernorAlreadyCastVote(address voter);
    error GovernorOnlyExecutor(address account);
    error GovernorNonexistentProposal(uint256 proposalId);
    error GovernorUnexpectedProposalState(uint256 proposalId, IGovernor.ProposalState current, bytes32 expectedStates);
    error GovernorInsufficientProposerVotes(address proposer, uint256 votes, uint256 threshold);
    error GovernorInvalidVoteType();
    error GovernorAlreadyQueuedProposal(uint256 proposalId);
    error GovernorUnableToCancel(uint256 proposalId, address account);

    error TimelockInvalidOperationLength(uint256 targets, uint256 payloads, uint256 values);
    error TimelockInsufficientDelay(uint256 delay, uint256 minDelay);
    error TimelockUnexpectedOperationState(bytes32 operationId, bytes32 expectedStates);
    error TimelockUnexecutedPredecessor(bytes32 predecessorId);
    error TimelockUnauthorizedCaller(address caller);

    GovToken public govToken;
    ProtocolTimelock public timelock;
    ProtocolGovernor public governor;

    address public proposerUser = makeAddr("proposerUser");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");
    address public stranger = makeAddr("stranger");

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant PROPOSAL_THRESHOLD = 10_000 * 1e18;
    uint48 public constant VOTING_DELAY = 7200;
    uint32 public constant VOTING_PERIOD = 50400;
    uint256 public constant MIN_DELAY = 2 days;

    function setUp() public {
        govToken = new GovToken(INITIAL_SUPPLY);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new ProtocolTimelock(MIN_DELAY, proposers, executors, address(this));

        governor =
            new ProtocolGovernor(IVotes(address(govToken)), timelock, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, address(this));

        // Set up token distribution for testing roles
        // Proposer gets 50,000 tokens (above threshold)
        govToken.transfer(proposerUser, 50_000 * 1e18);
        // Voters get voting power
        govToken.transfer(voter1, 200_000 * 1e18);
        govToken.transfer(voter2, 200_000 * 1e18);

        // Delegate voting power (needed for snapshots)
        vm.prank(proposerUser);
        govToken.delegate(proposerUser);

        vm.prank(voter1);
        govToken.delegate(voter1);

        vm.prank(voter2);
        govToken.delegate(voter2);

        vm.roll(block.number + 1);
    }

    /* ==================== EXISTING TESTS ==================== */

    function test_SuccessfulProposalFlow() public {
        // Transfer all remaining admin tokens to proposerUser for delegation testing
        vm.prank(proposerUser);
        govToken.delegate(proposerUser);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(0x123);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory description = "Proposal #1: Send dummy tx";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

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

    /* ==================== EXPANDED UNIT TESTS ==================== */

    function test_Initialization() public view {
        assertEq(governor.name(), "ProtocolGovernor");
        assertEq(address(governor.token()), address(govToken));
        assertEq(address(governor.timelock()), address(timelock));
    }

    function test_VotingDelay() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
    }

    function test_VotingPeriod() public view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_ProposalThreshold() public view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function test_Quorum() public view {
        // Quorum fraction is 4%. Initial supply is 1_000_000 * 1e18. Quorum = 40,000 * 1e18.
        assertEq(governor.quorum(block.number - 1), 40_000 * 1e18);
    }

    function test_SupportsInterface() public view {
        // Standard ERC165 checks for governor interface
        assertTrue(governor.supportsInterface(type(IGovernor).interfaceId));
    }

    function test_ProposeBelowThresholdReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        // stranger has 0 voting power
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(GovernorInsufficientProposerVotes.selector, stranger, 0, PROPOSAL_THRESHOLD)
        );
        governor.propose(targets, values, calldatas, "Below threshold proposal");
    }

    function test_ProposeMismatchedLengthsReverts() public {
        address[] memory targets = new address[](2);
        targets[0] = address(0x123);
        targets[1] = address(0x456);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        vm.expectRevert(abi.encodeWithSelector(GovernorInvalidProposalLength.selector, 2, 1, 1));
        governor.propose(targets, values, calldatas, "Mismatched lengths");
    }

    function test_StateNonExistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(GovernorNonexistentProposal.selector, 999999));
        governor.state(999999);
    }

    function test_RevertVoteBeforeDelay() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Vote before delay");

        // Proposal state is Pending (0)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Pending,
                bytes32(1 << uint8(IGovernor.ProposalState.Active))
            )
        );
        governor.castVote(proposalId, 1); // For
    }

    function test_RevertVoteNonExistentProposal() public {
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(GovernorNonexistentProposal.selector, 999999));
        governor.castVote(999999, 1);
    }

    function test_RevertDoubleVoting() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Double voting test");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        // Vote again should revert
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(GovernorAlreadyCastVote.selector, voter1));
        governor.castVote(proposalId, 1);
    }

    function test_CastVoteFor() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Vote FOR test");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        uint256 weight = governor.castVote(proposalId, 1); // For
        assertEq(weight, 200_000 * 1e18);
    }

    function test_CastVoteAgainst() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Vote AGAINST test");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        uint256 weight = governor.castVote(proposalId, 0); // Against
        assertEq(weight, 200_000 * 1e18);
    }

    function test_CastVoteAbstain() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Vote ABSTAIN test");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        uint256 weight = governor.castVote(proposalId, 2); // Abstain
        assertEq(weight, 200_000 * 1e18);
    }

    function test_CastVoteInvalidVoteTypeReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Invalid type test");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(GovernorInvalidVoteType.selector));
        governor.castVote(proposalId, 3); // 3 is not active in standard vote (only For=1, Against=0, Abstain=2)
    }

    function test_ProposalDefeated() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Defeated Proposal");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 0); // Voter1 votes AGAINST

        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_QueueDefeatedReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Defeated Proposal 2");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 0); // AGAINST

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(bytes("Defeated Proposal 2"));

        vm.expectRevert(
            abi.encodeWithSelector(
                GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Defeated,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        governor.queue(targets, values, calldatas, descriptionHash);
    }

    function test_QueueAlreadyQueuedReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory desc = "Queue twice test";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // FOR

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Queueing again should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Queued,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        governor.queue(targets, values, calldatas, descriptionHash);
    }

    function test_RevertExecuteBeforeTimelockMatures() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory desc = "Early execution test";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // FOR

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Executing before timelock matures should revert in timelock controller
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function test_ExecuteAlreadyExecutedReverts() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory desc = "Execute twice test";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // FOR

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        // Executing again should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Executed,
                bytes32(1 << uint8(IGovernor.ProposalState.Queued))
            )
        );
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function test_ProposerCanCancel() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory desc = "Cancellable proposal";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        // Cancel it when Pending
        bytes32 descriptionHash = keccak256(bytes(desc));

        vm.prank(proposerUser);
        governor.cancel(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_RevertCancelNonProposer() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory desc = "Non-proposer cancel test";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        bytes32 descriptionHash = keccak256(bytes(desc));

        // Stranger tries to cancel proposal
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(GovernorUnableToCancel.selector, proposalId, stranger));
        governor.cancel(targets, values, calldatas, descriptionHash);
    }

    function test_RevertCancelExecutedProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory desc = "Executed cancel test";

        vm.prank(proposerUser);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        // Cancel should revert since it's already executed
        vm.prank(proposerUser);
        vm.expectRevert(abi.encodeWithSelector(GovernorUnableToCancel.selector, proposalId, proposerUser));
        governor.cancel(targets, values, calldatas, descriptionHash);
    }

    function test_TimelockViews() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
    }

    function test_TimelockRevertUpdateDelayUnauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TimelockUnauthorizedCaller.selector, stranger));
        timelock.updateDelay(1 days);
    }

    /* ==================== EXPANDED FUZZ TESTS ==================== */

    function testFuzz_VotingPowerDelegation(uint256 amount) public {
        // Bound deposit amount to a reasonable token supply fraction
        amount = bound(amount, 1, 100_000 * 1e18);

        address fuzzedUser = makeAddr("fuzzedUser");
        govToken.transfer(fuzzedUser, amount);

        vm.startPrank(fuzzedUser);
        govToken.delegate(fuzzedUser);
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Snapshot details
        uint256 votes = govToken.getVotes(fuzzedUser);
        assertEq(votes, amount);
    }

    function testFuzz_ProposalThresholdChecks(uint256 amount) public {
        // Check proposal threshold boundaries with fuzzed amounts
        amount = bound(amount, 0, 200_000 * 1e18);

        address thresholdTester = makeAddr("thresholdTester");
        govToken.transfer(thresholdTester, amount);

        vm.prank(thresholdTester);
        govToken.delegate(thresholdTester);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(0x123);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        if (amount < PROPOSAL_THRESHOLD) {
            vm.prank(thresholdTester);
            vm.expectRevert(
                abi.encodeWithSelector(
                    GovernorInsufficientProposerVotes.selector, thresholdTester, amount, PROPOSAL_THRESHOLD
                )
            );
            governor.propose(targets, values, calldatas, "Threshold fuzzed proposal");
        } else {
            vm.prank(thresholdTester);
            uint256 propId = governor.propose(targets, values, calldatas, "Threshold fuzzed proposal success");
            assertTrue(propId > 0);
        }
    }
}
