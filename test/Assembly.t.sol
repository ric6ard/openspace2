// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Assembly.sol";

contract MyWalletTest is Test {
    MyWallet public wallet;
    address public owner;
    address public newOwner;

    function setUp() public {
        owner = address(this);
        newOwner = address(0x123);
        wallet = new MyWallet("Test Wallet");
    }

    function testInitialOwner() public view {
        assertEq(wallet.owner(), owner);
    }

    function testTransferOwnership() public {
        wallet.transferOwernship(newOwner);
        assertEq(wallet.owner(), newOwner);
    }

    function testSetOwnerByAssembly() public {
        wallet.setOwnerByAssembly(newOwner);
        assertEq(wallet.owner(), newOwner);
    }

    function testGetOwnerByAssembly() public {
        wallet.setOwnerByAssembly(newOwner);
        address retrievedOwner = wallet.getOwnerByAssembly();
        assertEq(retrievedOwner, newOwner);
    }

    function testTransferOwnershipReverts() public {
        vm.expectRevert("New owner is the zero address");
        wallet.transferOwernship(address(0));

        vm.expectRevert("New owner is the same as the old owner");
        wallet.transferOwernship(owner);
    }

    function testSetOwnerByAssemblyReverts() public {
        vm.expectRevert("New owner is the zero address");
        wallet.setOwnerByAssembly(address(0));

        vm.expectRevert("New owner is the same as the old owner");
        wallet.setOwnerByAssembly(owner);
    }
}