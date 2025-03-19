//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//编写 StakingPool 合约，实现 Stake 和 Unstake 方法，允许任何人质押ETH来赚钱 KK Token。
//其中 KK Token 是每一个区块产出 10 个，产出的 KK Token 需要根据质押时长和质押数量来公平分配。

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IStaking {
    function stake()  payable external;
    function unstake(uint256 amount) external; 
    function claim() external;
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
}

contract StakingPool is IStaking {
    IToken public token; //KK Token
    uint8 public decimal; //KK Token的小数位数
    uint256 public constant REWARD_PER_BLOCK = 10 ; //每个区块奖励10个KK Token
    uint256 public lastUpdateBlock; //上次更新奖励的区块
    uint256 public totalStaked; //总质押量

    struct UserInfo {
        uint256 userAmount; //用户质押数量
        uint256 userRewardClaimable; //用户可领取的奖励
        uint256 userLastUpdateBlock; //上次计算用户奖励的区块
    }

    mapping(uint256 => uint256) public accumulatedRewardPerWei; //某个block => 每质押一个weiETH的累计奖励(r值)
    mapping(address => UserInfo) public userInfo; //用户信息

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount); 

    constructor(address _token) {
        token = IToken( _token);
        decimal = 18; //假设KK Token的小数位数为18
        lastUpdateBlock = block.number;
    }

    function updatePool() public { //更新池累计奖励
        uint256 currentBlock = block.number;
        if (currentBlock <= lastUpdateBlock || totalStaked == 0) {
            lastUpdateBlock = currentBlock;
            accumulatedRewardPerWei[currentBlock] = 0;
            return;
        }
        uint256 reward = (currentBlock - lastUpdateBlock) * REWARD_PER_BLOCK * (10 ** decimal) ;

        accumulatedRewardPerWei[currentBlock] = accumulatedRewardPerWei[lastUpdateBlock] + (reward / totalStaked);

        lastUpdateBlock = currentBlock;
    }

    function updateUserReward(address userAddress) public { //更新用户奖励
        uint256 currentBlock = block.number;
        UserInfo storage user = userInfo[userAddress];
        
        // 如果是用户第一次质押或者最后更新区块为0，则初始化
        if (user.userLastUpdateBlock == 0) {
            user.userLastUpdateBlock = currentBlock;
            return;
        }
        
        // 确保不会发生下溢
        if (accumulatedRewardPerWei[currentBlock] >= accumulatedRewardPerWei[user.userLastUpdateBlock]) {
            uint256 rewardPerWeiRised = accumulatedRewardPerWei[currentBlock] - accumulatedRewardPerWei[user.userLastUpdateBlock];
            user.userRewardClaimable += user.userAmount * rewardPerWeiRised;
        }
        
        user.userLastUpdateBlock = currentBlock;
        //userInfo[userAddress]=user;
    }

    function stake() payable override external {
        require(msg.value > 0, "Cannot stake 0");
        updatePool();
        updateUserReward(msg.sender);
        totalStaked += msg.value;
        UserInfo storage user = userInfo[msg.sender];
        user.userAmount += msg.value;
        // userInfo[msg.sender].userAmount += msg.value;
        
        emit Stake(msg.sender, msg.value);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "Cannot unstake 0");
        require(userInfo[msg.sender].userAmount >= amount, "Insufficient balance");
        updatePool();
        updateUserReward(msg.sender);
        userInfo[msg.sender].userAmount -= amount;
        totalStaked -= amount;
        payable(msg.sender).transfer(amount);

        emit Unstake(msg.sender, amount);
    }
    function claim() external{
        updatePool();
        updateUserReward(msg.sender);
        uint256 amount = userInfo[msg.sender].userRewardClaimable;
        userInfo[msg.sender].userRewardClaimable = 0;
        token.mint(msg.sender, amount);

        emit Claim(msg.sender, amount);
    }
    function balanceOf(address account) external view returns (uint256){
        return userInfo[account].userAmount;
    }
    function earned(address account) external view returns (uint256) {
        UserInfo storage user = userInfo[account];
        uint256 currentBlock = block.number;
        
        // 如果用户没有质押，直接返回已累计的奖励
        if (user.userAmount == 0) {
            return user.userRewardClaimable;
        }
        
        // 复制用户的已累计奖励
        uint256 pendingReward = user.userRewardClaimable;
        
        // 如果用户的最后更新区块小于合约的最后更新区块
        // 说明用户在这段时间内没有与合约交互，需要计算这段时间的奖励
        if (user.userLastUpdateBlock < lastUpdateBlock) {
            // 计算从用户最后更新到全局最后更新的奖励变化
            uint256 rewardPerWeiDiff = 0;
            // 这里简化处理，假设accumulatedRewardPerWei是连续的
            // 实际应考虑质押量变化的情况
            if (accumulatedRewardPerWei[lastUpdateBlock] > accumulatedRewardPerWei[user.userLastUpdateBlock]) {
                rewardPerWeiDiff = accumulatedRewardPerWei[lastUpdateBlock] - accumulatedRewardPerWei[user.userLastUpdateBlock];
            }
            pendingReward += user.userAmount * rewardPerWeiDiff;
        }
        
        // 计算从全局最后更新到当前区块的奖励
        if (currentBlock > lastUpdateBlock && totalStaked > 0) {
            uint256 newRewards = (currentBlock - lastUpdateBlock) * REWARD_PER_BLOCK * (10 ** decimal);
            uint256 userShare = (user.userAmount * newRewards) / totalStaked;
            pendingReward += userShare;
        }
        
        return pendingReward;
    }

    receive() external payable {
        // this.stake{value: msg.value}();
        require(msg.value > 0, "Cannot stake 0");
        updatePool();
        updateUserReward(msg.sender);
        userInfo[msg.sender].userAmount += msg.value;
        totalStaked += msg.value;

        emit Stake(msg.sender, msg.value);
    }
}