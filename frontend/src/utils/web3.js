import { BrowserProvider, Contract, parseUnits } from 'ethers';

// For local testing, ensure these addresses match your anvil deployment,
// or Arbitrum Sepolia if testing on testnet.
export const FACTORY_ADDRESS = "0xFE1b72aB29a831831e4E4c1cE855214720c0e9E5";
export const AMM_ABI = [
    "function getReserves() external view returns (uint256 reserve0, uint256 reserve1)",
    "function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut)",
    "function swap(uint256 amountIn, uint256 minAmountOut, address tokenIn, address to) external returns (uint256 amountOut)",
    "function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to) external returns (uint256 shares)",
    "function removeLiquidity(uint256 shares, address to) external returns (uint256 amount0, uint256 amount1)",
    "function balanceOf(address account) external view returns (uint256)",
    "function totalSupply() external view returns (uint256)",
    "function token0() external view returns (address)",
    "function token1() external view returns (address)"
];

export const ERC20_ABI = [
    "function balanceOf(address account) external view returns (uint256)",
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function allowance(address owner, address spender) external view returns (uint256)",
    "function symbol() external view returns (string)",
    "function decimals() external view returns (uint8)"
];

export const FACTORY_ABI = [
    "function getPool(address tokenA, address tokenB) external view returns (address pool)",
    "function createPool(address tokenA, address tokenB) external returns (address pool)"
];

export const GOV_TOKEN_ADDRESS = "0x2b968A9276f08270c1d4bAE6B0eE01Dd89679682";
export const TEST_TOKEN_ADDRESS = "0xbdEf1F4589a87095ac77edACCB4FE6dA551FacCf";
export const GOVERNOR_ADDRESS = "0x3559d29Ea49bC09140f8e4634865722d7084F3b2";

export const GOV_TOKEN_ABI = [
    "function balanceOf(address account) external view returns (uint256)",
    "function delegate(address delegatee) external",
    "function delegates(address account) external view returns (address)",
    "function getVotes(address account) external view returns (uint256)",
    "function approve(address spender, uint256 amount) external returns (bool)"
];

export const GOVERNOR_ABI = [
    "function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) external returns (uint256)",
    "function castVote(uint256 proposalId, uint8 support) external returns (uint256)",
    "function state(uint256 proposalId) external view returns (uint8)",
    "function proposalThreshold() external view returns (uint256)",
    "function quorum(uint256 timepoint) external view returns (uint256)",
    "function countMembers() external view returns (uint256)"
];

export async function connectWallet() {
    if (!window.ethereum) throw new Error("MetaMask is not installed!");
    const provider = new BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    return { provider, account: accounts[0] };
}

export function parseError(err) {
    // Web3 error decoder for custom Solidity errors
    const str = err.message || err.toString();
    if (str.includes("0x08c379a0") && str.includes("K")) return "Invariant K broken (Slippage or Math Error)";
    if (str.includes("SlippageExceeded")) return "Slippage tolerance exceeded!";
    if (str.includes("InsufficientShares")) return "Not enough liquidity shares!";
    if (str.includes("ZeroAmount") || str.includes("ZeroAddress")) return "Invalid zero amount/address.";
    if (str.includes("user rejected action")) return "Transaction rejected by user.";
    return "Unknown transaction error. See console.";
}

