// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MyFirstToken.sol";
import "../src/SolidityBank.sol";
import "../src/SimpleMultiSig.sol";
import "../src/LLCToken2612.sol";
import "../src/TokenBank.sol";
import "../src/NFTPersaleFollowing/NFTPersale.sol";
import "../src/Blend/BlendFinance.sol";

contract DeployBlendFinance is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey); //开始广播交易
        new BlendFinance(
            0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            0xE9d2E42129C04f5627f7894aABD422B8a76737aD,
            0xE9d2E42129C04f5627f7894aABD422B8a76737aD
        );
        vm.stopBroadcast();
    }
}

contract DeployOpenSpaceNFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey); //开始广播交易
        new OpenspaceNFT();
        vm.stopBroadcast();
    }
}

contract DeployTokenBank is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey); //开始广播交易
        new TokenBank();
        vm.stopBroadcast();
    }
}

contract DeployLLCToken2612 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey); //开始广播交易
        new LLCToken2612();
        vm.stopBroadcast();
    }
}

contract DeployMyFirstToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey); //开始广播交易
        new MyFirstToken("FakeKKToken", "FKK");
        vm.stopBroadcast();
    }
}

contract DeploySolidityBank is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey); //开始广播交易
        new SolidityBank();
        vm.stopBroadcast();
    }
}

contract DeploySimpleMultiSig is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TEST");
        vm.startBroadcast(deployerPrivateKey);
        address[] memory owners = new address[](2);
        owners[0] = 0x36912Eb785f5A358Fc0EA9Cd0FB87041907B59c5;
        owners[1] = 0xE9d2E42129C04f5627f7894aABD422B8a76737aD;
        new SimpleMultiSig(owners,2);
        vm.stopBroadcast();
    }
}