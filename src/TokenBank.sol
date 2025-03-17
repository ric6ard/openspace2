// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface AutomationCompatibleInterface {
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);
    function performUpkeep(bytes calldata performData) external;
}
contract TokenBank is Ownable {
    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(address => uint256)) private balances;

    // uint256 upkeepLimit = 100 ether;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event UpkeepPerformed(address indexed token, address indexed admin, uint256 amount);

    constructor()Ownable(msg.sender) {
        // 部署者为管理员
    }

    function addToken(address token) external onlyOwner {
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function removeToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    function deposit(address token, uint256 amount) public {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        balances[token][msg.sender] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function permitDeposit(
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(supportedTokens[token], "Token not supported");
        IERC20Permit(token).permit(msg.sender, address(this), amount, deadline, v, r, s);
        deposit(token, amount);
    }

    function depositWithPermit2() public {
        // TODO
    }


    function withdraw(address token, uint256 amount) public {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        require(balances[token][msg.sender] >= amount, "Insufficient balance");

        balances[token][msg.sender] -= amount;
        require(IERC20(token).transfer(msg.sender, amount), "Token transfer failed");

        emit Withdrawal(msg.sender, token, amount);
    }

    function balanceOf(address token, address user) public view returns (uint256) {
        return balances[token][user];
    }

    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        (address token, uint256 limit) = abi.decode(checkData, (address, uint256));
        upkeepNeeded = IERC20(token).balanceOf(address(this)) > limit;
        performData = abi.encode(token, limit);
    }

    function performUpkeep(bytes calldata performData) external {
        (address token, uint256 limit) = abi.decode(performData, (address, uint256));
        address admin = owner();
        uint amount = limit/2;
        require(IERC20(token).balanceOf(address(this)) > limit , "Upkeep not needed");
        require(IERC20(token).transfer(admin, amount), "Token transfer failed");

        emit UpkeepPerformed(token, admin, amount);
    }
}