# BlendFinance 合约文档

## 合约简介
`BlendFinance` 是一个去中心化的债券发行和管理平台，允许用户使用支持的抵押物发行债券，并在到期时偿还债券或提取到期债券。该合约还支持债券清算和手续费提取功能。

---

## 主要数据结构

### 1. CollateralInfo
描述支持的抵押物信息：
- `isSupported`：是否支持该抵押物。
- `collateralRatio`：抵押率（以 1e18 为单位，100% = 1e18）。
- `priceFeed`：Chainlink 价格预言机地址。

### 2. Bond
描述用户的债券信息：
- `collateralToken`：抵押物代币地址。
- `collateralAmount`：抵押物数量。
- `bondToken`：债券代币地址。
- `bondAmount`：债券数量。
- `borrower`：债券持有人地址。
- `isActive`：债券是否处于活跃状态。

---

## 主要状态变量

- `supportedCollaterals`：支持的抵押物信息（`mapping(address => CollateralInfo)`）。
- `bondTokens`：债券代币地址（`mapping(uint256 => address)`）。
- `userBonds`：用户的债券列表（`mapping(address => Bond[])`）。
- `supportedMaturities`：支持的债券到期时间（`mapping(uint256 => uint256)`）。
- `feeRate`：手续费率（以 1e18 为单位，0.5% = 0.005e18）。
- `liquidationThreshold`：清算阈值（以 1e18 为单位，120% = 1.2e18）。
- `liquidationDiscount`：清算折扣（以 1e18 为单位，90% = 0.9e18）。
- `feeBalance`：累计的手续费余额（单位为债券代币）。

---

## 主要功能

### 1. 添加支持的抵押物
```solidity
function addCollateral(address token, uint256 ratio, address priceFeed) external onlyOwner
```

- 描述：添加支持的抵押物。
- 参数：
    - `token`：抵押物代币地址。
    - `ratio`：抵押率（以 1e18 为单位）。
    - `priceFeed`：Chainlink 价格预言机地址。
- 权限：仅限合约所有者调用。

### 2. 添加债券到期时间
```solidity
function addMaturity(uint256 date) external onlyOwner
```
- 描述：添加支持的债券到期时间。
- 参数：
    - `date`：债券到期时间（Unix 时间戳）。
- 权限：仅限合约所有者调用。

### 3. 设置手续费率
```solidity
function setFeeRate(uint256 _feeRate) external onlyOwner
```
- 描述：设置债券发行的手续费率。
- 参数：
    - `_feeRate`：手续费率（以 1e18 为单位）。
- 权限：仅限合约所有者调用。

### 4. 设置清算参数
```solidity
function setLiquidationParams(uint256 threshold, uint256 discount) external onlyOwner
```
- 描述：设置清算阈值和折扣。
- 参数：
    - `threshold`：清算阈值（以 1e18 为单位）。
    - `discount`：清算折扣（以 1e18 为单位）。
- 权限：仅限合约所有者调用。

### 5. 发行债券
```solidity
function issueBond(
    address collateralToken,
    uint256 collateralAmount,
    uint256 bondAmount,
    uint256 maturityIndex
) external nonReentrant
```
- 描述：用户使用抵押物发行债券。
- 参数：
    - `collateralToken`：抵押物代币地址。
    - `collateralAmount`：抵押物数量。
    - `bondAmount`：债券数量。
    - `maturityIndex`：债券到期时间索引。
- 事件：
    - `BondIssued`：记录债券发行信息。

### 6. 偿还债券
```solidity
function repayBond(uint256 bondIndex) external nonReentrant
```
- 描述：用户偿还债券并取回抵押物。
- 参数：
    - `bondIndex`：用户债券列表中的索引。
- 事件：
    - `BondRepaid`：记录债券偿还信息。

### 7. 提取到期债券
```solidity
function claimMatured(address bondToken) external nonReentrant
```
- 描述：用户提取到期债券。
- 参数：
    - `bondToken`：债券代币地址。
- 事件：
    - `BondRepaid`：记录债券提取信息。

### 8. 清算债券
```solidity
function liquidate(address borrower, uint256 bondIndex) external nonReentrant
```
- 描述：清算抵押不足的债券。
- 参数：
    - `borrower`：债券持有人地址。
    - `bondIndex`：债券索引。
- 事件：
    - `Liquidated`：记录债券清算信息。

### 9. 提取手续费
```solidity
function withdrawFees(address bondToken) external onlyOwner
```
- 描述：合约所有者提取累计的手续费。
- 参数：
    - `bondToken`：债券代币地址。
- 事件：
    - `FeesWithdrawn`：记录手续费提取信息。

### 10. 获取抵押物价值
```solidity
function getCollateralValue(address token, uint256 amount) public view returns (uint256)
```
- 描述：根据价格预言机获取抵押物的当前价值。
- 参数：
    - `token`：抵押物代币地址。
    - `amount`：抵押物数量。
- 返回值：抵押物的当前价值（以 USDC 为单位）。

## 事件
### 1.`BondIssued`
- 描述：记录债券发行信息。
- 参数：
    - `borrower`：债券持有人地址。
    - `bondToken`：债券代币地址。
    - `amount`：债券数量。
    
### 2.`BondRepaid`
- 描述：记录债券偿还信息。
- 参数：
    - `borrower`：债券持有人地址。
    - `bondToken`：债券代币地址。
    - `amount`：偿还的债券数量。

### 3.`Liquidated`
- 描述：记录债券清算信息。
- 参数：
    - `borrower`：债券持有人地址。
    - `bondToken`：债券代币地址。

### 4.`FeesWithdrawn`
- 描述：记录手续费提取信息。
- 参数：
    - `admin`：提取手续费的管理员地址。
    - `amount`：提取的手续费数量。

### 5.`MaturityAdded`
- 描述：记录新增的债券到期时间。
- 参数：
    - `maturity`：债券到期时间。
    - `bondToken`：债券代币地址。

## 注意事项
### 1.抵押物支持：
- 只有通过 `addCollateral` 添加的抵押物才能用于发行债券。
### 2.债券到期时间：
- 债券到期时间必须通过 `addMaturity` 添加，并且必须大于当前时间。
### 3. 清算条件：
- 当抵押物价值低于债券价值的清算阈值时，债券可以被清算。
### 4.手续费提取：
- 手续费只能由合约所有者提取。