// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/TokenBank.sol";
import "../src/LLCToken2612.sol";

contract TokenBankTest is Test {
    TokenBank private tokenBank;
    LLCToken2612 private token;
    address private owner;
    address user;
    uint256 privateKey;


    function setUp() public {
        owner = address(this);

        // (user, privateKey) = makeAddrAndKey("user");
        privateKey = vm.envUint("PRIVATE_KEY");
        user = vm.addr(privateKey);

        token = new LLCToken2612();
        tokenBank = new TokenBank();
        tokenBank.addToken(address(token));
        token.transfer(user, 1000 * 10**18);
    }

    function testDeposit1() public {
        vm.startPrank(user);
        token.approve(address(tokenBank), 500 * 10**18);
        tokenBank.deposit(address(token), 500 * 10**18);
        assertEq(tokenBank.balanceOf(address(token), user), 500 * 10**18);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);
        token.approve(address(tokenBank), 500 * 10**18);
        tokenBank.deposit(address(token), 500 * 10**18);
        tokenBank.withdraw(address(token), 200 * 10**18);
        assertEq(tokenBank.balanceOf(address(token), user), 300 * 10**18);
        vm.stopPrank();
    }

    function testPermitDeposit() public {
        uint256 amount = 500 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        uint8 v;
        bytes32 r;
        bytes32 s;

        // 生成离线签名
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(tokenBank),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (v, r, s) = vm.sign(privateKey, digest);

        vm.startPrank(user);
        tokenBank.permitDeposit(address(token), amount, deadline, v, r, s);
        assertEq(tokenBank.balanceOf(address(token), user), amount);
        vm.stopPrank();
    }

    function testAddAndRemoveToken() public {
        address newToken = address(0x5678);
        tokenBank.addToken(newToken);
        assertTrue(tokenBank.supportedTokens(newToken));

        tokenBank.removeToken(newToken);
        assertFalse(tokenBank.supportedTokens(newToken));
    }
}
