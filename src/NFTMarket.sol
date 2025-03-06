// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LLCToken2612,ITokenReceiver} from "./LLCToken2612.sol";
import "./MyERC721.sol";

contract NFTMarket is ITokenReceiver {
    LLCToken2612 public token;
    MyERC721 public nft;

    struct Listing {
        uint256 price;
        address seller;
    }

    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed tokenId, uint256 price, address indexed seller);
    event Purchased(uint256 indexed tokenId, uint256 price, address indexed buyer);

    address public admin;
    bytes32 public DOMAIN_SEPARATOR;

    constructor(LLCToken2612 _token, MyERC721 _nft) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
        token = _token;
        nft = _nft;
        admin = msg.sender;
    }

    function permitBuy(uint256 tokenId,uint256 deadline, uint8 v, bytes32 r, bytes32 s, uint deadline2,uint8 v2, bytes32 r2, bytes32 s2) public {
        Listing memory listing = listings[tokenId];
        require(isPermitted(msg.sender, tokenId, deadline, v, r, s), "Not permitted");
        permitDeposit(msg.sender, address(this), listing.price, deadline2, v2, r2, s2);
        executeOrder(msg.sender, listing.seller, tokenId, listing.price);
    }

    function isPermitted(address buyer, uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
        bytes32 PERMIT_TYPEHASH = keccak256("Permit(address buyer, uint256 tokenId, uint256 deadline)");
        bytes32 hash = keccak256(abi.encode(PERMIT_TYPEHASH, buyer, tokenId, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hash));
        address signer = ecrecover(digest, v, r, s);
        return signer == admin && block.timestamp <= deadline;
    }

    function permitDeposit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        token.permit(owner, spender, amount, deadline, v, r, s);
        token.approve(spender, amount);
    }
    
    function executeOrder(address buyer, address seller, uint256 tokenId, uint256 price) public {
        nft.transferFrom(seller, buyer, tokenId);
        token.transferFrom(buyer, seller, price);
        delete listings[tokenId];
        emit Purchased(tokenId, price, buyer);
    }

    function canBuy(uint256 tokenId, address buyer) public view returns (bool) {
        Listing memory listing = listings[tokenId];
        return listing.price > 0 && buyer != listing.seller;
    }

    function list(uint256 tokenId, uint256 price) public {
        require(nft.ownerOf(tokenId) == msg.sender, "Only NFT owner can list");
        nft.setApprovalForAll(address(this), true);
        listings[tokenId] = Listing(price, msg.sender);
        nft.setApprovalForAll(address(this), true);
        emit Listed(tokenId, price, msg.sender);
    }

    function buyNFT(address buyer, uint256 tokenId) public {
        Listing memory listing = listings[tokenId];
        require(listing.price > 0, "NFT is not listed for sale");
        require(buyer != listing.seller, "Seller cannot buy own NFT");

        uint256 price = listing.price;
        address seller = listing.seller;

        require(token.balanceOf(buyer) >= price, "Buyer does not have enough tokens");

        nft.transferFrom(seller, buyer, tokenId);
        // nft.safeTransferFrom(seller, buyer, tokenId);
        token.transferFrom(buyer, seller, price);
        //token.transfer(seller, price);
        delete listings[tokenId];
        emit Purchased(tokenId, price, buyer);
    }

    function tokensReceived(address from, uint256 amount, bytes calldata data) external {
        require(msg.sender == address(token), "Unauthorized token");
        uint256 tokenId = abi.decode(data, (uint256));
        require(tokenId > 0, "Invalid Token ID");
        Listing memory listing = listings[tokenId];
        require(listing.price > 0, "NFT is not listed for sale");
        buyNFT(from, tokenId);
        if (amount > listing.price) {
            token.transfer(from, amount - listing.price);
        }
    }
}
