// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LLCToken2612,ITokenReceiver} from "./LLCToken2612.sol";
import "./MyERC721.sol";

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

contract AirdropMerkleNFTMarket is Ownable, Multicall {
    LLCToken2612 public token;
    MyERC721 public nft;      
    bytes32 public merkleRoot;         // Merkle root for whitelist verification
    mapping(uint256 => uint256) public nftPrices;  // NFT tokenId => price in tokens
    mapping(uint256 => address) public nftListings; // NFT tokenId => seller

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTClaimed(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event MerkleRootUpdated(bytes32 newRoot);

    constructor(LLCToken2612 _token, MyERC721 _nft,bytes32 _merkleRoot) Ownable(msg.sender) {
        token = _token;
        nft = _nft;
        merkleRoot = _merkleRoot;
    }

    // List NFT for sale
    function listNFT(uint256 tokenId, uint256 price) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(nft.getApproved(tokenId) == address(this) || 
                nft.isApprovedForAll(msg.sender, address(this)), 
                "Market not approved");
        nftListings[tokenId] = msg.sender;
        nftPrices[tokenId] = price;
        
        emit NFTListed(tokenId, msg.sender, price);
    }

    // Authorize token spending via permit (to be called via multicall)
    function permitPrePay(uint256 amount,uint256 deadline,uint8 v,bytes32 r,bytes32 s
    ) external {
        token.permit(msg.sender, address(this), amount, deadline, v, r, s);
    }

    // Claim NFT using whitelist discount (to be called via multicall)
    function claimNFT(uint256 tokenId,uint256 amount,bytes32[] calldata merkleProof) external {
        address seller = nftListings[tokenId];
        require(seller != address(0), "NFT not listed");
        // Verify whitelist status via Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, leaf),
            "Not in whitelist"
        );
        // Calculate discounted price (50% off for whitelisted users)
        uint256 fullPrice = nftPrices[tokenId];
        uint256 discountedPrice = fullPrice / 2;
        require(amount >= discountedPrice, "Insufficient payment");

        // Transfer tokens from buyer to seller
        require(
            token.transferFrom(msg.sender, seller, discountedPrice),
            "Token transfer failed"
        );

        // Transfer NFT from seller to buyer
        nft.safeTransferFrom(seller, msg.sender, tokenId);

        // Clean up listing
        delete nftListings[tokenId];
        delete nftPrices[tokenId];

        emit NFTClaimed(tokenId, msg.sender, discountedPrice);
    }

    // Update Merkle root (only owner)
    function updateMerkleRoot(bytes32 _newRoot) external onlyOwner {
        merkleRoot = _newRoot;
        emit MerkleRootUpdated(_newRoot);
    }

    // Get NFT price with discount applied if whitelisted
    function getPrice(uint256 tokenId, bytes32[] calldata merkleProof) 
        external 
        view 
        returns (uint256) 
    {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool isWhitelisted = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        
        uint256 fullPrice = nftPrices[tokenId];
        return isWhitelisted ? fullPrice / 2 : fullPrice;
    }
}