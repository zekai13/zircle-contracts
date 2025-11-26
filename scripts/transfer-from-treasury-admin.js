const { ethers } = require('ethers');
require('dotenv').config();

// 配置
const RPC_URL = process.env.RPC_BASE_SEPOLIA;
const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY; // 使用部署者私钥（有管理员权限）
const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS;
const ZIR_TOKEN_ADDRESS = process.env.ZIR_TOKEN_ADDRESS;
const ESCROW_ADDRESS = process.env.ESCROW_ADDRESS;

// 转账金额：10万ZIR (6位小数)
const AMOUNT = ethers.parseUnits('100000', 6); // 100,000 ZIR

async function transferFromTreasury() {
    try {
        console.log('=== 从Treasury转账到托管地址 ===');
        console.log(`RPC URL: ${RPC_URL}`);
        console.log(`Treasury地址: ${TREASURY_ADDRESS}`);
        console.log(`ZIR代币地址: ${ZIR_TOKEN_ADDRESS}`);
        console.log(`托管地址: ${ESCROW_ADDRESS}`);
        console.log(`转账金额: ${ethers.formatUnits(AMOUNT, 6)} ZIR`);
        console.log();

        // 创建provider和wallet
        const provider = new ethers.JsonRpcProvider(RPC_URL);
        const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
        
        console.log(`使用账户: ${wallet.address}`);
        
        // 检查ETH余额
        const ethBalance = await provider.getBalance(wallet.address);
        console.log(`ETH余额: ${ethers.formatEther(ethBalance)} ETH`);
        
        if (ethBalance < ethers.parseEther('0.001')) {
            console.log('❌ ETH余额不足，无法支付gas费用');
            return;
        }

        // 创建Treasury合约实例
        const treasuryABI = [
            "function withdraw(address token, address to, uint256 amount) external",
            "function balanceOf(address token) external view returns (uint256)"
        ];
        const treasury = new ethers.Contract(TREASURY_ADDRESS, treasuryABI, wallet);

        // 检查Treasury中的ZIR余额
        console.log('检查Treasury ZIR余额...');
        const treasuryZirBalance = await treasury.balanceOf(ZIR_TOKEN_ADDRESS);
        console.log(`Treasury ZIR余额: ${ethers.formatUnits(treasuryZirBalance, 6)} ZIR`);

        if (treasuryZirBalance < AMOUNT) {
            console.log('❌ Treasury ZIR余额不足');
            return;
        }

        // 执行转账
        console.log('执行转账...');
        const tx = await treasury.withdraw(ZIR_TOKEN_ADDRESS, ESCROW_ADDRESS, AMOUNT);
        console.log(`交易哈希: ${tx.hash}`);
        console.log('等待确认...');
        
        const receipt = await tx.wait();
        console.log(`✅ 转账成功！`);
        console.log(`区块号: ${receipt.blockNumber}`);
        console.log(`Gas使用: ${receipt.gasUsed.toString()}`);

        // 验证转账结果
        console.log('\n=== 验证转账结果 ===');
        const zirABI = ["function balanceOf(address) external view returns (uint256)"];
        const zirToken = new ethers.Contract(ZIR_TOKEN_ADDRESS, zirABI, provider);
        
        const escrowBalance = await zirToken.balanceOf(ESCROW_ADDRESS);
        console.log(`托管地址ZIR余额: ${ethers.formatUnits(escrowBalance, 6)} ZIR`);
        
        const newTreasuryBalance = await treasury.balanceOf(ZIR_TOKEN_ADDRESS);
        console.log(`Treasury剩余ZIR: ${ethers.formatUnits(newTreasuryBalance, 6)} ZIR`);

    } catch (error) {
        console.error('❌ 转账失败:', error.message);
        if (error.reason) {
            console.error('错误原因:', error.reason);
        }
    }
}

// 运行脚本
transferFromTreasury();
