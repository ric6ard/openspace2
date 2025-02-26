// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenBank is Ownable {
    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(address => uint256)) private balances;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    constructor()Ownable(msg.sender) {
        // 部署者为管理员
        // transferOwnership(msg.sender);
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
}