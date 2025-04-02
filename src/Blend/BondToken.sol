// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BondToken is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public maturityDate;
    address public platform;

    constructor(string memory _name, string memory _symbol, uint256 _maturityDate, address _platform) {
        name = _name;
        symbol = _symbol;
        maturityDate = _maturityDate;
        platform = _platform;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == platform, "Only platform");
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function burn(uint256 amount) external {
        require(msg.sender == platform, "Only platform");
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
    }
}