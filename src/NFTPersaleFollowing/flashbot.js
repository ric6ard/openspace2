import { ethers } from "ethers";
import { FlashbotsBundleProvider } from "@flashbots/ethers-provider-bundle";
import * as dotenv from "dotenv";
import * as path from "path";
import { fileURLToPath } from "url";
import WebSocket from "ws"; // 直接使用ws模块

// 加载.env文件(从上级目录)
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../../.env') });

// Alchemy API URL更新
const mainnet = {
  rpc: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
  // 正确的WebSocket格式
  ws: `wss://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
  flashbots: "https://relay.flashbots.net"
};

const sepolia = {
  rpc: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
  // 正确的WebSocket格式 - .ws.alchemyapi.io 改为 .g.alchemy.com
  ws: `wss://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
  flashbots: "https://relay-sepolia.flashbots.net"
};

// 获取环境变量
const NETWORK = "sepolia";
const CONTRACT_ADDRESS = "0xa4010fa5a816747f9eba1a60271280beaae28f10";
const OWNER_ADDRESS = "0xE9d2E42129C04f5627f7894aABD422B8a76737aD";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ETHEREUM_RPC_URL = NETWORK === "mainnet" ? mainnet.rpc : sepolia.rpc;
const FLASHBOTS_RELAY_URL = NETWORK === "mainnet" ? mainnet.flashbots : sepolia.flashbots;
const WS_URL = NETWORK === "mainnet" ? mainnet.ws : sepolia.ws;

// 验证环境变量
if (!process.env.ALCHEMY_API_KEY) {
  console.error("错误: 缺少ALCHEMY_API_KEY。请在.env文件中设置");
  process.exit(1);
}

if (!PRIVATE_KEY) {
  console.error("错误: 缺少私钥。请在.env文件中设置PRIVATE_KEY");
  process.exit(1);
}

// 手动WebSocket管理
async function setupWebSocketListener(url, callback) {
  return new Promise((resolve, reject) => {
    try {
      console.log(`连接到WebSocket: ${url}`);
      const ws = new WebSocket(url);
      
      ws.on('open', () => {
        console.log('WebSocket连接已建立');
        
        // 发送订阅请求
        const subscription = {
          "jsonrpc": "2.0", 
          "id": 1, 
          "method": "eth_subscribe", 
          "params": [
            "alchemy_pendingTransactions",
            {
              // "fromAddress": OWNER_ADDRESS,
              // "toAddress": CONTRACT_ADDRESS,
              "hashesOnly": true
            }
          ]
        };
        
        ws.send(JSON.stringify(subscription));
        console.log('已发送订阅请求');
        
        resolve(ws);
      });
      
      ws.on('message', (data) => {
        try {
          const message = JSON.parse(data.toString());
          callback(message);
        } catch (e) {
          console.error('解析消息失败:', e);
        }
      });
      
      ws.on('error', (error) => {
        console.error('WebSocket错误:', error);
      });
      
      ws.on('close', () => {
        console.log('WebSocket连接已关闭');
      });
      
    } catch (error) {
      console.error('设置WebSocket失败:', error);
      reject(error);
    }
  });
}

async function main() {
  // 连接到以太坊RPC
  console.log("连接到以太坊RPC:", ETHEREUM_RPC_URL);
  const httpProvider = new ethers.providers.JsonRpcProvider(ETHEREUM_RPC_URL);

  // 创建钱包
  const wallet = new ethers.Wallet(PRIVATE_KEY, httpProvider);
  console.log("钱包地址:", wallet.address);
  
  // 获取网络信息
  const network = await httpProvider.getNetwork();
  console.log("连接到网络:", network.name, "链ID:", network.chainId);
    
  // enablePresale 函数选择器
  const enablePresaleSelector = ethers.utils.id('enablePresale()').slice(0, 10);
  console.log("enablePresale 函数选择器:", enablePresaleSelector);

  try {
    // 创建Flashbots provider
    console.log("连接到Flashbots中继:", FLASHBOTS_RELAY_URL);
    const flashbotsProvider = await FlashbotsBundleProvider.create(
      httpProvider, 
      wallet, 
      FLASHBOTS_RELAY_URL
    );
    console.log("Flashbots httpProvider创建成功");

    // 设置WebSocket监听
    const wsListener = await setupWebSocketListener(WS_URL, (message) => {
      // 处理WebSocket消息
      if (message.params && message.params.result) {
        const txHash = message.params.result;
        console.log("检测到新交易:", txHash);
        
        // 这里可以添加交易处理逻辑
        processTransaction(txHash, httpProvider, flashbotsProvider, wallet);
      }
    }).catch(error => {
      console.error("WebSocket设置失败，使用轮询模式作为备份");
      // 可以实现一个备份的轮询机制
    });
    
    // 示范Flashbots bundle (可选)
    await demoFlashbotsBundle(httpProvider, flashbotsProvider, wallet, network);
    
    console.log("\n程序继续运行以监听交易...");
    // 保持程序运行
    await new Promise((resolve) => setTimeout(resolve, 24 * 60 * 60 * 1000)); // 24小时
    
  } catch (error) {
    console.error("Flashbots操作失败:", error);
  }
}

