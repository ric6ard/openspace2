// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
    function approve(address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
}

contract MyDex {
    address public factory;
    address public router;
    address public WETH;
    bytes32 public initCodeHash;

    constructor(address _factory, address _router, address _WETH, bytes32 _initCodeHash) {
        factory = _factory;
        router = _router;
        WETH = _WETH;
        initCodeHash = _initCodeHash;
    }

    function getPairAddress(address tokenA, address tokenB) public view returns (address pair) {
        return IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    }

    // 直接与交易对交互而不使用 Router
    function sellETH(address buyToken, uint256 minBuyAmount) external payable {
        require(msg.value > 0, "Must send ETH to sell");
        
        // 获取交易对地址
        address pair = getPairAddress(buyToken, WETH);
        require(pair != address(0), "Pair does not exist");
        
        // 将 ETH 转换为 WETH
        IWETH(WETH).deposit{value: msg.value}();
        
        // 获取当前储备量
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        
        // 确保 token0 和 token1 的顺序正确
        (address token0, ) = sortTokens(WETH, buyToken);
        (uint reserveIn, uint reserveOut) = WETH == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        
        // 计算输出金额 (使用 Uniswap 的公式)
        uint amountInWithFee = msg.value * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        uint amountOut = numerator / denominator;
        
        require(amountOut >= minBuyAmount, "Insufficient output amount");
        
        // 给交易对批准 WETH
        IWETH(WETH).approve(pair, msg.value);
        
        // 向交易对转移 WETH
        IWETH(WETH).transfer(pair, msg.value);
        
        // 执行交换 (简化版)
        IUniswapV2Pair(pair).swap(
            buyToken == token0 ? amountOut : 0, 
            buyToken == token0 ? 0 : amountOut, 
            msg.sender, 
            new bytes(0)
        );
    }

    function buyETH(address sellToken, uint256 sellAmount, uint256 minBuyAmount) external {
        require(sellAmount > 0, "Must sell some tokens");
        
        // 获取交易对地址
        address pair = getPairAddress(sellToken, WETH);
        require(pair != address(0), "Pair does not exist");
        
        // 从用户转移代币
        IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
        
        // 获取当前储备量
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        
        // 确保 token0 和 token1 的顺序正确
        (address token0, ) = sortTokens(sellToken, WETH);
        (uint reserveIn, uint reserveOut) = sellToken == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        
        // 计算输出金额
        uint amountInWithFee = sellAmount * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        uint amountOut = numerator / denominator;
        
        require(amountOut >= minBuyAmount, "Insufficient output amount");
        
        // 给交易对批准代币
        IERC20(sellToken).approve(pair, sellAmount);
        
        // 向交易对转移代币
        IERC20(sellToken).transfer(pair, sellAmount);
        
        // 执行交换
        IUniswapV2Pair(pair).swap(
            WETH == token0 ? amountOut : 0, 
            WETH == token0 ? 0 : amountOut, 
            address(this), 
            new bytes(0)
        );
        
        // 将 WETH 转换回 ETH 并发送给用户
        IWETH(WETH).withdraw(amountOut);
        (bool success, ) = msg.sender.call{value: amountOut}("");
        require(success, "ETH transfer failed");
    }

    // 辅助函数: 按顺序排列代币地址
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Same token");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "Zero address");
    }

    // 接收 ETH
    receive() external payable {}
}