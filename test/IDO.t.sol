// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/IDO.sol";
import "../src/LLCToken2612.sol";

contract IDOTest is Test {

    IDO ido;
    address owner = address(0x123);
    address contributor = address(0x456);
    LLCToken2612 public token;

    function setUp() public {
        vm.startPrank(owner);
        ido = new IDO();
        token = new LLCToken2612();
        token.approve(address(ido), 1_000_000 ether);
        console.log(token.balanceOf(owner));
        ido.startPresale(
            address(token), // token address
            1_000_000 ether, // token amount
            10 ether, // target ETH
            20 ether, // max ETH
            block.timestamp, // start time
            block.timestamp + 1000, // end time
            18 // decimals
        );
        vm.stopPrank();
    }

    function testStartPresale() public view {
        assertEq(address(ido.token()), address(token));
        assertEq(ido.tokenAmount(), 1_000_000 ether);
        assertEq(ido.targetEth(), 10 ether);
        assertEq(ido.maxEth(), 20 ether);
        assertEq(ido.startTime(), block.timestamp );
        assertEq(ido.endTime(), block.timestamp + 1000);
        assertEq(ido.decimals(), 18);
        assertTrue(ido.isPresaleInitialized());
    }

    function testContribute() public {
        vm.prank(contributor);
        vm.deal(contributor, 5 ether);
        ido.contribute{value: 5 ether}();

        assertEq(ido.userContributions(contributor), 5 ether);
        assertEq(ido.totalRaised(), 5 ether);
    }

    function testWithdrawContribution() public {

        vm.prank(contributor);
        vm.deal(contributor, 5 ether);
        ido.contribute{value: 5 ether}();

        vm.warp(block.timestamp + 1001); // fast forward time to end presale

        vm.prank(contributor);
        ido.withdrawContribution();

        assertEq(ido.userContributions(contributor), 0);
        assertEq(ido.totalRaised(), 0);
    }

    function testFinalizePresale() public {

        vm.prank(contributor);
        vm.deal(contributor, 10 ether);
        ido.contribute{value: 10 ether}();

        vm.warp(block.timestamp + 1001); // fast forward time to end presale

        vm.prank(owner);
        ido.finalizePresale();

        assertTrue(ido.isFinalized());
    }

    function testClaimTokens() public {
        vm.prank(contributor);
        vm.deal(contributor, 10 ether);
        ido.contribute{value: 10 ether}();

        vm.warp(block.timestamp + 1001); // fast forward time to end presale

        vm.prank(owner);
        ido.finalizePresale();

        vm.prank(contributor);
        ido.claimTokens();

        assertEq(token.balanceOf(contributor), 1_000_000 ether);
    }

    function testWithdrawEth() public {
        vm.prank(contributor);
        vm.deal(contributor, 10 ether);
        ido.contribute{value: 10 ether}();

        vm.warp(block.timestamp + 1001); // fast forward time to end presale

        vm.prank(owner);
        ido.finalizePresale();

        vm.prank(owner);
        ido.withdrawEth();

        assertEq(address(owner).balance, 10 ether);
    }

}