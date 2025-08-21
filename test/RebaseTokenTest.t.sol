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
    uint256 public constant SEND_VALUE = 1e5;

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: STARTING_VAULT_BALANCE}("");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        // Deposit funds
        amount = bound(amount, 1e6, type(uint96).max);
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(USER);
        console.log("block.timestamp", block.timestamp);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        console.log("block.timestamp", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(USER);
        console.log("middleBalance", middleBalance);
        assertGe(middleBalance, startBalance);
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(USER);
        console.log("block.timestamp", block.timestamp);
        console.log("endBalance", endBalance);
        assertGe(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

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

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // this is a crazy number of years - 2^96 seconds is a lot
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // this is an Ether value of max 2^78 which is crazy

        // Deposit funds
        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();

        // check the balance has increased after some time has passed
        vm.warp(time);

        // Get balance after time has passed
        uint256 balance = rebaseToken.balanceOf(USER);

        // Add rewards to the vault
        vm.deal(OWNER, balance - depositAmount);
        vm.prank(OWNER);
        addRewardsToVault(balance - depositAmount);

        // Redeem funds
        vm.prank(USER);
        vault.redeem(balance);

        uint256 ethBalance = address(USER).balance;

        assertApproxEqAbs(balance, ethBalance, 1);
        assertGe(balance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e6, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);

        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(USER);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        vm.prank(USER);
        rebaseToken.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(USER);
        uint256 userTwoBalancAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalancAfterTransfer, userTwoBalance + amountToSend);

        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(USER);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);

        uint256 userTwoInterestRate = rebaseToken.getUserInterestRate(userTwo);
        assertEq(userTwoInterestRate, 5e10);

        uint256 userInterestRate = rebaseToken.getUserInterestRate(USER);
        assertEq(userInterestRate, 5e10);

        assertGe(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGe(userTwoBalanceAfterWarp, userTwoBalancAfterTransfer);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.startPrank(USER);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function testCannotCallMint() public {
        vm.startPrank(USER);
        vm.expectRevert();
        rebaseToken.mint(USER, SEND_VALUE, rebaseToken.getInterestRate());
        vm.stopPrank();
    }

    function testCannotCallBurn() public {
        vm.startPrank(USER);
        vm.expectRevert();
        rebaseToken.burn(USER, SEND_VALUE);
        vm.stopPrank();
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(OWNER);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    /*//////////////////////////////////////////////////////////////
                              GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetInterestRate_Default() public view {
        uint256 rate = rebaseToken.getInterestRate();
        assertEq(rate, 5e10);
    }

    function testGetUserInterestRate_AfterDeposit() public {
        uint256 depositAmount = 1 ether;
        vm.deal(USER, depositAmount);

        vm.startPrank(USER);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        uint256 userRate = rebaseToken.getUserInterestRate(USER);
        assertEq(userRate, rebaseToken.getInterestRate());
    }

    function testGetPrincipleBalanceOf_AfterDepositAndRedeem() public {
        uint256 depositAmount = 2 ether;
        vm.deal(USER, depositAmount);

        vm.startPrank(USER);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        uint256 principleAfterDeposit = rebaseToken.getPrincipleBalanceOf(USER);
        assertEq(principleAfterDeposit, depositAmount);

        vm.startPrank(USER);
        vault.redeem(type(uint256).max);
        vm.stopPrank();

        uint256 principleAfterRedeem = rebaseToken.getPrincipleBalanceOf(USER);
        assertEq(principleAfterRedeem, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ADDITIONAL COMPREHENSIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function testMintAndBurnWithRole() public {
        uint256 mintAmount = 1e18;
        uint256 burnAmount = 5e17;
        address recipient = makeAddr("recipient");

        // Grant MINT_AND_BURN_ROLE to a new address
        address minter = makeAddr("minter");
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(minter);

        // Mint tokens as minter
        vm.prank(minter);
        rebaseToken.mint(recipient, mintAmount, rebaseToken.getInterestRate());
        assertEq(rebaseToken.balanceOf(recipient), mintAmount);

        // Burn tokens as minter
        vm.prank(minter);
        rebaseToken.burn(recipient, burnAmount);
        assertEq(rebaseToken.balanceOf(recipient), mintAmount - burnAmount);
    }

    function testMintWithoutRoleFails() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        rebaseToken.mint(attacker, 1e18, rebaseToken.getInterestRate());
    }

    function testBurnWithoutRoleFails() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        rebaseToken.burn(attacker, 1e18);
    }

    function testTransferFromFunctionality() public {
        uint256 amount = 1e18;
        address sender = makeAddr("sender");
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");

        vm.deal(sender, amount);
        vm.prank(sender);
        vault.deposit{value: amount}();

        // Approve spender
        vm.prank(sender);
        rebaseToken.approve(spender, amount);

        // Spender transfers tokens from sender to recipient
        vm.prank(spender);
        rebaseToken.transferFrom(sender, recipient, amount);

        assertEq(rebaseToken.balanceOf(sender), 0);
        assertEq(rebaseToken.balanceOf(recipient), amount);

        // Check interest rate for recipient is set to default after transfer
        uint256 recipientRate = rebaseToken.getUserInterestRate(recipient);
        assertEq(recipientRate, rebaseToken.getInterestRate());
    }

    function testTransferFromMaxUint256() public {
        uint256 amount = 1e18;
        address sender = makeAddr("sender");
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");

        vm.deal(sender, amount);
        vm.prank(sender);
        vault.deposit{value: amount}();

        // Approve spender with max uint256
        vm.prank(sender);
        rebaseToken.approve(spender, type(uint256).max);

        // Spender transfers partial amount
        vm.prank(spender);
        rebaseToken.transferFrom(sender, recipient, amount / 2);

        // Allowance should still be max uint256 (no decrement)
        uint256 allowance = rebaseToken.allowance(sender, spender);
        assertEq(allowance, type(uint256).max);

        // Spender transfers remaining amount
        vm.prank(spender);
        rebaseToken.transferFrom(sender, recipient, amount / 2);

        // Balance checks
        assertEq(rebaseToken.balanceOf(sender), 0);
        assertEq(rebaseToken.balanceOf(recipient), amount);
    }

    function testInterestAccrualOverTimeMultipleUsers() public {
        uint256 depositAmount = 1 ether;
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.deal(user1, depositAmount);
        vm.deal(user2, depositAmount);

        vm.startPrank(user1);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        vm.startPrank(user2);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        uint256 balance1Start = rebaseToken.balanceOf(user1);
        uint256 balance2Start = rebaseToken.balanceOf(user2);

        // Warp time 1 hour
        vm.warp(block.timestamp + 1 hours);

        uint256 balance1After = rebaseToken.balanceOf(user1);
        uint256 balance2After = rebaseToken.balanceOf(user2);

        // Both balances should have increased due to interest
        assertGe(balance1After, balance1Start);
        assertGe(balance2After, balance2Start);

        // Balances should be approximately equal
        assertApproxEqAbs(balance1After, balance2After, 1e10);
    }

    function testSetInterestRateFailsWhenIncreasing() public {
        uint256 initialRate = rebaseToken.getInterestRate();
        uint256 increasedRate = initialRate + 1;

        vm.prank(OWNER);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(increasedRate);
    }

    function testRedeemFullBalanceAfterInterestAccrued() public {
        uint256 depositAmount = 1 ether;
        vm.deal(USER, depositAmount);

        vm.startPrank(USER);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        // Warp time forward to accrue interest
        vm.warp(block.timestamp + 1 days);

        uint256 balance = rebaseToken.balanceOf(USER);
        assertGe(balance, depositAmount);

        vm.startPrank(USER);
        vault.redeem(type(uint256).max);
        vm.stopPrank();

        // After redeem, balance should be zero
        assertEq(rebaseToken.balanceOf(USER), 0);

        // User's ETH balance should have increased approximately by accrued amount
        assertApproxEqAbs(address(USER).balance, balance, 1);
    }

    /*//////////////////////////////////////////////////////////////
               ADDITIONAL TESTS TO INCREASE BRANCH COVERAGE
    //////////////////////////////////////////////////////////////*/

    function testSetInterestRate_Decrease() public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        uint256 newInterestRate = initialInterestRate - 1e9; // smaller than current rate

        vm.prank(OWNER);
        rebaseToken.setInterestRate(newInterestRate);

        uint256 updatedRate = rebaseToken.getInterestRate();
        assertEq(updatedRate, newInterestRate);
        assertLt(updatedRate, initialInterestRate);
    }

    function testTransferToExistingRecipient() public {
        uint256 amount = 1e18;
        uint256 transferAmount = 1e17;
        address sender = makeAddr("sender");
        address recipient = makeAddr("recipient");

        // Setup: sender deposits, recipient deposits to have existing balance
        vm.deal(sender, amount);
        vm.deal(recipient, amount);

        vm.prank(sender);
        vault.deposit{value: amount}();

        vm.prank(recipient);
        vault.deposit{value: amount}();

        uint256 senderBalanceBefore = rebaseToken.balanceOf(sender);
        uint256 recipientBalanceBefore = rebaseToken.balanceOf(recipient);
        assertGt(recipientBalanceBefore, 0);

        vm.prank(sender);
        rebaseToken.transfer(recipient, transferAmount);

        uint256 senderBalanceAfter = rebaseToken.balanceOf(sender);
        uint256 recipientBalanceAfter = rebaseToken.balanceOf(recipient);

        assertEq(senderBalanceAfter, senderBalanceBefore - transferAmount);
        assertEq(recipientBalanceAfter, recipientBalanceBefore + transferAmount);

        // Also test transferFrom to existing recipient
        vm.prank(sender);
        rebaseToken.approve(recipient, transferAmount);

        vm.prank(recipient);
        rebaseToken.transferFrom(sender, recipient, transferAmount);

        uint256 senderBalanceFinal = rebaseToken.balanceOf(sender);
        uint256 recipientBalanceFinal = rebaseToken.balanceOf(recipient);

        assertEq(senderBalanceFinal, senderBalanceAfter - transferAmount);
        assertEq(recipientBalanceFinal, recipientBalanceAfter + transferAmount);
    }
}
