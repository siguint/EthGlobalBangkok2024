// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PaymentVault} from "../src/PaymentsVault.sol";
import {ExampleToken} from "../src/vlayer/ExampleToken.sol";

contract PaymentVaultTest is Test {
    PaymentVault public vault;
    ExampleToken public token;
    address owner;
    address user;
    uint256 constant INITIAL_SUPPLY = 1000000e18;
    uint256 constant SUBSCRIPTION_PRICE = 10e18;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        
        vm.startPrank(owner);
        token = new ExampleToken(owner, INITIAL_SUPPLY);
        vault = new PaymentVault(address(token), SUBSCRIPTION_PRICE);
        vm.stopPrank();
    }

    function test_Deposit() public {
        // Give user enough tokens for subscription
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.deposit();
        vm.stopPrank();

        assertEq(vault.deposits(user), SUBSCRIPTION_PRICE);
        assertEq(vault.totalDeposits(), SUBSCRIPTION_PRICE);
        assertEq(token.balanceOf(address(vault)), SUBSCRIPTION_PRICE);
    }

    function test_WithdrawAsOwner() public {
        // Setup initial deposit
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.deposit();
        vm.stopPrank();

        // Test withdrawal
        vm.startPrank(owner);
        uint256 beforeBalance = token.balanceOf(owner);
        vault.withdraw(SUBSCRIPTION_PRICE);
        uint256 afterBalance = token.balanceOf(owner);
        vm.stopPrank();

        assertEq(afterBalance - beforeBalance, SUBSCRIPTION_PRICE);
        assertEq(vault.totalDeposits(), 0);
    }

    function testFail_WithdrawAsNonOwner() public {
        // Setup initial deposit
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.deposit();
        // Try to withdraw as non-owner
        vault.withdraw(SUBSCRIPTION_PRICE);
        vm.stopPrank();
    }

    function testFail_WithdrawMoreThanDeposited() public {
        // Setup initial deposit
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.deposit();
        vm.stopPrank();

        // Try to withdraw more than deposited
        vm.prank(owner);
        vault.withdraw(SUBSCRIPTION_PRICE + 1);
    }
}
