// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// 极简的杠杆 DEX 实现， 完成 TODO 代码部分
contract SimpleLeverageDEX {

    uint public vK;  // 100000 
    uint public vETHAmount;
    uint public vUSDCAmount;

    IERC20 public USDC;  // 自己创建一个币来模拟 USDC

    event PositionOpened(address indexed user, uint margin, uint level, int position);
    event PositionClosed(address indexed user, uint margin, uint pnl);
    // event LogVK(uint vETHAmount, uint vUSDCAmount, uint vK);
    // event LogOut(int256 any);

    struct PositionInfo {
        uint256 margin; // 保证金    // 真实的资金， 如 USDC 
        uint256 borrowed; // 借入的资金
        int256 position;    // 虚拟 eth 持仓
    }
    mapping(address => PositionInfo) public positions;

    constructor(uint vEth, uint vUSDC) {
        vETHAmount = vEth;
        vUSDCAmount = vUSDC;
        vK = vEth * vUSDC;
    }

    function setUSDC(address _usdc) external {
        USDC = IERC20(_usdc);
    }

    // 开启杠杆头寸
    function openPosition(uint256 _margin, uint level, bool long) external {
        require(positions[msg.sender].position == 0, "Position already open");

        PositionInfo storage pos = positions[msg.sender] ;

        USDC.transferFrom(msg.sender, address(this), _margin); // 用户提供保证金
        uint amount = _margin * level;
        uint256 borrowAmount = amount - _margin;

        pos.margin = _margin;
        pos.borrowed = borrowAmount;

        // TODO:
        if (long) { 
            //做多, 卖出vUSDC, 买入vETH, 用户传入 -usdc, 得到 +eth 仓位
            pos.position = calculateSwapUSDCForETH(-int256(amount));
            //池子 +usdc, -eth
            vUSDCAmount += amount;
            vETHAmount -= uint256(pos.position);
        } else {
            //做空, 买入vUSDC, 卖出vETH, 用户传入 +usdc, 得到 -eth 仓位
            pos.position = calculateSwapUSDCForETH(int256(amount));
            //池子 -usdc, +eth
            vUSDCAmount -= amount;
            vETHAmount += uint256(-pos.position);
        }
        // emit LogVK(vETHAmount, vUSDCAmount, vUSDCAmount*vETHAmount);
        emit PositionOpened(msg.sender, _margin, level, pos.position);
    }

    // 关闭头寸并结算, 不考虑协议亏损
    function closePosition(address _user) public {
        // TODO:
        PositionInfo memory pos = positions[_user];
        require(pos.position != 0, "No open position");
        int256 pnl = calculatePnL(_user);
        uint256 amountToTransfer;
        if (pnl >= 0) {
            amountToTransfer = pos.margin + uint256(pnl);
        } else {
            require(uint256(-pnl) <= pos.margin, "Insufficient margin");
            amountToTransfer = pos.margin - uint256(-pnl);
        }
        
        int256 deltaUSDC = calculateSwapETHForUSDC(-pos.position);
        vUSDCAmount = uint (int(vUSDCAmount) + int256(deltaUSDC));
        vETHAmount = uint (int(vETHAmount) - int256(pos.position));
        delete positions[_user];

        USDC.transfer(msg.sender, amountToTransfer);
        // emit LogVK(vETHAmount, vUSDCAmount, vUSDCAmount*vETHAmount);
        emit PositionClosed(_user, pos.margin, uint256(pnl));
    }

    modifier canLiquidate(address _user) {
        PositionInfo memory pos = positions[_user];
        require(pos.position != 0, "No open position");
        int256 pnl = calculatePnL(_user);
        require(pnl < -int256(pos.margin * 80 / 100), "PnL is not enough to liquidate");
        _;
    }
    // 清算头寸， 清算的逻辑和关闭头寸类似，不过利润由清算用户获取
    // 注意： 清算人不能是自己，同时设置一个清算条件，例如亏损大于保证金的 80%
    function liquidatePosition(address _user) external canLiquidate(_user){
        closePosition(_user);
    }

    // 计算盈亏： 对比当前的仓位和借的 vUSDC
    function calculatePnL(address user) public view returns (int256) {
        // TODO:
        PositionInfo memory pos = positions[user];
        require(pos.position != 0, "No open position");
        int256 currentValueUSDC = calculateSwapETHForUSDC(pos.position);
        int256 pnl;
        if (pos.position > 0) {
            pnl = 0 - currentValueUSDC - int(pos.borrowed + pos.margin) ;
        } else {
            pnl = int(pos.borrowed + pos.margin) - currentValueUSDC;
        }

        // emit LogOut(pnl);
        // emit LogVK(vETHAmount, vUSDCAmount, vUSDCAmount*vETHAmount);
        return pnl;
    }        

    function calculateSwapUSDCForETH(int USDCIn) internal view returns (int256) {
        uint256 newUSDCAmount;
        int256 ETHOut;
        if (USDCIn >= 0) {
            newUSDCAmount = vUSDCAmount - uint256(USDCIn);
        } else {
            require(uint256(-USDCIn) <= vUSDCAmount, "Insufficient Liquidity");
            newUSDCAmount = vUSDCAmount + uint256(-USDCIn); 
        }
        ETHOut = int256(vETHAmount) - int256(vK / newUSDCAmount) ;
        return ETHOut;
    }

    function calculateSwapETHForUSDC(int ETHIn) internal view returns (int256) {
        uint256 newETHAmount;
        if (ETHIn >= 0) {
            newETHAmount = vETHAmount + uint256(ETHIn);
        } else {
            require(uint256(-ETHIn) <= vETHAmount, "Insufficient Liquidity");
            newETHAmount = vETHAmount - uint256(-ETHIn); // Fixed subtraction for negative input
        }

        int256 USDCOut = int256(vK / newETHAmount) - int256(vUSDCAmount);
        return USDCOut;
    }
}