//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// interface IERC20 {
//     function transferFrom(address sender, address recipient, uint256 amount) external returns(bool);
//     function transfer(address recipient, uint256 amount) external returns(bool);
//     function balanceOf(address account) external view returns(uint256);
// }
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingMining {
    struct Batch {
        uint256 amount;
        uint256 creationTime;
    }

    address public owner;
    address public RNT;
    uint256 public totalStakedRNT;
    uint256 public rewardRNT;

    mapping(address => uint256) public stakedAmount;
    mapping(address => uint256) public lastClaimTime;
    mapping(address => Batch[]) public userEsRNT;

    uint256 constant SECONDS_PER_DAY = 86400;
    uint256 constant VESTING_PERIOD = 30 days;

    constructor(address _RNT) {
        owner = msg.sender;
        RNT = _RNT;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(RNT).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        stakedAmount[msg.sender] += amount;
        totalStakedRNT += amount;
    }

    function unstake(uint256 amount) external {
        require(amount > 0 && amount <= stakedAmount[msg.sender], "Invalid amount");
        require(IERC20(RNT).transfer(msg.sender, amount), "Transfer failed");
        stakedAmount[msg.sender] -= amount;
        totalStakedRNT -= amount;
    }

    function claimRewards() external {
        uint256 currentTime = block.timestamp;
        uint256 timeElapsed = currentTime - lastClaimTime[msg.sender];
        uint256 newEsRNTEarned = stakedAmount[msg.sender] * timeElapsed / SECONDS_PER_DAY;
        userEsRNT[msg.sender].push(Batch({amount: newEsRNTEarned, creationTime: currentTime}));
        lastClaimTime[msg.sender] = currentTime;
    }

    function exchangeEsRNTForRNT(uint256 amount) external {
        uint256 currentTime = block.timestamp;
        uint256 totalVestedRNT = 0;
        uint256 remainingAmountToExchange = amount;

        for(uint256 i = 0; i < userEsRNT[msg.sender].length; i++) {
            Batch storage batch = userEsRNT[msg.sender][i];
            if(batch.amount == 0) continue;
            if(batch.amount <= remainingAmountToExchange) {
                uint256 vestedSeconds = currentTime > batch.creationTime + VESTING_PERIOD 
                    ? VESTING_PERIOD 
                    : currentTime - batch.creationTime;
                uint256 vestedFraction = (vestedSeconds * 1e18) / VESTING_PERIOD;
                uint256 batchVestedRNT = batch.amount * vestedFraction / 1e18;
                totalVestedRNT += batchVestedRNT;
                remainingAmountToExchange -= batch.amount;
                batch.amount = 0;
            } else {
                uint256 partialAmount = remainingAmountToExchange;
                uint256 vestedSeconds = currentTime > batch.creationTime + VESTING_PERIOD 
                    ? VESTING_PERIOD 
                    : currentTime - batch.creationTime;
                uint256 vestedFraction = (vestedSeconds * 1e18) / VESTING_PERIOD;
                uint256 partialVestedRNT = partialAmount * vestedFraction / 1e18;
                totalVestedRNT += partialVestedRNT;
                batch.amount -= partialAmount;
                remainingAmountToExchange = 0;
                break;
            }
        }

        require(rewardRNT >= totalVestedRNT, "Insufficient reward RNT");
        rewardRNT -= totalVestedRNT;
        require(IERC20(RNT).transfer(msg.sender, totalVestedRNT), "Transfer failed");
    }

    function depositRewardRNT(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(RNT).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        rewardRNT += amount;
    }

    function min(uint256 a, uint256 b) internal pure returns(uint256) {
        return a < b ? a : b;
    }
}