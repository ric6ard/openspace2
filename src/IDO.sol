// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IDO {
    address public owner;
    IERC20 public token;
    uint256 public tokenAmount; // 代币预售数量
    uint256 public targetEth; // in wei 目标ETH
    uint256 public maxEth; // in wei 
    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalRaised; // in wei 总共筹集的ETH
    uint8 public decimals;
    mapping(address => uint256) public userContributions; // in wei 用户的ETH贡献
    mapping(address => bool) public claimed; // 是否已经领取代币
    bool public isFinalized; // 是否已经结束
    bool public isPresaleInitialized; // 是否已经初始化

    event Contribution(address indexed contributor, uint256 amount);
    event Withdrawal(address indexed withdrawer, uint256 amount);
    event PresaleFinalized();
    event TokensClaimed(address indexed claimer, uint256 tokenAmount);
    event EthWithdrawn(address indexed withdrawer, uint256 amount);

    error OnlyOwner(); // 只有合约部署者可以调用
    error PresaleAlreadyInitialized(); // 预售已经初始化
    error InvalidTimeSettings(); // 时间设置错误
    error TargetGreaterThanMax(); // 目标ETH大于最大ETH
    error InvalidTokenAmount(); // 无效的代币数量
    error InvalidTokenAddress(); // 无效的代币地址
    error PresaleNotInitialized(); // 预售未初始化
    error PresaleNotActive(); // 预售未开始或已结束
    error PresaleAlreadyFinalized(); // 预售已经结束
    error ContributionExceedsMaxLimit(); // 贡献超过最大限制
    error PresaleNotEnded(); // 预售未结束
    error PresaleNotFinalized(); // 预售未结束
    error PresaleSuccessful(); // 预售成功
    error NoContributionToWithdraw(); // 没有贡献可以提取
    error RefundFailed(); // 退款失败
    error PresaleDidNotMeetTargets(); // 预售未达到目标
    error InsufficientTokensTransferred(); // 代币转账不足
    error NoContributionToClaim(); // 没有贡献可以领取
    error TokensAlreadyClaimed(); // 代币已经领取
    error WithdrawalFailed(); // 提现失败
    error UseContributeFunction(); // 使用Contribute函数

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function getDecimalMultiplier() private view returns (uint256) {
        return 10 ** decimals;
    }

    function startPresale(
        address _token,
        uint256 _tokenAmount,
        uint256 _targetEth,
        uint256 _maxEth,
        uint256 _startTime,
        uint256 _endTime,
        uint8 _decimals
    ) external onlyOwner {
        if (isPresaleInitialized) revert PresaleAlreadyInitialized();
        if (_startTime > _endTime) revert InvalidTimeSettings();
        if (_targetEth > _maxEth) revert TargetGreaterThanMax();
        if (_tokenAmount == 0) revert InvalidTokenAmount(); 
        if (_token == address(0)) revert InvalidTokenAddress();

        token = IERC20(_token);
        tokenAmount = _tokenAmount;
        targetEth = _targetEth;
        maxEth = _maxEth;
        startTime = _startTime;
        endTime = _endTime;
        decimals = _decimals;
        totalRaised = 0;
        isPresaleInitialized = true;
        // token.approve(spender, value);
        token.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function contribute() external payable {
        if (!isPresaleInitialized) revert PresaleNotInitialized();
        if (block.timestamp < startTime || block.timestamp >= endTime) revert PresaleNotActive();
        if (isFinalized) revert PresaleAlreadyFinalized();
        if (totalRaised + msg.value > maxEth) revert ContributionExceedsMaxLimit();

        userContributions[msg.sender] += msg.value;
        totalRaised += msg.value;
        emit Contribution(msg.sender, msg.value);
    }

    function withdrawContribution() external {
        if (block.timestamp < endTime) revert PresaleNotEnded();
        if (totalRaised >= targetEth) revert PresaleSuccessful();
        if (userContributions[msg.sender] == 0) revert NoContributionToWithdraw();
        if (isFinalized) revert PresaleAlreadyFinalized();

        uint256 amount = userContributions[msg.sender];
        userContributions[msg.sender] = 0;
        totalRaised -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert RefundFailed();
        emit Withdrawal(msg.sender, amount);
    }

    function finalizePresale() external onlyOwner {
        if (block.timestamp < endTime) revert PresaleNotEnded();
        if (totalRaised < targetEth || totalRaised > maxEth) revert PresaleDidNotMeetTargets();
        if (isFinalized) revert PresaleAlreadyFinalized();
        if (token.balanceOf(address(this)) < tokenAmount) revert InsufficientTokensTransferred();

        isFinalized = true;
        emit PresaleFinalized();
    }

    function claimTokens() external {
        if (!isFinalized) revert PresaleNotFinalized();
        if (userContributions[msg.sender] == 0) revert NoContributionToClaim();
        if (claimed[msg.sender]) revert TokensAlreadyClaimed();

        uint256 tokensClaimable = tokenAmount * userContributions[msg.sender] / totalRaised ;
        // uint256 amountToTransfer = tokenAmount * getDecimalMultiplier();
        token.transfer(msg.sender, tokensClaimable);
        claimed[msg.sender] = true;
        emit TokensClaimed(msg.sender, tokensClaimable);
    }

    function withdrawEth() external onlyOwner {
        if (!isFinalized) revert PresaleNotFinalized();

        uint256 amount = totalRaised;
        totalRaised = 0;
        (bool success,) = owner.call{value: amount}("");
        if (!success) revert WithdrawalFailed();
        emit EthWithdrawn(owner, amount);
    }

    receive() external payable {
        revert UseContributeFunction();
    }
}