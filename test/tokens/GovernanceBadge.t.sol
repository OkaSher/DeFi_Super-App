// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceBadge} from "../../src/tokens/GovernanceBadge.sol";

contract GovernanceBadgeTest is Test {
    GovernanceBadge public badge;

    address public owner = makeAddr("owner");
    address public governor = makeAddr("governor");
    address public timelock = makeAddr("timelock");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    error NotAuthorizedMint();
    error InvalidAddress();
    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        vm.prank(owner);
        badge = new GovernanceBadge(governor, timelock);
    }

    function test_BadgeInitialization() public view {
        assertEq(badge.name(), "Governance Badge");
        assertEq(badge.symbol(), "GBADGE");
        assertEq(badge.governor(), governor);
        assertEq(badge.timelock(), timelock);
        assertEq(badge.owner(), owner);
    }

    function test_BadgeInitializationRevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        new GovernanceBadge(address(0), timelock);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        new GovernanceBadge(governor, address(0));
    }

    function test_MintBadgeAuthorizedGovernor() public {
        // Minting from Governor should succeed
        vm.prank(governor);
        uint256 tokenId = badge.mintBadge(alice);
        assertEq(tokenId, 0);
        assertEq(badge.ownerOf(tokenId), alice);
        assertEq(badge.balanceOf(alice), 1);
    }

    function test_MintBadgeAuthorizedTimelock() public {
        // Minting from Timelock should succeed
        vm.prank(timelock);
        uint256 tokenId = badge.mintBadge(bob);
        assertEq(tokenId, 0);
        assertEq(badge.ownerOf(tokenId), bob);
        assertEq(badge.balanceOf(bob), 1);
    }

    function test_MintBadgeUnauthorizedReverts() public {
        // Minting from Owner or stranger should revert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorizedMint.selector));
        badge.mintBadge(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorizedMint.selector));
        badge.mintBadge(alice);
    }

    function test_MintBadgeRevertsOnZeroAddress() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        badge.mintBadge(address(0));
    }

    function test_UpdateRolesOwnerOnly() public {
        address newGov = makeAddr("newGov");
        address newTime = makeAddr("newTime");

        // Stranger trying to update roles should revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        badge.updateRoles(newGov, newTime);

        // Owner updating roles should succeed
        vm.prank(owner);
        badge.updateRoles(newGov, newTime);

        assertEq(badge.governor(), newGov);
        assertEq(badge.timelock(), newTime);
    }

    function test_UpdateRolesRevertsOnZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        badge.updateRoles(address(0), timelock);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        badge.updateRoles(governor, address(0));

        vm.stopPrank();
    }
}
