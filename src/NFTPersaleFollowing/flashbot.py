import asyncio
import json
from web3 import Web3 # type: ignore
from web3.types import HexBytes # type: ignore
from eth_account import Account # type: ignore
from eth_account._utils.legacy_transactions import (
    encode_transaction,
    serializable_unsigned_transaction_from_dict,
)
from flashbots import flashbot # type: ignore
from websocket import create_connection  # type: ignore
import time
from dotenv import load_dotenv # type: ignore
import os

load_dotenv('/Users/richard/Desktop/dev/openspace2/.env')
Alchemy_API_KEY = os.getenv("ALCHEMY_API_KEY")
PritateKey = os.getenv("PRIVATE_KEY_DEV_2")

# 设置 Web3 连接到 Sepolia 测试网络
http_provider = Web3.HTTPProvider("https://eth-sepolia.g.alchemy.com/v2/" + Alchemy_API_KEY)
w3 = Web3(http_provider)

flashbot_w3 = flashbot(w3, Account.from_key(PritateKey), "https://relay-sepolia.flashbots.net")
# 对于Web3.py v6+，使用新的中间件导入和应用方式
try:
    # 尝试新版API (web3.py v6+)
    from web3.middleware import geth_poa  # 新的导入路径
    w3.middleware_onion.inject(geth_poa.geth_poa_middleware, layer=0)
except ImportError:
    try:
        # 尝试旧版API (web3.py v5)
        from web3.middleware import geth_poa_middleware
        w3.middleware_onion.inject(geth_poa_middleware, layer=0)
    except ImportError:
        print("警告: 无法加载 POA 中间件，可能影响与 Sepolia 的交互")

# WebSocket 提供者
ws_url = "wss://eth-sepolia.g.alchemy.com/v2/" + Alchemy_API_KEY

# 定义 OpenspaceNFT 合约 ABI 和地址
contract_abi = [
    {"inputs": [], "name": "enablePresale", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"internalType": "uint256", "name": "amount", "type": "uint256"}], "name": "presale", "outputs": [], "stateMutability": "payable", "type": "function"}
]
# 修复: 使用toChecksumAddress将合约地址转换为checksum格式
contract_address = w3.to_checksum_address("0xa4010fa5a816747f9eba1a60271280beaae28f10")
contract = w3.eth.contract(address=contract_address, abi=contract_abi)

# 定义所有者地址和买家私钥 - 同样使用checksum格式
owner_address = w3.to_checksum_address("0xE9d2E42129C04f5627f7894aABD422B8a76737aD")
buyer_private_key = PritateKey  
buyer_address = w3.to_checksum_address(Account.from_key(buyer_private_key).address)

# 计算 enablePresale 函数选择器
enable_presale_selector = Web3.keccak(text="enablePresale()").hex()[:8]

# 创建并签署用户的 presale 交易
amount = 5  # 示例：购买 5 个 NFT
value = amount * 10**16  # 0.05 Ether
presale_txn = contract.functions.presale(amount).build_transaction({
    'from': buyer_address,
    'maxFeePerGas': 100 * 10**9,  # 示例 gas 费用
    'maxPriorityFeePerGas': 2 * 10**9,
    'nonce': w3.eth.get_transaction_count(buyer_address),
    'value': value,
})
signed_presale = w3.eth.account.sign_transaction(presale_txn, buyer_private_key)
raw_presale_tx = signed_presale['rawTransaction'].hex()


# 恢复原始交易
def recover_raw_transaction(tx):
    """Recover raw transaction for replay.
    Inspired by: https://github.com/ethereum/eth-account/blob/1d26f44f6075d6f283aeaeff879f4508c9a228dc/eth_account/_utils/signing.py#L28-L42
    """
    transaction = dict(tx)
    v, r, s = transaction.pop("v"), transaction.pop("r"), transaction.pop("s")
    transaction.pop('blockHash')
    transaction.pop('blockNumber')
    transaction.pop('transactionIndex')
    transaction.pop('from')
    transaction.pop('yParity')
    transaction.pop('gasPrice')
    transaction.pop('hash')
    transaction['data']=transaction.pop('input')
    # print(f"Transaction: {transaction}")

    unsigned_transaction = serializable_unsigned_transaction_from_dict(transaction)
    print(f"Unsigned Transaction: {unsigned_transaction}")
    return "0x" + encode_transaction(unsigned_transaction, vrs=(v, r, s)).hex()

# WebSocket 监听新交易
async def listen_pending_transactions():
    ws = create_connection(ws_url)
    subscription = {"jsonrpc": "2.0", "id": 1, "method": "eth_subscribe", 
                    "params": ["alchemy_pendingTransactions",
                    {"fromAddresses":  owner_address, "toAddress": contract_address, 
                     "includeRemoved": False,"hashesOnly": True,},],}
    ws.send(json.dumps(subscription))
    print("Listening for pending transactions...")

    while True:
        message = json.loads(ws.recv())
        if "params" in message and "result" in message["params"]:
            tx_hash = message["params"]["result"]
            print(f"New pending transaction: {tx_hash}")
            try:
                tx = w3.eth.get_transaction(tx_hash)
                
                if (tx and tx['input'].hex()[:8] == enable_presale_selector):
                    # 找到所有者的 enablePresale 交易
                    # raw_enable_tx = w3.provider.make_request("eth_getRawTransactionByHash", [tx_hash])['result']
                    # raw_enable_tx = w3.eth.get_raw_transaction(tx_hash)
                    raw_enable_tx = recover_raw_transaction(tx)
                    if not raw_enable_tx:
                        print("无法获取原始交易，跳过此交易")
                        continue
                    print(f"type: {type(raw_enable_tx)}, Raw Enable Tx: {raw_enable_tx}")

                    # 创建捆绑
                    bundle_txs = [raw_enable_tx, raw_presale_tx]
                    # bundle_txs = [raw_presale_tx]

                    current_block = w3.eth.block_number
                    target_block = current_block + 1
                    # target_block_hex = hex(target_block)
                    print(f"Bundle Tx: {bundle_txs}")
                    print(f"Type: {type(target_block)}, Target Block: {target_block}")

                    # 发送捆绑
                    send_result = flashbot_w3.flashbots.send_bundle(bundle_txs, target_block)
                    print(f"Send Result: {send_result}")
                    bundle_hash = send_result.bundle_hash()
                    print(f"Bundle hash: {bundle_hash}")

                    # 获取捆绑状态
                    # stats = await flashbots.get_bundle_stats(bundle_hash)
                    stats = await w3.flashbots.get_bundle_stats(bundle_hash)

                    # 打印结果
                    print(f"Enable Presale Tx Hash: {tx_hash}")
                    print(f"Presale Tx Hash: {signed_presale['hash'].hex()}")
                    print(f"Bundle Stats: {stats}")

                    ws.close()
                    break
            except Exception as e:
                print(f"Error processing tx {tx_hash}: {e}")
        await asyncio.sleep(0.1)  # 避免阻塞

# 运行异步监听
if __name__ == "__main__":
    asyncio.run(listen_pending_transactions())