// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SimpleTestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}

contract DeployTestToken is Script {
    function run() external {
        vm.startBroadcast();

        SimpleTestToken testToken = new SimpleTestToken();

        vm.stopBroadcast();

        address deployedAddress = address(testToken);
        console2.log("Test Token deployed at:", deployedAddress);
        console2.log("Supply: 1,000,000 TEST tokens");
    }
}

// Add console2 import for logging
import {console2} from "forge-std/console2.sol";
