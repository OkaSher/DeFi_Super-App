import { BrowserProvider, Contract, parseUnits, JsonRpcProvider } from 'ethers';

// For local testing, ensure these addresses match your anvil deployment,
// or Arbitrum Sepolia if testing on testnet.
export const FACTORY_ADDRESS = "0x5fc8d32690cc91d4c39d9d3abcbd16989f875707";
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

export const GOV_TOKEN_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
export const GOVERNER_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";
export const VAULT_ADDRESS = "0x0165878A594ca255338adfa4d48449f69242Eb8F";

export const VAULT_ABI = [
    "function asset() external view returns (address)",
    "function totalAssets() external view returns (uint256)",
    "function convertToShares(uint256 assets) external view returns (uint256)",
    "function convertToAssets(uint256 shares) external view returns (uint256)",
    "function deposit(uint256 assets, address receiver) external returns (uint256 shares)",
    "function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares)",
    "function balanceOf(address account) external view returns (uint256)",
    "function totalSupply() external view returns (uint256)"
];

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
    if (window.ethereum) {
        const provider = new BrowserProvider(window.ethereum);
        const accounts = await provider.send("eth_requestAccounts", []);
        return { provider, account: accounts[0] };
    } else {
        console.warn("MetaMask not detected, falling back to local Anvil node...");
        const provider = new JsonRpcProvider("http://127.0.0.1:8545");
        const account = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
        return { provider, account };
    }
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

