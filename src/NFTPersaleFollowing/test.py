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

# 发送交易
tx = {
    "from": Account.from_key(PritateKey).address,
    "to": contract_address,
    "data": enable_presale_selector,
    "value": 0,
    "gas": 100000,
    "gasPrice": 1,
    "nonce": w3.eth.get_transaction_count(Account.from_key(PritateKey).address),
}


bundle_txs = [tx]
current_block = w3.eth.block_number
target_block = current_block + 1
# target_block_hex = hex(target_block)
print(f"Bundle Tx: {bundle_txs}")
print(f"Type: {type(target_block)}, Target Block: {target_block}")

# 发送捆绑
send_result = flashbot_w3.flashbots.send_bundle(bundle_txs, target_block)
