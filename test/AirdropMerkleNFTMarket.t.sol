// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/AirdropMerkleNFTMarket.sol";
import "../src/LLCToken2612.sol";
import "../src/MyERC721.sol";

contract AirdropMerkleNFTMarketTest is Test {
    AirdropMerkleNFTMarket market;
    LLCToken2612 token;
    MyERC721 nft;

    uint256 buyerPrivateKey = 0xa11ce;
    
    address owner = address(1);
    address seller = address(2);
    address buyer = vm.addr(buyerPrivateKey);
    address nonWhitelisted = address(4);
    
    uint256 tokenId = 1;
    uint256 price = 100 ether;
    bytes32 merkleRoot;
    bytes32[] merkleProof;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy token and NFT
        token = new LLCToken2612();
        nft = new MyERC721();
        
        // Create merkle root (simplified for testing)
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(buyer));
        merkleRoot = leaves[0]; // Simplified merkle tree for testing
        
        // Deploy market contract
        market = new AirdropMerkleNFTMarket(token, nft, merkleRoot);
        
        // Set up test scenario
        nft.mint(seller, "tokenURI");
        token.transfer(buyer, 1000 ether);
        
        vm.stopPrank();
        
        // Setup simple merkle proof for testing
        merkleProof = new bytes32[](0);
    }

    function buyerSignature(uint256 amount, uint256 deadline) public view returns (uint8, bytes32, bytes32) {
        bytes32 PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 hash = keccak256(abi.encode(PERMIT_TYPEHASH, buyer, address(market), amount, 0, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), hash));
        return vm.sign(buyerPrivateKey, digest);
    }

    function testListNFT() public {
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, price);
        vm.stopPrank();
        
        assertEq(market.nftPrices(tokenId), price);
        assertEq(market.nftListings(tokenId), seller);
    }
    
    function test_RevertIf_ListNFTNotOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert("Not NFT owner");
        market.listNFT(tokenId, price);
        vm.stopPrank();
    }
    
    function test_RevertIf_ListNFTNotApproved() public {
        vm.startPrank(seller);
        vm.expectRevert("Market not approved");
        market.listNFT(tokenId, price);
        vm.stopPrank();
    }
    
    function testPermitPrePay() public {
        (uint8 v, bytes32 r, bytes32 s) = buyerSignature(100 ether, 1800000000);
        vm.prank(buyer);
        market.permitPrePay(100 ether, 1800000000, v, r, s);
        // Check ownership and balances
        assertEq(token.allowance(buyer, address(market)), 100 ether);
    }

    function testClaimNFT() public {
        // List NFT first
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, price);
        vm.stopPrank();
        
        // Approve token spending
        vm.startPrank(buyer);
        token.approve(address(market), price);
        
        // Claim NFT
        market.claimNFT(tokenId, price/2, merkleProof);
        vm.stopPrank();
        
        // Verify ownership and balances
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(token.balanceOf(seller), price/2);
        assertEq(market.nftListings(tokenId), address(0)); // Listing should be removed
    }
    
    function testGetPrice() public {
        // List NFT
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, price);
        vm.stopPrank();
        
        // Check price for whitelisted user
        vm.prank(buyer);
        assertEq(market.getPrice(tokenId, merkleProof), price/2);
        
        // Check price for non-whitelisted user
        vm.prank(nonWhitelisted);
        assertEq(market.getPrice(tokenId, merkleProof), price);
    }
    
    function testUpdateMerkleRoot() public {
        bytes32 newRoot = keccak256("new root");
        
        vm.prank(owner);
        market.updateMerkleRoot(newRoot);
        
        assertEq(market.merkleRoot(), newRoot);
    }
    
    function test_RevertIf_UpdateMerkleRootNotOwner() public {
        bytes32 newRoot = keccak256("new root");
        
        vm.prank(buyer);
        vm.expectRevert();
        market.updateMerkleRoot(newRoot);
    }
    
    function testMulticall() public {
        // List NFT first
        vm.startPrank(seller);
        nft.approve(address(market), tokenId);
        market.listNFT(tokenId, price);
        vm.stopPrank();
        
        // Create permit signature
        vm.startPrank(buyer);
        (uint8 v, bytes32 r, bytes32 s) = buyerSignature(price/2, 1800000000);
        
        // Create multicall data
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            market.permitPrePay.selector,
            price/2,
            1800000000,
            v,
            r,
            s  
        );
        calls[1] = abi.encodeWithSelector(
            market.claimNFT.selector,
            tokenId,
            price/2,
            merkleProof
        );
        
        // Execute multicall
        market.multicall(calls);
        vm.stopPrank();
        
        // Verify transaction worked
        assertEq(nft.ownerOf(tokenId), buyer);
    }
}