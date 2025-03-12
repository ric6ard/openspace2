// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

interface ITokenReceiver {
    function tokensReceived(address from, uint256 amount, bytes calldata data) external;
}

contract RNT is ERC20, ERC20Permit {
    // 初始供应量，可以根据需要调整
    uint256 constant INITIAL_SUPPLY = (10**9) * (10**18); // 1 billion tokens with 18 decimals

    constructor() ERC20("RNTToken", "RNT") ERC20Permit("LLC Token EIP2612") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
