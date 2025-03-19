// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/StakingPool.sol";

// 创建一个模拟的 KK Token 实现 IToken 接口
contract MockToken is IToken {
    string public constant name = "KK Token";
    string public constant symbol = "KKT";
    uint8 public constant decimals = 18;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == stakingPool, "Not authorized to mint");
        _;
    }
    
    address public stakingPool;
    
    function setStakingPool(address _stakingPool) external onlyOwner {
        stakingPool = _stakingPool;
    }
    
    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }
    
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    
    function allowance(address _owner, address spender) external view override returns (uint256) {
        return _allowances[_owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");
        
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }
    
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }
    
    function _approve(address _owner, address _spender, uint256 _amount) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }
}

contract StakingPoolTest is Test {
    StakingPool public stakingPool;
    MockToken public token;
    address public alice;
    address public bob;
    
    uint256 public constant INITIAL_BALANCE = 100 ether;
    
    function setUp() public {
        // 创建用户
        alice = address(0x123);
        bob = address(0x456);
        
        // 给用户分配资金
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        
        // 部署合约
        token = new MockToken();
        stakingPool = new StakingPool(address(token));
        
        // 设置质押池权限
        token.setStakingPool(address(stakingPool));
    }
    
    function logPoolInfo() public view {
        uint256 x=stakingPool.lastUpdateBlock();
        uint256 y=stakingPool.totalStaked();
        uint256 z=stakingPool.accumulatedRewardPerWei(block.number);
        console.log("-----------------------------------------------------------------------");
        console.log('PoolInfo: Block number, Total staked, r:',x,y,z);
    }
    function logPoolInfoNum(uint256 blockNumber) public view {
        uint256 x=stakingPool.lastUpdateBlock();
        uint256 y=stakingPool.totalStaked();
        uint256 z=stakingPool.accumulatedRewardPerWei(blockNumber);
        console.log("-----------------------------------------------------------------------");
        console.log('PoolInfo: Block number, Total staked, r:',x,y,z);
    }
    function logUserInfo(address user) public view {
        (uint x,uint y,uint z) =stakingPool.userInfo(user);
        console.log('UserInfo: Staked Amount, Reward, Update Black:',x,y,z);
        console.log("-----------------------------------------------------------------------");
    }
    // 测试质押功能
    function testStake() public {
        uint256 stakeAmount = 10 ether;
        
        // Alice质押10 ETH
        vm.prank(alice);
        stakingPool.stake{value: stakeAmount}();
        // logPoolInfo();
        // logUserInfo(alice);
        
        // 检查质押后的结果
        assertEq(address(stakingPool).balance, stakeAmount, "StakingPool balance should match staked amount");
        assertEq(stakingPool.balanceOf(alice), stakeAmount, "Alice's staked balance should be correct");
        assertEq(stakingPool.totalStaked(), stakeAmount, "Total staked should be updated");
        assertEq(stakingPool.lastUpdateBlock(), block.number, "Last update block should be updated");
        assertEq(stakingPool.accumulatedRewardPerWei(block.number), 0, "Accumulated reward should be updated");
    }
    
    // 测试取消质押功能
    function testUnstake() public {
        uint256 stakeAmount = 10 ether;
        uint256 unstakeAmount = 5 ether;
        
        // Alice质押10 ETH
        vm.startPrank(alice);
        stakingPool.stake{value: stakeAmount}();
        
        // 记录取消质押前的余额
        uint256 balanceBefore = alice.balance;
        
        // Alice取消质押5 ETH
        stakingPool.unstake(unstakeAmount);
        vm.stopPrank();
        
        // 检查取消质押后的结果
        assertEq(alice.balance, balanceBefore + unstakeAmount, "Alice should receive unstaked ETH");
        assertEq(stakingPool.balanceOf(alice), stakeAmount - unstakeAmount, "Alice's staked balance should be reduced");
        assertEq(stakingPool.totalStaked(), stakeAmount - unstakeAmount, "Total staked should be reduced");
    }
    
    // 测试奖励计算
    function testEarned() public {
        uint256 stakeAmount = 10 ether;
        
        // Alice质押10 ETH
        vm.prank(alice);
        stakingPool.stake{value: stakeAmount}();
        
        // 推进10个区块
        vm.roll(block.number + 10);
        
        // 计算预期奖励: 10个区块 * 每区块10个代币 * 10^18 (token decimals)
        uint256 expectedReward = 10 * 10 * 10**18;
        
        // 检查奖励
        assertEq(stakingPool.earned(alice), expectedReward, "Earned reward should be calculated correctly");
    }
    
    // 测试领取奖励
    function testClaim() public {
        uint256 stakeAmount = 10 ether;
        // logPoolInfo();
        // logUserInfo(alice);
        
        // Alice质押10 ETH
        vm.prank(alice);
        stakingPool.stake{value: stakeAmount}();
        // logPoolInfo();
        // logUserInfo(alice);

        // 推进10个区块
        vm.roll(block.number + 10);
        
        // Alice领取奖励
        vm.prank(alice);
        stakingPool.claim();
        // logPoolInfo();
        // logUserInfo(alice);
        
        // 计算预期奖励
        uint256 expectedReward = 10 * 10 * 10**18;

        // 检查Alice的代币余额
        assertEq(token.balanceOf(alice), expectedReward, "Alice should receive correct reward tokens");
    }
    
    // 测试多用户质押和奖励分配
    function testMultipleUsers() public {
        // Alice质押10 ETH
        vm.prank(alice);
        stakingPool.stake{value: 10 }();

        // logPoolInfo();
        // logUserInfo(bob);
        
        // 推进5个区块
        vm.roll(block.number + 5);

        
        // Bob质押30 ETH (现在总质押是40 ETH)
        vm.prank(bob);
        stakingPool.stake{value: 30 }();
        
        // 推进5个区块
        vm.roll(block.number + 6);
        // logPoolInfo();
        // logUserInfo(bob);
        // Alice的预期奖励: 
        // 前5个区块: 5 * 10 * 10^18 = 50 * 10^18 (Alice拥有100%份额)
        // 后6个区块: 6 * 10 * 10^18 * (10/40) = 15 * 10^18 (Alice拥有1/4份额)
        // 总计: 65 * 10^18

        
        // stakingPool.updateUserReward(bob);
        uint256 shares=40;
        uint256 expectedRewardAlice = 5 * 10 * 10**18 + ((6 * 10 * 10**18 * 10)  / shares);
        
        // Bob的预期奖励:
        // 后6个区块: 6 * 10 * 10^18 * (30/40) = 45 * 10^18 (Bob拥有3/4份额)
        uint256 expectedRewardBob =(6 * 10 * 10**18 * 30) / shares;

                // 验证奖励计算
        assertApproxEqRel(stakingPool.earned(alice), expectedRewardAlice, 0.01e18, "Alice's reward should be calculated correctly");
        assertApproxEqRel(stakingPool.earned(bob), expectedRewardBob, 0.01e18, "Bob's reward should be calculated correctly");
    

        vm.prank(alice);
        stakingPool.claim();
        vm.roll(block.number + 1);

        vm.prank(bob);
        stakingPool.claim();
        expectedRewardBob += (1 * 10 * 10**18 * 30) / shares;

        // logPoolInfo();
        // logUserInfo(bob);
        // logPoolInfoNum(1);
        // logPoolInfoNum(6);
        // logPoolInfoNum(12);


        assertEq(token.balanceOf(alice), expectedRewardAlice, "Alice should receive correct reward tokens");
        assertEq(token.balanceOf(bob), expectedRewardBob, "Bob should receive correct reward tokens");
        



    }
    
    // 测试通过receive函数质押ETH
    function testReceiveFunction() public {
        uint256 stakeAmount = 10 ether;
        
        // 直接发送ETH到合约
        vm.prank(alice);
        (bool success, ) = address(stakingPool).call{value: stakeAmount}("");
        
        // 检查质押是否成功
        assertTrue(success, "Direct ETH transfer should succeed");
        assertEq(stakingPool.balanceOf(alice), stakeAmount, "Alice's staked balance should be correct");
        assertEq(stakingPool.totalStaked(), stakeAmount, "Total staked should be updated");
    }
    
    // 测试奖励计算边缘情况
    function testEdgeCases() public {
        // 没有质押时的奖励
        assertEq(stakingPool.earned(alice), 0, "Earned should be 0 when no stake");
        
        // 质押0 ETH (应该失败)
        vm.expectRevert("Cannot stake 0");
        vm.prank(alice);
        stakingPool.stake{value: 0}();
        
        // 取消质押0 ETH (应该失败)
        vm.expectRevert("Cannot unstake 0");
        vm.prank(alice);
        stakingPool.unstake(0);
        
        // 取消质押过多 (应该失败)
        vm.expectRevert("Insufficient balance");
        vm.prank(alice);
        stakingPool.unstake(1 ether);
    }
    
    // 测试在更新池后进行质押
    function testStakeAfterPoolUpdate() public {
        // 推进一些区块
        vm.roll(block.number + 5);
        
        // Alice质押10 ETH
        vm.prank(alice);
        stakingPool.stake{value: 10 ether}();
        // 推进10个区块   
        vm.roll(block.number + 10); //***发现Bug, 当两次推进10个区块时，只推进了一次

        // 计算预期奖励: 10个区块 * 每区块10个代币 * 10^18
        uint256 expectedReward = 10 * 10 * 10**18;

        // logPoolInfo();
        // logUserInfo(alice);
        
        // 检查奖励
        assertEq(stakingPool.earned(alice), expectedReward, "Earned reward should be calculated correctly");
    }
}