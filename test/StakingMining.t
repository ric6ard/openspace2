// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/StakingMining.sol";

contract MockERC20 is IERC20 {
    string public name = "MockERC20";
    string public symbol = "MERC20";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
        totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }
}

contract StakingMiningTest is Test {
    StakingMining public stakingMining;
    MockERC20 public rnt;
    address public owner;
    address public userA;
    address public userB;

    uint256 constant SECONDS_PER_DAY = 86400;
    uint256 constant VESTING_PERIOD = 30 days;

    function setUp() public {
        owner = address(this);
        userA = address(0x123);
        userB = address(0x456);
        rnt = new MockERC20();
        stakingMining = new StakingMining(address(rnt));

        // 为用户铸造 RNT
        rnt.mint(userA, 1000 ether);
        rnt.mint(userB, 500 ether);
    }

    function testStake() public {
        uint256 stakeAmount = 100 ether;
        vm.startPrank(userA);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        vm.stopPrank();

        assertEq(stakingMining.stakedAmount(userA), stakeAmount);
        assertEq(stakingMining.totalStakedRNT(), stakeAmount);
        assertEq(rnt.balanceOf(address(stakingMining)), stakeAmount);
    }

    function testUnstake() public {
        uint256 stakeAmount = 100 ether;
        vm.startPrank(userA);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        vm.stopPrank();

        uint256 unstakeAmount = 50 ether;
        vm.startPrank(userA);
        stakingMining.unstake(unstakeAmount);
        vm.stopPrank();

        assertEq(stakingMining.stakedAmount(userA), stakeAmount - unstakeAmount);
        assertEq(stakingMining.totalStakedRNT(), stakeAmount - unstakeAmount);
        assertEq(rnt.balanceOf(userA), 1000 ether - stakeAmount + unstakeAmount);
        assertEq(rnt.balanceOf(address(stakingMining)), stakeAmount - unstakeAmount);
    }

    function testClaimRewards() public {
        uint256 stakeAmount = 100 ether;
        uint256 initialTime = block.timestamp;
        vm.warp(initialTime);

        vm.startPrank(userA);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        vm.stopPrank();

        uint256 timeElapsed = 2 days;
        uint256 newTime = initialTime + timeElapsed;
        vm.warp(newTime);

        vm.startPrank(userA);
        stakingMining.claimRewards();
        vm.stopPrank();

        uint256 daysElapsed = timeElapsed / SECONDS_PER_DAY;
        uint256 expectedEsRNT = (stakeAmount / 1e18) * daysElapsed * 1e18; // 转换为 esRNT 单位
        (StakingMining.Batch[] memory batches, uint256 totalEsRNT) = stakingMining.userEsRNT(userA, 0);
        assertEq(batches.length, 1);
        assertEq(batches[0].amount, expectedEsRNT);
        assertEq(batches[0].creationTime, newTime);
        assertEq(stakingMining.lastClaimTime(userA), newTime);
    }

    function testExchangeEsRNTForRNT() public {
        uint256 stakeAmount = 100 ether;
        uint256 initialTime = block.timestamp;
        vm.warp(initialTime);

        vm.startPrank(userA);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        vm.stopPrank();

        uint256 timeToClaim = initialTime + 2 days;
        vm.warp(timeToClaim);

        vm.startPrank(userA);
        stakingMining.claimRewards();
        vm.stopPrank();

        uint256 timeElapsedForClaim = timeToClaim - initialTime;
        uint256 daysElapsedForClaim = timeElapsedForClaim / SECONDS_PER_DAY;
        uint256 esRNTFromClaim = (stakeAmount / 1e18) * daysElapsedForClaim * 1e18; // 200 esRNT

        uint256 timeToExchange = timeToClaim + 10 days;
        vm.warp(timeToExchange);

        uint256 rewardDeposit = 1000 ether;
        vm.startPrank(owner);
        rnt.approve(address(stakingMining), rewardDeposit);
        stakingMining.depositRewardRNT(rewardDeposit);
        vm.stopPrank();

        uint256 amountToExchange = esRNTFromClaim / 2; // 兑换一半 esRNT
        uint256 currentTime = block.timestamp;
        uint256 batchCreationTime = timeToClaim;
        uint256 vestedSeconds = currentTime - batchCreationTime;
        if(vestedSeconds > VESTING_PERIOD) {
            vestedSeconds = VESTING_PERIOD;
        }
        uint256 vestedFraction = (vestedSeconds * 1e18) / VESTING_PERIOD;
        uint256 expectedVestedRNT = amountToExchange * vestedFraction / 1e18; // 转换为 RNT 单位

        vm.startPrank(userA);
        stakingMining.exchangeEsRNTForRNT(amountToExchange);
        vm.stopPrank();

        assertEq(rnt.balanceOf(userA), 1000 ether - stakeAmount + expectedVestedRNT);
        assertEq(stakingMining.rewardRNT(), rewardDeposit - expectedVestedRNT);
        StakingMining.Batch[] memory batches = stakingMining.userEsRNT(userA);
        assertEq(batches.length, 1);
        assertEq(batches[0].amount, esRNTFromClaim - amountToExchange);
    }
}