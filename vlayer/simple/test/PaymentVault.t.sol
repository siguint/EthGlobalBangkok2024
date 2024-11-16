// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PaymentVault} from "../src/PaymentVault.sol";
import {ExampleToken} from "../src/vlayer/ExampleToken.sol";

contract PaymentVaultTest is Test {
    PaymentVault public vault;
    ExampleToken public token;
    address owner;
    address user;
    address serviceReceiver;
    uint256 constant INITIAL_SUPPLY = 1000000e18;
    uint256 constant SUBSCRIPTION_PRICE = 10e18;
    uint256 serviceId;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        serviceReceiver = makeAddr("serviceReceiver");
        
        vm.startPrank(owner);
        token = new ExampleToken(owner, INITIAL_SUPPLY);
        vault = new PaymentVault(address(token));
        serviceId = vault.registerService(serviceReceiver, SUBSCRIPTION_PRICE);
        vm.stopPrank();
    }

    function test_RegisterService() public {
        vm.startPrank(owner);
        uint256 newServiceId = vault.registerService(serviceReceiver, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        (uint256 price, address receiver, bool isActive) = vault.services(newServiceId);
        assertEq(price, SUBSCRIPTION_PRICE);
        assertEq(receiver, serviceReceiver);
        assertTrue(isActive);
    }

    function test_Subscribe() public {
        // Give user enough tokens for subscription
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.subscribe(serviceId);
        vm.stopPrank();

        assertEq(vault.deposits(serviceId, user), SUBSCRIPTION_PRICE);
        assertEq(vault.serviceTotalDeposits(serviceId), SUBSCRIPTION_PRICE);
        assertEq(vault.totalDeposits(), SUBSCRIPTION_PRICE);
        assertEq(token.balanceOf(address(vault)), SUBSCRIPTION_PRICE);
        assertTrue(vault.isSubscriptionActive(serviceId, user));
    }

    function test_WithdrawAsServiceReceiver() public {
        // Setup initial subscription
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.subscribe(serviceId);
        vm.stopPrank();

        // Test withdrawal
        vm.startPrank(serviceReceiver);
        uint256 beforeBalance = token.balanceOf(serviceReceiver);
        vault.withdraw(serviceId, SUBSCRIPTION_PRICE);
        uint256 afterBalance = token.balanceOf(serviceReceiver);
        vm.stopPrank();

        assertEq(afterBalance - beforeBalance, SUBSCRIPTION_PRICE);
        assertEq(vault.serviceTotalDeposits(serviceId), 0);
        assertEq(vault.totalDeposits(), 0);
    }

    function testFail_WithdrawAsNonReceiver() public {
        // Setup initial subscription
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.subscribe(serviceId);
        // Try to withdraw as non-receiver
        vault.withdraw(serviceId, SUBSCRIPTION_PRICE);
        vm.stopPrank();
    }

    function testFail_WithdrawMoreThanDeposited() public {
        // Setup initial subscription
        vm.startPrank(owner);
        token.transfer(user, SUBSCRIPTION_PRICE);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), SUBSCRIPTION_PRICE);
        vault.subscribe(serviceId);
        vm.stopPrank();

        // Try to withdraw more than deposited
        vm.prank(serviceReceiver);
        vault.withdraw(serviceId, SUBSCRIPTION_PRICE + 1);
    }

    function test_DeactivateService() public {
        vm.prank(owner);
        vault.deactivateService(serviceId);

        (,, bool isActive) = vault.services(serviceId);
        assertFalse(isActive);
    }

    function test_SetSubscriptionPrice() public {
        uint256 newPrice = SUBSCRIPTION_PRICE * 2;
        
        vm.prank(serviceReceiver);
        vault.setSubscriptionPrice(serviceId, newPrice);

        (uint256 price,,) = vault.services(serviceId);
        assertEq(price, newPrice);
    }
}
