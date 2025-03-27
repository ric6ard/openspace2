// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
// import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// 一个支持两个池子之间的闪电贷的合约
contract FlashLoan is IUniswapV2Callee, Ownable {

    // event TestLogUint(uint256 logUint);
    constructor() Ownable(msg.sender) {

    }
    function start(
        address _pairBorrow,//借款的pair
        address _pairSwap,//兑换的pair
        address _tokenBorrow,//借款的token
        address _tokenSwap,//兑换的目标token
        uint256 _amountBorrow //借款数量
        // uint256 _amountMin
    ) external onlyOwner {
        address tokenA = IUniswapV2Pair(_pairBorrow).token0();
        address tokenB = IUniswapV2Pair(_pairBorrow).token1();
        address tokenC = IUniswapV2Pair(_pairSwap).token0();
        address tokenD = IUniswapV2Pair(_pairSwap).token1();
        require((tokenA == tokenC || tokenA == tokenD ) && (tokenB == tokenC || tokenB == tokenD), "Invalid pair");
        require(tokenA == _tokenBorrow || tokenB == _tokenBorrow, "Invalid token");

        //计算还款数量
        (uint256 rA, uint256 rB,) = IUniswapV2Pair(_pairBorrow).getReserves();
        uint256 amountDebt = ((rA * rB / (rA - _amountBorrow)) - rB) * 1000 / 997;
        amountDebt = amountDebt + 1; // 防止精度问题, 还款的数量要多一点

        bytes memory data = abi.encode(_pairBorrow, _pairSwap, _tokenBorrow,_tokenSwap, _amountBorrow, amountDebt);

        if (_tokenBorrow == tokenA){
            IUniswapV2Pair(_pairBorrow).swap(_amountBorrow, 0, address(this), data);
        } else if(_tokenBorrow == tokenB){
            IUniswapV2Pair(_pairBorrow).swap(0, _amountBorrow, address(this), data);
        }
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        //decode data
        (address pairBorrow, address pairSwap, address tokenBorrow, address tokenSwap, uint amountBorrow, uint amountDebt) = abi.decode(data, (address, address, address, address, uint, uint));
        require(msg.sender == pairBorrow, "Only pair can call this");
        require(sender == address(this), "Only this contract can call this");
        (uint256 rA, uint256 rB,) = IUniswapV2Pair(pairSwap).getReserves();
        
 
        if (amount0 > 0) {
            uint256 amountSwap = rB - rA * rB / (rA + amountBorrow * 997 / 1000);
            amountSwap = amountSwap - 1; // 防止精度问题, 取出的数量要少一点
            // 直接和 pairSwap 交互, 把 tokenBorrow 兑换成 tokenSwap
            IERC20(tokenBorrow).transfer(pairSwap, amountBorrow);
            if (tokenBorrow == IUniswapV2Pair(pairBorrow).token0()) {
                // emit TestLogUint(1);
                IUniswapV2Pair(pairSwap).swap(amountSwap, 0, address(this), new bytes(0));
            } else {
                // emit TestLogUint(2);
                IUniswapV2Pair(pairSwap).swap(0, amountSwap, address(this), new bytes(0));
            }


        } else if (amount1 > 0) {
            uint256 amountSwap = rA - rA * rB / (rB + amountBorrow * 997 / 1000);
            amountSwap = amountSwap - 1; // 防止精度问题, 取出的数量要少一点
            // 直接和 pairSwap 交互, 把 tokenBorrow 兑换成 tokenSwap
            IERC20(tokenBorrow).transfer(pairSwap, amountBorrow);
            if (tokenBorrow == IUniswapV2Pair(pairBorrow).token0()) {
                // emit TestLogUint(3);
                IUniswapV2Pair(pairSwap).swap(0, amountSwap, address(this), new bytes(0));
            } else {
                // emit TestLogUint(4);
                IUniswapV2Pair(pairSwap).swap(amountSwap, 0, address(this), new bytes(0));
            }

        }
        
        // 还款
        IERC20(tokenSwap).transfer(pairBorrow, amountDebt);
        // 提取利润
        uint256 profit = IERC20(tokenSwap).balanceOf(address(this));
        IERC20(tokenSwap).transfer(owner(), profit);
    }
}