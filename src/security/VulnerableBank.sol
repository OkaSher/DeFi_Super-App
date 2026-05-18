// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VulnerableBank
 * @notice A bank contract designed to demonstrate reentrancy and access control exploits.
 * @dev DO NOT USE IN PRODUCTION.
 */
contract VulnerableBank {
    mapping(address => uint256) public balances;

    constructor() payable {}

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /**
     * @notice Vulnerable withdraw function (Reentrancy vector)
     * @dev Sends ether before updating balance (Checks-Effects-Interactions violation)
     */
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // INTERACTION BEFORE EFFECT
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");

        // EFFECT AFTER INTERACTION
        unchecked {
            balances[msg.sender] -= amount;
        }
    }

    /**
     * @notice Vulnerable administration function (Access Control violation)
     * @dev Unguarded function that should be owner-only, allowing anyone to drain funds.
     */
    function drainBank() external {
        // MISSING OWNER REQUIREMENT OR ACCESS CONTROL
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Drain failed");
    }

    receive() external payable {}
}
