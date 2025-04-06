// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract BondToken is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public maturityDate;
    address public platform;

    constructor(string memory _name, string memory _symbol, uint256 _maturityDate, address _platform) {
        name = _name;
        symbol = _symbol;
        maturityDate = _maturityDate;
        platform = _platform;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == platform, "Only platform");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        require(msg.sender == platform, "Only platform");
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract BlendFinance is Ownable, ReentrancyGuard {
    struct CollateralInfo {
        bool isSupported;
        uint256 collateralRatio; // 1e18 = 100%
        AggregatorV3Interface priceFeed;
    }

    struct Bond {
        address collateralToken;
        uint256 collateralAmount;
        address bondToken;
        uint256 bondAmount;
        address borrower;
        bool isActive;
    }

    mapping(address => CollateralInfo) public supportedCollaterals;
    mapping(uint256 => address) public bondTokens; // maturity => bondToken
    mapping(address => Bond[]) public userBonds;
    mapping(uint256 => uint256) public supportedMaturities;
    uint256 public maturityCount;
    address public usdc;
    uint256 public feeRate; // 1e18 = 100%
    uint256 public liquidationThreshold; // 1e18 = 100%
    uint256 public liquidationDiscount; // 1e18 = 100%
    uint256 public feeBalance; // 手续费余额（单位为 bondToken）

    ISwapRouter public uniswapRouter;
    INonfungiblePositionManager public positionManager;

    event BondIssued(address indexed borrower, address bondToken, uint256 amount);
    event BondRepaid(address indexed borrower, address bondToken, uint256 amount);
    event Liquidated(address indexed borrower, address bondToken);
    event FeesWithdrawn(address indexed admin, uint256 amount);
    event MaturityAdded(uint256 indexed maturity, address bondToken);

    event TestMessage(string message);

    constructor(address _usdc, address _uniswapRouter, address _positionManager) Ownable(msg.sender) {
        usdc = _usdc;
        uniswapRouter = ISwapRouter(_uniswapRouter);
        positionManager = INonfungiblePositionManager(_positionManager);
        feeRate = 5e15; // 0.5%
        // feeRate = 0;
        liquidationThreshold = 1.2e18; // 120%
        liquidationDiscount = 0.9e18; // 90%
    }

    function addCollateral(address token, uint256 ratio, address priceFeed) external onlyOwner {
        supportedCollaterals[token] = CollateralInfo(true, ratio, AggregatorV3Interface(priceFeed));
    }

    function addMaturity(uint256 date) external onlyOwner {
        require(date > block.timestamp, "Invalid maturity");
        string memory symbol = string(abi.encodePacked("USDC-Bond-", uint2str(date)));
        BondToken bondToken = new BondToken("Blend Finance Bond", symbol, date, address(this));
        bondTokens[date] = address(bondToken);
        supportedMaturities[maturityCount] = date;
        maturityCount++;
        emit MaturityAdded(date, address(bondToken));
        // emit TestMessage(symbol);
    }

    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 0.005e18, "Fee too high");
        feeRate = _feeRate;
    }

    function setLiquidationParams(uint256 threshold, uint256 discount) external onlyOwner {
        require(threshold >= 1e18, "Threshold too low");
        require(discount <= 1e18, "Discount too high");
        liquidationThreshold = threshold;
        liquidationDiscount = discount;
    }

    function issueBond(
        address collateralToken,
        uint256 collateralAmount,
        uint256 bondAmount,
        uint256 maturityIndex
    ) external nonReentrant {
        CollateralInfo memory collInfo = supportedCollaterals[collateralToken];
        require(collInfo.isSupported, "Unsupported collateral");
        uint256 maturity = supportedMaturities[maturityIndex];
        require(maturity > block.timestamp, "Invalid maturity");

        address bondTokenAddr = bondTokens[maturity];
        require(bondTokenAddr != address(0), "Bond token not created");

        uint256 collValue = getCollateralValue(collateralToken, collateralAmount);
        require(collValue >= (bondAmount * collInfo.collateralRatio) / 1e18, "Insufficient collateral");

        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);

        uint256 fee = (bondAmount * feeRate) / 1e18;
        uint256 netBondAmount = bondAmount - fee;
        require(netBondAmount > 0, "Bond amount too low after fee");

        feeBalance += fee; // 单位为 bondToken
        userBonds[msg.sender].push(Bond({
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            bondToken: bondTokenAddr,
            bondAmount: bondAmount,
            borrower: msg.sender,
            isActive: true
        }));
        BondToken(bondTokenAddr).mint(address(this), fee);
        BondToken(bondTokenAddr).mint(msg.sender, netBondAmount);
        emit BondIssued(msg.sender, bondTokenAddr, netBondAmount);

    }

    function repayBond(uint256 bondIndex) external nonReentrant {
        Bond[] storage bonds = userBonds[msg.sender];
        require(bondIndex < bonds.length, "Invalid bond index");
        Bond storage bond = bonds[bondIndex];
        require(bond.isActive, "Bond not active");

        uint256 amount = bond.bondAmount;
        BondToken bondToken = BondToken(bond.bondToken);
        uint256 fee = (amount * feeRate) / 1e18;
        require(bondToken.balanceOf(msg.sender) >= amount + fee, "Insufficient bond tokens");
        bondToken.transferFrom(msg.sender, address(this), amount + fee);
        bondToken.burn(amount);

        uint256 collToReturn = bond.collateralAmount; // 整个仓位的抵押物

        bond.bondAmount = 0;
        bond.collateralAmount = 0;
        bond.isActive = false;

        feeBalance += fee; // 单位为 bondToken
        IERC20(bond.collateralToken).transfer(msg.sender, collToReturn);

        emit BondRepaid(msg.sender, bond.bondToken, amount);
    }

    function claimMatured(address bondToken) external nonReentrant {
        BondToken bond = BondToken(bondToken);
        require(block.timestamp >= bond.maturityDate(), "Not matured");
        uint256 amount = bond.balanceOf(msg.sender);
        require(amount > 0, "No bonds to claim");

        bond.transferFrom(msg.sender, address(this), amount);
        bond.burn(amount);
        uint256 fee = (amount * feeRate) / 1e18;
        feeBalance += fee; // 单位为 bondToken
        uint256 netAmount = amount - fee;
        if (IERC20(usdc).balanceOf(address(this)) < netAmount ) {
            // TODO 如果USDC不足, 通过 Uniswap 将 抵押物 转换为 USDC
            revert("Insufficient USDC");
        }


        IERC20(usdc).transfer(msg.sender, amount);
    }

    function liquidate(address borrower, uint256 bondIndex) external nonReentrant {
        Bond storage bond = userBonds[borrower][bondIndex];
        require(bond.isActive, "Bond not active");

        uint256 collValue = getCollateralValue(bond.collateralToken, bond.collateralAmount);
        require(collValue < (bond.bondAmount * liquidationThreshold) / 1e18, "Not liquidatable");
        uint256 collValueAfterDiscount = (collValue * liquidationDiscount) / 1e18;
        require(IERC20(usdc).transferFrom(msg.sender, address(this), collValueAfterDiscount), "Payment failed");

        uint256 fee = (collValueAfterDiscount * feeRate) / 1e18;
        feeBalance += fee; // 单位为 USDC，此处与 bondToken 单位不一致

        bond.isActive = false;
        IERC20(bond.collateralToken).transfer(msg.sender, bond.collateralAmount);
        emit Liquidated(borrower, bond.bondToken);
    }

    function provideLiquidity(address token0, address token1, uint256 amount0Desired, uint256 amount1Desired) external {
        //TODO Placeholder for Uniswap V3 LP logic
    }

    function withdrawFees(address bondToken) external onlyOwner {
        uint256 amount = feeBalance;
        require(amount > 0, "No fees to withdraw");
        feeBalance = 0;

        
        // BondToken(bondToken).approve(address(uniswapRouter), amount);
        uint256 amountOut = amount; // Placeholder for actual swap amount
        BondToken(bondToken).transfer(msg.sender, amount);
        //TODO 假设通过 Uniswap 将 bondToken 转换为 USDC
        // ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        //     tokenIn: bondToken,
        //     tokenOut: usdc,
        //     fee: 3000, // 0.3% fee tier
        //     recipient: owner(),
        //     deadline: block.timestamp + 15,
        //     amountIn: amount,
        //     amountOutMinimum: 0, // 需设置滑点保护
        //     sqrtPriceLimitX96: 0
        // });
        // uint256 amountOut = uniswapRouter.exactInputSingle(params);
        emit FeesWithdrawn(owner(), amountOut);
    }

    function getCollateralValue(address token, uint256 amount) public view returns (uint256) {
        CollateralInfo memory info = supportedCollaterals[token];
        (, int256 price, , , ) = info.priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return (amount * uint256(price)) / 1e8; // Adjust for Chainlink decimals
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}