#!/bin/bash

# 加载环境变量
source .env

echo "=== 从Treasury转账到托管地址 ==="
echo "Treasury地址: $TREASURY_ADDRESS"
echo "ZIR代币地址: $ZIR_TOKEN_ADDRESS"
echo "托管地址: $ESCROW_ADDRESS"
echo "转账金额: 100,000 ZIR"
echo

# 检查Treasury ZIR余额
echo "检查Treasury ZIR余额..."
TREASURY_BALANCE=$(cast call $ZIR_TOKEN_ADDRESS "balanceOf(address)" $TREASURY_ADDRESS --rpc-url $RPC_BASE_SEPOLIA)
echo "Treasury ZIR余额: $(python3 -c "print($TREASURY_BALANCE / 10**6, 'ZIR')")"
echo

# 检查托管地址当前余额
echo "检查托管地址当前余额..."
ESCROW_BALANCE=$(cast call $ZIR_TOKEN_ADDRESS "balanceOf(address)" $ESCROW_ADDRESS --rpc-url $RPC_BASE_SEPOLIA)
echo "托管地址ZIR余额: $(python3 -c "print($ESCROW_BALANCE / 10**6, 'ZIR')")"
echo

# 执行转账 (10万ZIR = 100000000000 wei)
echo "执行转账..."
cast send $TREASURY_ADDRESS "withdraw(address,address,uint256)" \
    $ZIR_TOKEN_ADDRESS \
    $ESCROW_ADDRESS \
    100000000000 \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --rpc-url $RPC_BASE_SEPOLIA

echo
echo "=== 验证转账结果 ==="

# 检查转账后的余额
NEW_ESCROW_BALANCE=$(cast call $ZIR_TOKEN_ADDRESS "balanceOf(address)" $ESCROW_ADDRESS --rpc-url $RPC_BASE_SEPOLIA)
echo "托管地址新余额: $(python3 -c "print($NEW_ESCROW_BALANCE / 10**6, 'ZIR')")"

NEW_TREASURY_BALANCE=$(cast call $ZIR_TOKEN_ADDRESS "balanceOf(address)" $TREASURY_ADDRESS --rpc-url $RPC_BASE_SEPOLIA)
echo "Treasury新余额: $(python3 -c "print($NEW_TREASURY_BALANCE / 10**6, 'ZIR')")"

echo
echo "✅ 转账完成！"
