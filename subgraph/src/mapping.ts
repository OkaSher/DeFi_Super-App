import { BigInt } from "@graphprotocol/graph-ts"
import {
  ProposalCreated,
  VoteCast,
  ProposalExecuted
} from "../generated/ProtocolGovernor/ProtocolGovernor"
import { Swap } from "../generated/AMM/AMM"
import { User, PoolSwap, Proposal, Vote } from "../generated/schema"

export function handleProposalCreated(event: ProposalCreated): void {
  let proposalId = event.params.proposalId.toString()
  let proposal = new Proposal(proposalId)

  let proposerId = event.params.proposer.toHexString()
  let proposer = User.load(proposerId)
  if (proposer == null) {
    proposer = new User(proposerId)
    proposer.governanceTokenBalance = BigInt.fromI32(0)
    proposer.save()
  }

  proposal.description = event.params.description
  proposal.proposer = proposerId
  proposal.startBlock = event.params.voteStart
  proposal.endBlock = event.params.voteEnd
  proposal.forVotes = BigInt.fromI32(0)
  proposal.againstVotes = BigInt.fromI32(0)
  proposal.abstainVotes = BigInt.fromI32(0)
  proposal.state = "PENDING"
  proposal.save()
}

export function handleVoteCast(event: VoteCast): void {
  let proposalId = event.params.proposalId.toString()
  let proposal = Proposal.load(proposalId)
  if (proposal == null) return

  let voterId = event.params.voter.toHexString()
  let voter = User.load(voterId)
  if (voter == null) {
    voter = new User(voterId)
    voter.governanceTokenBalance = BigInt.fromI32(0)
    voter.save()
  }

  let voteId = voterId + "-" + proposalId
  let vote = new Vote(voteId)
  vote.voter = voterId
  vote.proposal = proposalId
  vote.weight = event.params.weight

  let supportType = event.params.support
  if (supportType == 0) {
    vote.support = "AGAINST"
    proposal.againstVotes = proposal.againstVotes.plus(event.params.weight)
  } else if (supportType == 1) {
    vote.support = "FOR"
    proposal.forVotes = proposal.forVotes.plus(event.params.weight)
  } else {
    vote.support = "ABSTAIN"
    proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight)
  }

  vote.save()
  proposal.save()
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposalId = event.params.proposalId.toString()
  let proposal = Proposal.load(proposalId)
  if (proposal != null) {
    proposal.state = "EXECUTED"
    proposal.save()
  }
}

export function handleSwap(event: Swap): void {
  let swapId = event.transaction.hash.toHexString() + "-" + event.logIndex.toString()
  let swap = new PoolSwap(swapId)
  swap.swapper = event.params.sender
  swap.tokenIn = event.params.tokenIn
  swap.tokenOut = event.params.tokenOut
  swap.amountIn = event.params.amountIn
  swap.amountOut = event.params.amountOut
  swap.timestamp = event.block.timestamp
  swap.transactionHash = event.transaction.hash
  swap.save()
}
