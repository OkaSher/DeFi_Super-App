// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";


contract YieldVault is ERC20, ERC4626 {
   
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    )
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {}

    
    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 9;
    }
}
