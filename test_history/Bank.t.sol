// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Bank.sol";  // 假设 Bank 合约存放在 contracts 文件夹内

contract BankTest is Test {
    Bank bank;

    function setUp() public {
        bank = new Bank();
    }

    function testDepositETH() public {
        address user = address(0x123);
        uint256 depositAmount = 1 ether;

        // 检查存款前用户的存款额
        uint256 initialBalance = bank.balanceOf(user);
        assertEq(initialBalance, 0, "Initial balance should be zero");

        // 进行存款
        vm.prank(user);
        vm.deal(user, depositAmount);
        
        // 设置事件期望
        vm.expectEmit(true, true, false, true);
        emit Bank.Deposit(user, 2000000000000000000);
        
        // 用户发送存款交易
        bank.depositETH{value: depositAmount}();

        // 检查存款后用户的存款额
        uint256 finalBalance = bank.balanceOf(user);
        assertEq(finalBalance, depositAmount, "Final balance should match deposit amount");
    }
}