// 处理检测到的交易
async function processTransaction(txHash, provider, flashbotsProvider, wallet) {
  try {
    const tx = await provider.getTransaction(txHash);
    console.log("处理交易:", tx);
    if (!tx) return;
    
    // 检查是否是enablePresale交易
    if (tx.data && tx.data.startsWith("0xa8eac4")) {
      console.log("找到enablePresale交易!");
      
      // 准备presale交易
      const nonce = await provider.getTransactionCount(wallet.address);
      const presaleTx = {
        to: tx.to,
        data: "0x03825e4e0000000000000000000000000000000000000000000000000000000000000001", // presale(1)
        value: ethers.utils.parseEther("0.01"),
        gasLimit: 200000,
        maxFeePerGas: ethers.utils.parseUnits("10", "gwei"),
        maxPriorityFeePerGas: ethers.utils.parseUnits("5", "gwei"),
        nonce: nonce,
        type: 2,
        chainId: tx.chainId
      };
      
      // 发送Flashbots bundle
      await sendFlashbotsBundle(provider, flashbotsProvider, wallet, tx, presaleTx);
    }
  } catch (error) {
    console.error("处理交易失败:", error);
  }
}

// 发送Flashbots bundle
async function sendFlashbotsBundle(provider, flashbotsProvider, wallet, enableTx, presaleTx) {
  try {
    const targetBlock = await provider.getBlockNumber() + 1;
    console.log(`准备发送bundle到区块: ${targetBlock}`);
    
    // 签名bundle
    const signedBundle = await flashbotsProvider.signBundle([
      { 
        signer: wallet,
        transaction: presaleTx
      }
    ]);
    
    const bundleReceipt = await flashbotsProvider.sendRawBundle(
      signedBundle,
      targetBlock
    );
    
    console.log("Bundle已发送, Hash:", bundleReceipt.bundleHash);
    
    // 等待结果
    const waitResponse = await Promise.race([
      bundleReceipt.wait(),
      new Promise((resolve) => setTimeout(() => resolve("超时"), 30000))
    ]);
    
    if (waitResponse === "超时") {
      console.log("Bundle等待超时");
    } else {
      console.log("Bundle结果:", waitResponse);
    }
    
  } catch (error) {
    console.error("发送bundle失败:", error);
  }
}

// 示范Flashbots bundle
async function demoFlashbotsBundle(provider, flashbotsProvider, wallet, network) {
  const nonce = await provider.getTransactionCount(wallet.address);
  const targetBlock = await provider.getBlockNumber() + 1;
  
  console.log("当前区块:", await provider.getBlockNumber());
  console.log("目标区块:", targetBlock);
  
  // 创建一个示例交易
  const exampleTx = {
    to: wallet.address,  // 发送给自己避免浪费ETH
    value: ethers.utils.parseUnits("0.0000001", "ether"),
    gasLimit: 21000,
    maxFeePerGas: ethers.utils.parseUnits("10", "gwei"),
    maxPriorityFeePerGas: ethers.utils.parseUnits("5", "gwei"),
    nonce: nonce,
    type: 2,
    chainId: network.chainId
  };
  
  console.log("示例交易已准备");
  
  try {
    // 签名bundle
    const signedBundle = await flashbotsProvider.signBundle([
      { 
        signer: wallet,
        transaction: exampleTx
      }
    ]);
    
    // 发送bundle
    const bundleReceipt = await flashbotsProvider.sendRawBundle(
      signedBundle,
      targetBlock
    );
    
    console.log("示例Bundle发送结果:", bundleReceipt.bundleHash);
  } catch (error) {
    console.error("示例Bundle发送失败:", error);
  }
}

// 执行主函数
main().catch((error) => {
  console.error("执行失败:", error);
  process.exit(1);
});