// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Blend/BlendFinance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BlendFinanceTest is Test {
    BlendFinance blend;
    MockERC20 usdc;
    MockERC20 collateralToken;
    address alice = address(0x1);
    address bob = address(0x2);
    address priceFeed = address(0x3);

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("Mock USDC", "USDC");
        collateralToken = new MockERC20("Mock Collateral", "COLL");

        // Deploy BlendFinance contract
        blend = new BlendFinance(address(usdc), address(0), address(0));

        // Mint tokens for testing
        usdc.mint(alice, 10000 ether);
        usdc.mint(bob, 10000 ether);
        usdc.mint(address(blend), 10000 ether);
        collateralToken.mint(alice, 1000 ether);

        // Add collateral and maturity
        blend.addCollateral(address(collateralToken), 1.5e18, priceFeed); // 150% collateral ratio
        blend.addMaturity(block.timestamp + 30 days);

        // Approve tokens
        vm.startPrank(alice);
        usdc.approve(address(blend), type(uint256).max);
        collateralToken.approve(address(blend), type(uint256).max);
        vm.stopPrank();
    }

    function testIssueBond() public {
        vm.startPrank(alice);

        // Mock price feed to return a price
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 2e8, 0, 0, 0)); // Price = 2 USDC

        // Issue bond
        blend.issueBond(address(collateralToken), 100 ether, 50 ether, 0);

        // Verify bond details
        (address collateral,uint256 collateralAmount,,uint256 bondAmount,,) = blend.userBonds(alice, 0);
        assertEq(collateralAmount, 100 ether, "Incorrect collateral amount");
        assertEq(bondAmount, 50 ether, "Incorrect bond amount");
        assertEq(collateral, address(collateralToken), "Incorrect collateral token");

        vm.stopPrank();
    }

    function testRepayBond() public {
        vm.startPrank(alice);

        // Mock price feed to return a price
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 2e8, 0, 0, 0)); // Price = 2 USDC

        // Issue bond
        blend.issueBond(address(collateralToken), 100 ether, 50 ether, 0);
        // Issue more bonds to cover the repayment and fees
        blend.issueBond(address(collateralToken), 2 ether, 1 ether, 0);

        (,,address bondTokenAddr,,,) = blend.userBonds(alice, 0);
        BondToken bondToken = BondToken(bondTokenAddr);
        bondToken.approve(address(blend), type(uint256).max);
        blend.repayBond(0);

        (,,,uint256 bondAmount,,bool isActive) = blend.userBonds(alice, 0);
        assertEq(bondAmount, 0, "Bond not repaid");
        assertEq(isActive, false, "Bond not repaid");

        vm.stopPrank();
    }
    function testClaimMatured() public {
        vm.startPrank(alice);

        // Mock price feed to return a price
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 2e8, 0, 0, 0)); // Price = 2 USDC
        uint256 previousBalance =  usdc.balanceOf(alice); // Check USDC balance

        // Issue bond
        blend.issueBond(address(collateralToken), 100 ether, 50 ether, 0);

        // Fast forward time to maturity
        vm.warp(block.timestamp + 31 days);

        // Claim matured bond
        // Claim matured bond
        (,,address bondTokenAddr,,,) = blend.userBonds(alice, 0);
        BondToken bondToken = BondToken(bondTokenAddr);
        // bondToken.mint(alice, 50 ether); // Mint bond tokens for claiming
        bondToken.approve(address(blend), type(uint256).max);

        blend.claimMatured(bondTokenAddr);

        // Verify USDC balance
        uint256 feeRate = blend.feeRate();
        uint256 expectedBalance = previousBalance + (50 ether * (1e18 - feeRate)) / 1e18;

        assertEq(usdc.balanceOf(alice), expectedBalance, "Incorrect USDC balance after claim");

        vm.stopPrank();
    }

    function testLiquidate() public {
        vm.startPrank(alice);

        // Mock price feed to return a price
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 2e8, 0, 0, 0)); // Price = 2 USDC

        // Issue bond
        blend.issueBond(address(collateralToken), 100 ether, 50 ether, 0);

        vm.stopPrank();
        vm.startPrank(bob);

        // Mock price drop
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 59e6, 0, 0, 0)); // Price = 0.59 USDC

        // Liquidate bond
        usdc.approve(address(blend), type(uint256).max);
        blend.liquidate(alice, 0);

        // Verify bond is liquidated
        (,,,,,bool isActive) = blend.userBonds(alice, 0);
        assertEq(isActive, false, "Bond not liquidated");
    }

    function testWithdrawFees() public {
        vm.startPrank(alice);

        // Mock price feed to return a price
        vm.mockCall(priceFeed, abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), abi.encode(0, 2e8, 0, 0, 0)); // Price = 2 USDC

        // Issue bond
        blend.issueBond(address(collateralToken), 100 ether, 50 ether, 0);

        vm.stopPrank();
        vm.startPrank(address(blend.owner()));

        // Withdraw fees
        (,,address bondTokenAddr,,,) = blend.userBonds(alice, 0);
        blend.withdrawFees(bondTokenAddr);

        // Verify fee balance
        assertEq(usdc.balanceOf(blend.owner()), blend.feeBalance(), "Incorrect fee balance");

        vm.stopPrank();
    }

    function testSetFeeRate() public {
        vm.startPrank(address(blend.owner()));

        // Set new fee rate
        blend.setFeeRate(0.002e18); // 0.2%

        // Verify fee rate
        assertEq(blend.feeRate(), 0.002e18, "Incorrect fee rate");

        vm.stopPrank();
    }

    function testAddCollateral () public {
        vm.startPrank(address(blend.owner()));

        // Add new collateral
        blend.addCollateral(address(collateralToken), 1.5e18, priceFeed); // 150% collateral ratio

        // Verify collateral added
        (bool isSupported,,) = blend.supportedCollaterals(address(collateralToken));
        assertTrue(isSupported, "Collateral not added");
        vm.stopPrank();
    }

}