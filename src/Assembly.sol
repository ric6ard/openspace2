//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MyWallet {

    string public name;
    mapping (address => bool) approved;
    address public owner;

    modifier auth {
        require (msg.sender == owner, "Not authorized");
        _;
    }

    constructor(string memory _name) {
        name = _name;
        owner = msg.sender;
    } 

    function transferOwernship(address _addr) public auth {
        require(_addr!=address(0), "New owner is the zero address");
        require(owner != _addr, "New owner is the same as the old owner");
        owner = _addr;
    }

    function setOwnerByAssembly(address _addr) public auth {
        require(_addr!=address(0), "New owner is the zero address");
        require(owner != _addr, "New owner is the same as the old owner");
        assembly {
            sstore(owner.slot, _addr)
        }
    }

    function getOwnerByAssembly() public view returns (address) {
        address _owner;
        assembly {
            _owner := sload(owner.slot)
        }
        return _owner;
    }
}
