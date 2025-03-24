import asyncio
import json
from web3 import Web3
from eth_account import Account
from flashbots import flashbot
from websocket import create_connection
import time
from dotenv import load_dotenv
import os

load_dotenv('/Users/richard/Desktop/dev/openspace2/.env')
Alchemy_API_KEY = os.getenv("ALCHEMY_API_KEY")
PrivateKey = os.getenv("PRIVATE_KEY_DEV_2")

# 设置 Web3 连接到 Sepolia 测试网络
http_provider = Web3.HTTPProvider(f"https://eth-sepolia.g.alchemy.com/v2/{Alchemy_API_KEY}")
w3 = Web3(http_provider)
try:
    from web3.middleware import geth_poa
    w3.middleware_onion.inject(geth_poa.geth_poa_middleware, layer=0)
except ImportError:
    from web3.middleware import geth_poa_middleware
    w3.middleware_onion.inject(geth_poa_middleware, layer=0)

flashbot_w3 = flashbot(w3, Account.from_key(PrivateKey), "https://relay-sepolia.flashbots.net")

# WebSocket 提供者
ws_url = f"wss://eth-sepolia.g.alchemy.com/v2/{Alchemy_API_KEY}"

# 定义 OpenspaceNFT 合约 ABI 和地址
contract_abi = [
    {"inputs": [], "name": "enablePresale", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"internalType": "uint256", "name": "amount", "type": "uint256"}], "name": "presale", "outputs": [], "stateMutability": "payable", "type": "function"}
]
contract_address = w3.to_checksum_address("0xa4010fa5a816747f9eba1a60271280beaae28f10")
contract = w3.eth.contract(address=contract_address, abi=contract_abi)

# 定义所有者地址和买家私钥
owner_address = w3.to_checksum_address("0xE9d2E42129C04f5627f7894aABD422B8a76737aD")
buyer_private_key = PrivateKey
buyer_address = w3.to_checksum_address(Account.from_key(buyer_private_key).address)

# 计算 enablePresale 函数选择器
enable_presale_selector = Web3.keccak(text="enablePresale()").hex()[:8]

# 创建并签署用户的 presale 交易
amount = 5
value = amount * 10**16
presale_txn = contract.functions.presale(amount).build_transaction({
    'from': buyer_address,
    'maxFeePerGas': 100 * 10**9,
    'maxPriorityFeePerGas': 2 * 10**9,
    'nonce': w3.eth.get_transaction_count(buyer_address),
    'value': value,
})
signed_presale = w3.eth.account.sign_transaction(presale_txn, buyer_private_key)

# WebSocket 监听新交易
async def listen_pending_transactions():
    ws = create_connection(ws_url)
    subscription = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_subscribe",
        "params": [
            "alchemy_pendingTransactions",
            {"fromAddresses": [owner_address], "toAddress": contract_address, "includeRemoved": False, "hashesOnly": True}
        ]
    }
    ws.send(json.dumps(subscription))
    print("Listening for pending transactions...")

    while True:
        message = json.loads(ws.recv())
        if "params" in message and "result" in message["params"]:
            tx_hash = message["params"]["result"]
            print(f"New pending transaction: {tx_hash}")
            try:
                tx = w3.eth.get_transaction(tx_hash)
                
                if tx and tx['input'].hex()[:8] == enable_presale_selector:
                    raw_enable_tx = w3.eth.get_raw_transaction(tx_hash)
                    if raw_enable_tx is None:
                        print("Could not get raw transaction, skipping")
                        continue
                    raw_enable_tx_str = str(raw_enable_tx)
                    raw_presale_tx_str = str(signed_presale['rawTransaction'])

                    bundle_txs = [raw_enable_tx_str, raw_presale_tx_str]
                    print(f"Bundle Tx: {bundle_txs}")
                    current_block = w3.eth.block_number
                    target_block = current_block + 1

                    # 发送捆绑
                    bundle_response = await flashbot_w3.flashbots.send_bundle(
                        bundle_txs,
                        target_block_number=target_block
                    )
                    bundle_hash = bundle_response.bundle_hash()
                    print(f"Bundle hash: {bundle_hash}")

                    # 获取捆绑状态
                    stats = await flashbot_w3.flashbots.get_bundle_stats(bundle_hash)
                    print(f"Bundle Stats: {stats}")

                    print(f"Enable Presale Tx Hash: {tx_hash}")
                    print(f"Presale Tx Hash: {signed_presale['hash'].hex()}")

                    ws.close()
                    break
            except Exception as e:
                print(f"Error processing tx {tx_hash}: {e}")
        await asyncio.sleep(0.1)

if __name__ == "__main__":
    asyncio.run(listen_pending_transactions())