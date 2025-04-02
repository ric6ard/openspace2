// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract BlendFinance is Ownable, ReentrancyGuard {
    struct CollateralInfo {
        bool isSupported;
        uint256 collateralRatio; // 1e18 = 100%
        AggregatorV3Interface priceFeed; // Chainlink price feed
    }

    mapping(address => CollateralInfo) public supportedCollaterals;
    address public usdc;
    uint256 public feeRate; // 1e18 = 100%, max 0.001e18 (0.1%)
    uint256 public liquidationThreshold; // 1e18 = 100%, default 1.2e18 (120%)
    uint256 public liquidationDiscount; // 1e18 = 100%, default 0.9e18 (90%)

    struct Bond {
        address collateralToken;
        uint256 collateralAmount;
        address bondToken;
        uint256 bondAmount;
        address borrower;
        bool isActive;
    }

    mapping(address => Bond[]) public userBonds;
    mapping(uint256 => address) public supportedMaturities;
    uint256 public maturityCount;
    uint256 public feeBalance; // Platform fee balance in USDC

    ISwapRouter public uniswapRouter;
    INonfungiblePositionManager public positionManager;

    event BondIssued(address indexed borrower, address bondToken, uint256 amount);
    event BondRepaid(address indexed borrower, address bondToken, uint256 amount);
    event Liquidated(address indexed borrower, address bondToken);
    event FeesWithdrawn(address indexed admin, uint256 amount);

    constructor(address _usdc, address _uniswapRouter, address _positionManager) Ownable(msg.sender) {
        usdc = _usdc;
        uniswapRouter = ISwapRouter(_uniswapRouter);
        positionManager = INonfungiblePositionManager(_positionManager);
        feeRate = 0;
        liquidationThreshold = 1.2e18; // 120%
        liquidationDiscount = 0.9e18; // 10% off
    }

    function addCollateral(address token, uint256 ratio, address priceFeed) external onlyOwner {
        supportedCollaterals[token] = CollateralInfo(true, ratio, AggregatorV3Interface(priceFeed));
    }

    function addMaturity(uint256 date) external onlyOwner {
        require(date > block.timestamp, "Invalid maturity");
        supportedMaturities[maturityCount] = date;
        maturityCount++;
    }

    function setFeeRate(uint256 _feeRate) external onlyOwner {
        require(_feeRate <= 0.001e18, "Fee too high");
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
        require(supportedMaturities[maturityIndex] > block.timestamp, "Invalid maturity");

        uint256 collValue = getCollateralValue(collateralToken, collateralAmount);
        require(collValue >= (bondAmount * collInfo.collateralRatio) / 1e18, "Insufficient collateral");

        string memory symbol = string(abi.encodePacked("USDC-Bond-", uint2str(supportedMaturities[maturityIndex])));
        BondToken bondToken = new BondToken("Blend Finance Bond", symbol, supportedMaturities[maturityIndex], address(this));

        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);

        uint256 fee = (bondAmount * feeRate) / 1e18;
        require(IERC20(usdc).transferFrom(msg.sender, address(this), fee), "Fee transfer failed");
        feeBalance += fee;

        userBonds[msg.sender].push(Bond({
            collateralToken: collateralToken,
            collateralAmount: collateralAmount,
            bondToken: address(bondToken),
            bondAmount: bondAmount,
            borrower: msg.sender,
            isActive: true
        }));

        bondToken.mint(msg.sender, bondAmount);

        emit BondIssued(msg.sender, address(bondToken), bondAmount);
    }

    function repayBond(address bondToken, uint256 amount) external nonReentrant {
        BondToken bond = BondToken(bondToken);
        require(bond.platform() == address(this), "Invalid bond");

        uint256 fee = (amount * feeRate) / 1e18;
        require(IERC20(usdc).transferFrom(msg.sender, address(this), fee), "Fee transfer failed");
        feeBalance += fee;

        bond.transferFrom(msg.sender, address(this), amount);
        bond.burn(amount);

        Bond[] storage bonds = userBonds[msg.sender];
        for (uint i = 0; i < bonds.length; i++) {
            if (bonds[i].bondToken == bondToken && bonds[i].isActive) {
                uint256 collToReturn = (bonds[i].collateralAmount * amount) / bonds[i].bondAmount;
                bonds[i].bondAmount -= amount;
                bonds[i].collateralAmount -= collToReturn;

                if (bonds[i].bondAmount == 0) {
                    bonds[i].isActive = false;
                }

                IERC20(bonds[i].collateralToken).transfer(msg.sender, collToReturn);
                break;
            }
        }

        emit BondRepaid(msg.sender, bondToken, amount);
    }

    function claimMatured(address bondToken) external nonReentrant {
        BondToken bond = BondToken(bondToken);
        require(block.timestamp >= bond.maturityDate(), "Not matured");
        uint256 amount = bond.balanceOf(msg.sender);
        require(amount > 0, "No bonds to claim");

        bond.transferFrom(msg.sender, address(this), amount);
        bond.burn(amount);
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
        feeBalance += fee;

        bond.isActive = false;
        IERC20(bond.collateralToken).transfer(msg.sender, bond.collateralAmount);

        emit Liquidated(borrower, bond.bondToken);
    }

    function provideLiquidity(address token0, address token1, uint256 amount0Desired, uint256 amount1Desired) external {
        // Implement Uniswap V3 LP logic using positionManager.mint()
        // Placeholder - needs full implementation
    }

    function withdrawFees() external onlyOwner {
        uint256 amount = feeBalance;
        feeBalance = 0;
        IERC20(usdc).transfer(owner(), amount);
        emit FeesWithdrawn(owner(), amount);
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