// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/StakingMining.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockRNT is ERC20 {
    constructor() ERC20("Mock RNT", "MRNT") {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract StakingMiningTest is Test {
    StakingMining staking;
    MockRNT rnt;
    address owner = address(0x1234);
    address user = address(0x5678);

    function setUp() public {
        vm.startPrank(owner);
        rnt = new MockRNT();
        staking = new StakingMining(address(rnt));
        rnt.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    function testDepositReward() public {
        vm.startPrank(owner);
        uint256 amount = 1000e18;
        staking.depositRewardRNT(amount);
        assertEq(staking.rewardRNT(), amount);
        vm.stopPrank();
    }

    function testStakeAndUnstake() public {
        vm.startPrank(owner);
        rnt.transfer(user, 500e18);
        vm.stopPrank();

        vm.startPrank(user);
        rnt.approve(address(staking), type(uint256).max);
        staking.stake(200e18);
        assertEq(staking.stakedAmount(user), 200e18, "Stake not recorded");
        staking.unstake(50e18);
        assertEq(staking.stakedAmount(user), 150e18, "Unstake not recorded");
        vm.stopPrank();
    }

    function testClaimRewards() public {
        vm.startPrank(owner);
        rnt.transfer(user, 500e18);
        vm.stopPrank();

        vm.startPrank(user);
        rnt.approve(address(staking), type(uint256).max);
        staking.stake(200e18);
        vm.warp(block.timestamp + 1 days);
        staking.claimRewards();
        (uint256 esAmount, ) = staking.userEsRNT(user, 0);
        assertEq(esAmount, 200e18, "No batch created");
        vm.stopPrank();
    }

    function testExchangeEsRNTForRNT() public {
        vm.startPrank(owner);
        rnt.transfer(user, 500e18);
        staking.depositRewardRNT(500e18);
        vm.stopPrank();

        vm.startPrank(user);
        rnt.approve(address(staking), type(uint256).max);
        staking.stake(100e18);
        vm.warp(block.timestamp + 1 days);
        staking.claimRewards();
        (uint256 esRntAmount,) = staking.userEsRNT(user, 0);
        staking.exchangeEsRNTForRNT(esRntAmount);
        console.log(rnt.balanceOf(user));
        assertEq(rnt.balanceOf(user), 100e18, "RNT not received");
        vm.stopPrank();
        // Check user's RNT grows from vested portion
        // Full test of vesting details omitted for brevity
        vm.stopPrank();
    }
}