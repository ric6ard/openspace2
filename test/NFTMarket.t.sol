// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/NFTMarket.sol";
import "../src/LLCToken2612.sol";
import "../src/MyERC721.sol";

contract NFTMarketTest is Test {
    NFTMarket public market;
    LLCToken2612 public token;
    MyERC721 public nft;
    address public admin;
    address public seller;
    address public buyer;

    uint256 public adminPrivateKey;
    uint256 public buyerPrivateKey;

    function setUp() public {
        buyerPrivateKey = 0xa11ce;
        adminPrivateKey = 0xabc123;
        buyer = vm.addr(buyerPrivateKey);
        admin = vm.addr(adminPrivateKey);
        // admin = address(admin);
        seller = address(0x1);
        // buyer = address(buyer);
        vm.startPrank(admin);
        token = new LLCToken2612();
        nft = new MyERC721();

        market = new NFTMarket(token, nft);

        // Mint tokens and NFTs for testing
        token.transfer(buyer, 1000 ether);

        // vm.prank(admin);
        nft.mint(seller, "tokenURI");
        // nft.safeTransferFrom(admin, seller, 1);
        vm.stopPrank();

        // Approve market contract to transfer tokens and NFTs
        vm.prank(buyer);
        token.approve(address(market), 1000 ether);

        vm.prank(seller);
        nft.approve(address(market), 1);
    }

    function testPermitBuy() public {
        // List the NFT
        vm.prank(seller);
        market.list(1, 100 ether);

        // Generate permit signature
        uint256 deadline = 1800000000;
        uint tokenId = 1;
        bytes32 PERMIT_TYPEHASH = keccak256("Permit(address buyer, uint256 tokenId, uint256 deadline)");
        bytes32 hash = keccak256(abi.encode(PERMIT_TYPEHASH,buyer, tokenId, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", market.DOMAIN_SEPARATOR(), hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);

        // Generate permit signature for token approval
        uint256 deadline2 = 1800000000;
        bytes32 PERMIT_TYPEHASH2 = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 hash2 = keccak256(abi.encode(PERMIT_TYPEHASH2, buyer, address(market), 100 ether, 0, deadline2));
        bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), hash2));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(buyerPrivateKey, digest2);

        // Execute permitBuy
        vm.prank(buyer);
        market.permitBuy(tokenId, deadline, v, r, s, deadline2, v2, r2, s2);

        // Check ownership and balances
        assertEq(nft.ownerOf(1), buyer);
        assertEq(token.balanceOf(seller), 100 ether);
        assertEq(token.balanceOf(buyer), 900 ether);
    }
}