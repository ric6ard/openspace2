// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MyDEX/FlashLoan.sol";
import "../src/MyDEX/MyDEX.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UniswapV2Factory} from "../src/MyDEX/UniswapV2Factory.sol"; 
import {UniswapV2Pair} from "../src/MyDEX/UniswapV2Pair.sol";
// import "../src/MyDEX/UniswapV2Factory.sol";
// import "../src/MyDEX/UniswapV2Pair.sol";

contract TestToken is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 1000000 ether); // 初始铸造代币
    }
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract FlashLoanTest is Test {
    FlashLoan flashLoan;
    MyDex dex1;
    MyDex dex2;
    TestToken tokenA;
    TestToken tokenB;
    UniswapV2Factory factory1;
    UniswapV2Factory factory2;
    IUniswapV2Pair pair1;
    IUniswapV2Pair pair2;
    
    bytes32 constant INIT_CODE_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    
    function setUp() public {
        // 部署测试代币
        tokenA = new TestToken("Token A", "TKNA");
        tokenB = new TestToken("Token B", "TKNB");
        
        // 部署工厂合约
        factory1 = new UniswapV2Factory(address(this));
        factory2 = new UniswapV2Factory(address(this));
        
        // 部署两个DEX
        dex1 = new MyDex(
            address(factory1),
            address(0), // router地址在这里不需要
            address(0), // WETH地址在这里不需要
            INIT_CODE_HASH
        );
        
        dex2 = new MyDex(
            address(factory2),
            address(0),
            address(0),
            INIT_CODE_HASH
        );
        
        // 部署FlashLoan合约
        flashLoan = new FlashLoan();
        
        // 创建交易对
        address pair1Address = factory1.createPair(address(tokenA), address(tokenB));
        address pair2Address = factory2.createPair(address(tokenA), address(tokenB));
        
        pair1 = IUniswapV2Pair(pair1Address);
        pair2 = IUniswapV2Pair(pair2Address);
        
        // 给交易对添加流动性
        // DEX1: 1:1 比例
        tokenA.transfer(pair1Address, 100000 ether);
        tokenB.transfer(pair1Address, 100000 ether);
        pair1.mint(address(this));
        
        // DEX2: 1:2 比例
        tokenA.transfer(pair2Address, 100000 ether);
        tokenB.transfer(pair2Address, 200000 ether);
        pair2.mint(address(this));
    }
    
    function test_LiquidityAddedCorrectly() public view {
        // 验证两个交易对都创建成功并添加了流动性
        (uint112 reserve1A, uint112 reserve1B,) = pair1.getReserves();
        (uint112 reserve2A, uint112 reserve2B,) = pair2.getReserves();
        
        // 确保流动性添加成功
        assertGt(reserve1A, 0, "Pair1 tokenA reserves should be > 0");
        assertGt(reserve1B, 0, "Pair1 tokenB reserves should be > 0");
        assertGt(reserve2A, 0, "Pair2 tokenA reserves should be > 0");
        assertGt(reserve2B, 0, "Pair2 tokenB reserves should be > 0");
        
        // 检查DEX1的1:1比例
        assertApproxEqRel(
            reserve1A,
            reserve1B,
            1e16, // 允许1%的误差
            "Pair1 should have 1:1 ratio"
        );
        
        // 检查DEX2的1:2比例
        assertApproxEqRel(
            reserve2A,
            reserve2B * 2,
            1e16, // 允许1%的误差
            "Pair2 should have 1:2 ratio"
        );
    }
    
    function test_FlashLoanArbitrage() public {
        // 记录初始余额
        uint256 initialBalanceA = tokenA.balanceOf(address(this));
        uint256 initialBalanceB = tokenB.balanceOf(address(this));
        
        // 执行闪电贷套利
        uint256 borrowAmount = 10 ether; // 借10个tokenA
        flashLoan.start(
            address(pair1), // 从DEX1借款
            address(pair2), // 在DEX2中套利
            address(tokenA), // 借tokenA
            address(tokenB), // 换成tokenB
            borrowAmount
        );
        
        // 验证套利结果
        uint256 finalBalanceA = tokenA.balanceOf(address(this));
        uint256 finalBalanceB = tokenB.balanceOf(address(this));
        
        // 确保至少赚到了一些利润
        assertGt(
            finalBalanceA + finalBalanceB,
            initialBalanceA + initialBalanceB,
            "No profit made from arbitrage"
        );
    }
    
    function test_InvalidFlashLoanAmount() public {
        // 测试借款金额过大的情况
        uint256 excessiveAmount = type(uint256).max;
        
        vm.expectRevert();
        flashLoan.start(
            address(pair1),
            address(pair2),
            address(tokenA),
            address(tokenB),
            excessiveAmount
        );
    }
    
    receive() external payable {}
}