# Base Sepolia Deployment Summary

Generated: 2025-10-28

## Operator
- Deployer address: `0x7c5DA45c3631E91f4D2DC9F53f706775787dBF1E`

## Environment
- Network: Base Sepolia (`chainId 84532`)
- RPC endpoint: `https://sepolia.base.org`
- EntryPoint (ERC-4337): `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`
- Price feed: `MockV3Aggregator` (deployed automatically)

## Contracts Deployed
| Module | Address |
| --- | --- |
| AccessController | `0x53Cb056265Ca1E8F9765FA65fb81452ECE33BA38` |
| FeatureFlags | `0xaA3FD0fa40fDb0fd470dd522431DB4b50e94EeE3` |
| Registry | `0xB0247C0E85bA4Aa39a7759BAeCa07D35D2f5021a` |
| ZIR Token | `0x23De97EFff253935ba6c631ef8197A02EB1608Cd` |
| PriceOracle | `0x6a021Cc72E296666F2F50d0DeEd4c7ca20dD3139` |
| TreasuryModule | `0x4c37F8D06083775eC2d36716E6Fb2Ccf12aD256f` |
| ReputationModule | `0xaf1b13a60c38D9D4c46f60eA0d3BDD29880e14d2` |
| StakingModule | `0xF6faf0875A36901Fe5FC005B41183334dCFfcCC7` |
| Escrow | `0xa1eb0e60694680d25CBd8C0C1B50d673D03b575F` |
| ZIRDistributor | `0x3DACc7b689FE2C41D5a9A94601E370Ec9D4b8860` |
| VestingLinear | `0x28179a0E0a174d6dA139da39CA5f034114CCf68a` |
| VestingMerkle | `0x0C772F866B41e9bd156606A78606c247563C7d06` |
| Aggregator (external) | `0x3daf9F1331807cE109f9721682BC548854408FB2` |

## Escrow Upgrade Procedure
Use `scripts/upgrade-escrow.sh` to deploy a fresh `Escrow` implementation and upgrade the proxy (`0xa1eb0e60694680d25CBd8C0C1B50d673D03b575F`). The script wraps the exact steps we have been running manually.

1. Populate `.env.deploy` with at least `RPC_URL`, `PRIVATE_KEY`, and add `PROXY_ADDRESS=0xa1eb0e60694680d25CBd8C0C1B50d673D03b575F`.
2. Ensure the private key has sufficient ETH on Base Sepolia and Foundry is up-to-date (`foundryup`).
3. Run:
   ```bash
   bash scripts/upgrade-escrow.sh
   ```
4. The script emits the new implementation address (stored as `latest-escrow-impl-<timestamp>.json`), broadcasts the UUPS upgrade, and prints the implementation slot for quick verification.
5. After validating, clean up sensitive artifacts:
   ```bash
   rm latest-escrow-impl-*.json
   cast wallet remove deployer  # if you imported the key
   ```

If you prefer to execute the steps manually,参考脚本使用 `forge create contracts/modules/escrow/Escrow.sol:Escrow` 部署实现，再调用 `forge script scripts/UpgradeModuleUUPS.s.sol --broadcast` 完成升级。

## Transaction Logs
- Broadcast bundle saved at `broadcast/DeployBase.s.sol/84532/run-latest.json`.
- Total gas consumed: `32,003,074`.
- Total ETH spent: `0.000032004836458064`.

## Follow-up Recommendations
1. Verify contract source code on the Base Sepolia block explorer.
2. Execute post-deployment smoke tests (FeatureFlags toggles, Escrow lifecycle, Staking rewards, Distributor claims).
3. Replace mock price feed with production oracle when ready and update configuration on-chain.
4. Store this file in release notes together with transaction hashes for audit trail.

## Key Material (local testing only)
- Deployer private key: `0xa9bd3f0c051c9522bea3e0546a20d617094e6a4c8a774a2acda8e7473a841bc6` → `0x7c5DA45c3631E91f4D2DC9F53f706775787dBF1E`
- Buyer private key: `0xb3cf93bc9a10f562e1870efde427857090b434238bac36f548985af816a6cdb9` → `0xA4Cc4c627Ba3ce9D072487Ad1A7df3A442156655`
- Seller private key: `0xd42164f8a13a31a44cc799a6c7f8d0cba5f652c752aa6ea7c74741d02c1e9319` → `0x82BfDBFF67eEAb47F8aF9032df7102566B7b06eE`
- Staker private key: `0x0bdcfb88fa2a88942fa00a696c1afd85384979ed092361a1aeb998e34bd4a52b` → `0xB2d7B5cb601C4b3BFe5C5996Ee3A3cAc6ED0B324`
- Beneficiary private key: `0x6a508d9435ceae232b7b9ea6b963e8a5214302fc44b8de42f39dae6aed81c8b3` → `0x0EbE7e5f25a59ECB5d33A2b956DE687E4E13E16d`
- Distributor signer private key: `0xa9bd3f0c051c9522bea3e0546a20d617094e6a4c8a774a2acda8e7473a841bc6` → `0x7c5DA45c3631E91f4D2DC9F53f706775787dBF1E`

## Source-code verification checklist
To verify a contract on Base Sepolia (requires `ETHERSCAN_API_KEY` in `.env`):
```bash
forge verify-contract \
  --chain-id 84532 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  <contract-address> \
  <path/to/Contract.sol:ContractName> \
  --constructor-args <hex-encoded-args>
```
Helpful constructors:
- FeatureFlags: `constructor(address accessController_)`
- ZIR: `constructor(address accessController_, address featureFlags_, address treasury_)`
- Escrow (implementation): no constructor args; initialize via `initialize(address accessController, address featureFlags)` on the proxy after deployment。
- ZIRDistributor: `constructor(address accessController_, address featureFlags_, address zirToken_, address signer_)`

Use `cast abi-encode` to produce constructor args, e.g.:
```bash
cast abi-encode "constructor(address,address,address)" \
  0xC1c502a474480Df4C0DCa641fFA96a6cF66e6Fb1 \
  0xE5E4B610e5634103550DEFD4f1E739946a984178 \
  0x9B2b539938dB144baae9F14512B8B25DA40B178d
```

### Next actions
1. Complete remaining source verifications and attach explorer URLs here.
2. Archive this scenario section alongside future smoke-test runs for regression tracking.
