// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SecureBank
 * @notice Fixed bank contract incorporating ReentrancyGuard, Ownable, and Checks-Effects-Interactions pattern.
 */
contract SecureBank is ReentrancyGuard, Ownable {
    mapping(address => uint256) public balances;

    constructor() payable Ownable(msg.sender) {}

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /**
     * @notice Secure withdraw function
     * @dev Follows Checks-Effects-Interactions pattern and uses nonReentrant modifier.
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // EFFECT FIRST (update state)
        balances[msg.sender] -= amount;

        // INTERACTION LAST
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Secure administrative function
     * @dev Guarded with onlyOwner modifier, preventing unauthorized draining.
     */
    function drainBank() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Drain failed");
    }

    receive() external payable {}
}
