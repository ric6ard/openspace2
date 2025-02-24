// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title A simple decentralized banking smart contract
/// @author v0 Assistant
/// @notice This contract allows users to deposit ETH
contract SolidityBank {
    mapping(address => uint256) public balances;

    event Deposit(address indexed user, uint256 amount);

    /// @notice Allows users to deposit ETH
    function deposit() public  payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Returns the balance of the caller
    /// @return The balance of the caller
    function getBalance() external view returns (uint256) {
        return balances[msg.sender];
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {
        deposit();
    }

    /// @notice Withdraws the caller's balance
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Insufficient balance");
        balances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
}


