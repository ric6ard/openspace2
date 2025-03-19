// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/NFTMarket.sol";
import "../src/MyERC721.sol";
import "../src/LLCToken2612.sol";

contract NFTMarketTest is Test {
    NFTMarket market;
    MyERC721 nft;
    LLCToken2612 token;
    address seller;
    address buyer;

    function setUp() public {
        token = new LLCToken2612();
        nft = new MyERC721();
        market = new NFTMarket(token, nft);
        seller = address(0x1);
        buyer = address(0x2);
        token.transfer(seller, 10000 ether);
        token.transfer(buyer, 10000 ether);

    }

    function testListNFT() public {
        vm.startPrank(seller);
        nft.mint(seller, "tokenURI");
        nft.approve(address(market), 1);
        market.list(1, 1000 ether);
        (uint256 price, address sellerAddress) = market.listings(1);
        assertEq(price, 1000 ether);
        assertEq(sellerAddress, seller);
        vm.stopPrank();
    }

    function testBuyNFT() public {
        vm.startPrank(seller);
        nft.mint(seller, "tokenURI");
        nft.approve(address(market), 1);
        market.list(1, 1000 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 1000 ether);
        market.buyNFT(buyer, 1);
        assertEq(nft.ownerOf(1), buyer);
        assertEq(token.balanceOf(seller), 11000 ether);
        assertEq(token.balanceOf(buyer), 9000 ether);
        vm.stopPrank();
    }

    function testBuyOwnNFT() public {
        vm.startPrank(seller);
        nft.mint(seller, "tokenURI");
        nft.approve(address(market), 1);
        market.list(1, 1000 ether);
        token.approve(address(market), 1000 ether);
        vm.expectRevert("Seller cannot buy own NFT");
        market.buyNFT(seller, 1);
        vm.stopPrank();
    }

    function testBuyNFTTwice() public {
        vm.startPrank(seller);
        nft.mint(seller, "tokenURI");
        nft.approve(address(market), 1);
        market.list(1, 1000 ether);
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 1000 ether );
        market.buyNFT(buyer, 1);
        vm.expectRevert("NFT is not listed for sale");
        market.buyNFT(buyer, 1);
        vm.stopPrank();
    }

    function testBuyNFTWithExcessTokens() public {
        vm.startPrank(seller);
        nft.mint(seller, "tokenURI");
        nft.approve(address(market), 1);
        market.list(1, 1000 ether );
        vm.stopPrank();

        vm.startPrank(buyer);
        token.approve(address(market), 2000 ether );
        market.buyNFT(buyer, 1);
        assertEq(nft.ownerOf(1), buyer);
        assertEq(token.balanceOf(seller), 11000 ether );
        assertEq(token.balanceOf(buyer), 9000 ether );
        vm.stopPrank();
    }

    function testFuzzyListingAndBuying(address randomSeller, address randomBuyer, uint price) public {
        vm.assume(price > 0.01 ether && price < 10000 ether);
        vm.assume(randomSeller != address(0) && randomBuyer != address(0) && randomSeller != randomBuyer);
        // vm.assume(randomBuyer.code.length >0);
        // Transfer tokens to randomSeller and randomBuyer
        // token.transfer(randomSeller, price);

        vm.startPrank(randomSeller);
        nft.mint(randomSeller, "tokenURI");
        nft.approve(address(market), 1);
        market.list(1, price);
        vm.stopPrank();

        token.transfer(randomBuyer, price);
        vm.startPrank(randomBuyer);
        token.approve(address(market), price);
        market.buyNFT(randomBuyer, 1);
        assertEq(nft.ownerOf(1), randomBuyer);
        vm.stopPrank();
    }

    function invariantNoTokenBalanceInMarket() public view {
        uint256 initialBalance = token.balanceOf(address(market));
        assertEq(initialBalance, 0);
    }
}
