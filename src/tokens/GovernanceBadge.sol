// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernanceBadge
 * @dev Secure ERC-721 badge contract to reward governance participation.
 * Minting is restricted exclusively to the ProtocolGovernor or the ProtocolTimelock.
 */
contract GovernanceBadge is ERC721, Ownable {
    uint256 private _nextTokenId;
    
    address public governor;
    address public timelock;

    // Custom errors
    error NotAuthorizedMint();
    error InvalidAddress();

    event GovernanceRolesUpdated(address indexed newGovernor, address indexed newTimelock);

    modifier onlyGovernorOrTimelock() {
        if (msg.sender != governor && msg.sender != timelock) {
            revert NotAuthorizedMint();
        }
        _;
    }

    constructor(address _governor, address _timelock) 
        ERC721("Governance Badge", "GBADGE") 
        Ownable(msg.sender)
    {
        if (_governor == address(0) || _timelock == address(0)) {
            revert InvalidAddress();
        }
        governor = _governor;
        timelock = _timelock;
    }

    /**
     * @notice Mints a governance badge to reward an address.
     * @dev Restricted to either Governor or Timelock.
     * @param to Address to receive the governance badge.
     * @return The newly minted token ID.
     */
    function mintBadge(address to) external onlyGovernorOrTimelock returns (uint256) {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Updates the Governor and Timelock contract references.
     * @dev Restricted to the contract owner (which should be transitioned to the Timelock controller).
     * @param _governor The new Governor address.
     * @param _timelock The new Timelock address.
     */
    function updateRoles(address _governor, address _timelock) external onlyOwner {
        if (_governor == address(0) || _timelock == address(0)) {
            revert InvalidAddress();
        }
        governor = _governor;
        timelock = _timelock;
        emit GovernanceRolesUpdated(_governor, _timelock);
    }
}
