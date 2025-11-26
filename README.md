# Zircle Contracts

Zircle 的链上协议代码库，覆盖 Base Sepolia 上的代币、金库、信誉、质押、托管、预言机、分发与解锁等模块。所有核心合约均通过 UUPS 代理部署，方便后续升级与治理。

## 核心组件
- AccessController & FeatureFlags：权限与功能开关的双层管控。
- Registry：模块发现与地址目录，便于前后端读取。
- ZIR：协议原生代币，内置金库授权。
- PriceOracle：链上/模拟预言机包装，支持喂价过期与跳变控制。
- TreasuryModule：金库与费用路由、回购/销毁、模块额度管理。
- ReputationModule / StakingModule：信誉累积与 ZIR 质押。
- Escrow：买卖双方托管、发货/收货流程、争议/延期处理。
- ZIRDistributor & Vesting(Linear/Merkle)：空投/奖励发放与线性/白名单解锁。

## 目录速览
- `contracts/`：合约源码与接口、库。
- `script/`：主要部署脚本（例如 `DeployBase.s.sol`）。
- `scripts/`：运维脚本（升级、金库操作、托管转账等）。
- `test/`：单元与不变量测试。
- `broadcast/`：历史部署/脚本广播记录。
- `deployments/`：已部署地址的快照。
- `AUDIT_OVERVIEW.md`、`AUDIT_REPORT.md`：审计摘要与详细报告。

## 快速开始
```bash
# 安装 Foundry（若未安装）
curl -L https://foundry.paradigm.xyz | bash
foundryup

git clone https://github.com/zekai13/zircle-contracts.git
cd zircle-contracts
git submodule update --init --recursive

cp .env.example .env  # 按需填写 RPC、私钥与地址
forge build
```

## 环境变量
使用 `.env.example` 作为模板，勿提交真实私钥。关键字段：
- `RPC_URL` / `RPC_BASE_SEPOLIA`：目标节点。
- `PRIVATE_KEY` / `DEPLOYER_ADDRESS` / `DISTRIBUTOR_SIGNER`：部署/签名账户（仅限测试私钥）。
- `ENTRY_POINT`：ERC-4337 入口（Base Sepolia 默认为 `0x5FF1...`）。
- `AGGREGATOR_ADDRESS`：已有价格预言机地址，留空则部署 `MockV3Aggregator`。
- `NATIVE_USD_PRICE`、`ORACLE_EXPIRY`、`ORACLE_MAX_CHANGE_BPS` 等：预言机参数。
- `DEPLOY_PERSIST_FILES=true`：部署后将地址写入 `deployments/base_sepolia_<timestamp>.json` 和 `.env`。

## 测试
```bash
forge test              # 常规测试
forge test -vvv         # 输出更详细日志
forge test --match-path test/invariant/*  # 不变量/属性测试
```

## 部署（Base Sepolia 示例）
```bash
source .env
forge script script/DeployBase.s.sol:DeployBase \
  --rpc-url $RPC_URL \
  --broadcast
```
环境变量中可预设喂价、费用参数、是否使用外部预言机等。开启 `DEPLOY_PERSIST_FILES=true` 可自动生成地址清单与 `.env` 片段，便于前端/运维引用。

## 运维脚本
- `scripts/UpgradeModuleUUPS.s.sol`：升级任意 UUPS 模块。
- `scripts/TreasuryOps.s.sol`、`scripts/transfer-treasury-to-escrow.sh`：金库授权、资金划转。
- `scripts/QueryCustodyBalance.s.sol`：查询托管/金库余额。
- `scripts/transfer-from-treasury-admin.js`：通过管理员密钥从金库转账（请确保只在安全环境使用）。

## 其他文档
- `AUDIT_OVERVIEW.md` / `AUDIT_REPORT.md`：审计材料。
- `DEPLOYMENT_BASE_SEPOLIA.md`：现网部署说明与地址汇总。
