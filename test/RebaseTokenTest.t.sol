// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;
    IRebaseToken i_rebaseToken;

    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");
    uint256 public constant STARTING_VAULT_BALANCE = 1 ether;

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: STARTING_VAULT_BALANCE}("");
        vm.stopPrank();
    }

    // function testDepositLinear(uint256 amount) public {
    //     amount = bound(amount, 1e5, type(uint96).max);
    //     vm.startPrank(USER);
    //     vm.deal(USER, amount);

    //     vault.deposit{value: amount}();
    //     uint256 startBalance = rebaseToken.balanceOf(USER);
    //     console.log("startBalance:", startBalance);
    //     assertEq(startBalance, amount);

    //     vm.warp(block.timestamp + 1 hours);
    //     uint256 middleBalance = rebaseToken.balanceOf(USER);
    //     assertGt(middleBalance, startBalance);

    //     vm.warp(block.timestamp + 1 hours);
    //     uint256 endBalance = rebaseToken.balanceOf(USER);
    //     assertGt(endBalance, middleBalance);

    //     assertApproxEqAb(endBalance - middleBalance, middleBalance - startBalance, 1e18);
    //     vm.stopPrank();
    // }

    function addRewardsToVault(uint256 amount) public {
        (bool success,) = payable(address(vault)).call{value: amount}("");
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        uint256 startBalance = rebaseToken.balanceOf(USER);
        assertEq(startBalance, amount);

        vault.redeem(type(uint256).max);
        uint256 endBalance = rebaseToken.balanceOf(USER);
        assertEq(endBalance, 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint256).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(USER);
        vm.prank(OWNER);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);

        vm.deal(OWNER, balanceAfterSomeTime - depositAmount);
        vm.prank(USER);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(USER).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }
}
