// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PriceOracle} from "./PriceOracle.sol";

/**
 * @title PriceOracleV2
 * @notice V2 implementation of PriceOracle to demonstrate and test UUPS upgradeability.
 */
contract PriceOracleV2 is PriceOracle {
    /**
     * @notice Returns the contract version.
     */
    function version() external pure returns (string memory) {
        return "V2";
    }
}
