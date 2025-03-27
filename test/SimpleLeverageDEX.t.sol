// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/SimpleLeverageDEX.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 创建测试用USDC代币
contract TestUSDC is ERC20 {
    constructor() ERC20("Test USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract SimpleLeverageDEXTest is Test {
    SimpleLeverageDEX dex;
    TestUSDC usdc;
    address alice = address(0x1);
    address bob = address(0x2);
    
    function setUp() public {
        // 部署合约
        usdc = new TestUSDC();
        dex = new SimpleLeverageDEX(1000 ether, 2000000 ether); // 初始价格 2000 USDC/ETH
        dex.setUSDC(address(usdc));  // 使用新的setter函数

        // 给测试账户转账USDC
        usdc.mint(alice, 10000 ether);
        usdc.mint(bob, 10000 ether);
        // 给DEX合约一些USDC
        usdc.mint(address(dex), 1000000 ether);

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    function test_OpenLongPosition() public {
        // 设置Alice账户
        vm.startPrank(alice);
        usdc.approve(address(dex), type(uint256).max);

        // 开多仓：1000 USDC保证金，5倍杠杆
        dex.openPosition(1000 ether, 5, true);

        // 验证仓位信息
        (uint256 margin, uint256 borrowed, int256 position) = dex.positions(alice);
        assertEq(margin, 1000 ether, "Incorrect margin");
        assertEq(borrowed, 4000 ether, "Incorrect borrowed amount");
        assertTrue(position > 0, "Position should be positive for long");

        vm.stopPrank();
    }

    function test_OpenShortPosition() public {
        vm.startPrank(bob);
        usdc.approve(address(dex), type(uint256).max);

        // 开空仓：1000 USDC保证金，3倍杠杆
        dex.openPosition(1000 ether, 3, false);

        // 验证仓位信息
        (uint256 margin, uint256 borrowed, int256 position) = dex.positions(bob);
        assertEq(margin, 1000 ether, "Incorrect margin");
        assertEq(borrowed, 2000 ether, "Incorrect borrowed amount");
        assertTrue(position < 0, "Position should be negative for short");

        vm.stopPrank();
    }

    function test_ClosePosition() public {
        // 开仓
        vm.startPrank(alice);
        usdc.approve(address(dex), type(uint256).max);
        dex.openPosition(1000 ether, 5, true);
        
        // 记录关仓前的余额
        uint256 balanceBefore = usdc.balanceOf(alice);
        
        // 关仓
        dex.closePosition(alice);
        // 验证仓位已清空
        (, , int256 position) = dex.positions(alice);
        assertEq(position, 0, "Position should be closed");
        
        // 验证资金已返还
        assertTrue(
            usdc.balanceOf(alice) >= balanceBefore, 
            "Should receive funds back"
        );
        
        vm.stopPrank();
    }

    function test_Liquidation() public {
        // 开仓
        vm.startPrank(alice);
        usdc.approve(address(dex), type(uint256).max);
        dex.openPosition(1000 ether, 5, true);
        vm.stopPrank();

        // 改变价格使仓位可被清算
        // 假设bob过来交易使价格下跌到18%
        vm.startPrank(bob);
        usdc.approve(address(dex), type(uint256).max);
        dex.openPosition(2000 ether, 100, false);
        // 计算Alice的PnL
        // int pnl = dex.calculatePnL(alice); // 更新PnL
        // Bob尝试清算Alice的仓位
        // vm.prank(bob);
        dex.liquidatePosition(alice);
        vm.stopPrank();
        // 验证Bob的余额
        uint256 bobBalance = usdc.balanceOf(bob);
        assertTrue(bobBalance > 0, "Bob should receive funds from liquidation");

        // 验证仓位已被清算
        (,, int256 position) = dex.positions(alice);
        assertEq(position, 0, "Position should be liquidated");
    }

    function test_PnLCalculation() public {
        // 开仓
        vm.startPrank(alice);
        usdc.approve(address(dex), type(uint256).max);
        dex.openPosition(1000 ether, 5, true);
        
        // 获取初始PnL
        int256 initialPnL = dex.calculatePnL(alice);
        
        // 修改价格
        uint256 newETHAmount = dex.vETHAmount() * 120 / 100;  // ETH价格上涨20%
        vm.store(
            address(dex),
            bytes32(uint256(1)), // vETHAmount的存储槽
            bytes32(newETHAmount)
        );
        
        // 验证PnL变化
        int256 newPnL = dex.calculatePnL(alice);
        assertTrue(newPnL > initialPnL, "PnL should increase for long position");
        
        vm.stopPrank();
    }

    function test_RevertWhen_LiquidatingHealthyPosition() public {
        // 假设 Bob 开了一个健康的仓位
        vm.startPrank(bob);
        usdc.approve(address(dex), type(uint256).max);
        dex.openPosition(1000 ether, 3, false);
        vm.stopPrank();

        // Alice 尝试清算 Bob 的健康仓位，应该失败
        vm.startPrank(alice);
        vm.expectRevert("PnL is not enough to liquidate"); // 假设合约中有这样的错误消息
        dex.liquidatePosition(bob);
        vm.stopPrank();
    }

    receive() external payable {}
}