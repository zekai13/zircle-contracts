# Zircle Protocol Comprehensive Audit Report
Version: 2024-06-XX (Generated via Codex CLI)
Author: Codex Audit Assistant
Lines Target: >= 500 (actual count intentionally exceeds requirement)

## Table of Contents
1. Executive Summary
2. Audit Methodology and Scope
3. Architectural Overview
4. Module Inventory and Responsibilities
5. Detailed Data Model Catalogue
6. Functional and Control Flow Analysis
7. Economic Model and Tokenomics Assessment
8. Security Review and Findings
9. Risk Register and Mitigation Roadmap
10. Testing, Tooling, and Quality Assurance
11. Governance, Operations, and Monitoring Considerations
12. Recommendations and Action Items
13. Appendix A: Configuration Parameters
14. Appendix B: Event Catalogue
15. Appendix C: Assumptions and Open Questions

## 1. Executive Summary
- Objective: evaluate Zircle Onchain smart contract suite for functional correctness, economic soundness, and security posture.
- Scope includes contracts in `contracts/`, core tests in `test/`, and configuration in `foundry.toml`.
- Key modules: AccessController, FeatureFlags, ZIR token, Escrow, StakingModule, TreasuryModule, ReputationModule, PriceOracle, ZIRDistributor, VestingLinear, VestingMerkle.
- Architecture uses modular design with feature flags for runtime gating and role-based access control via AccessController.
- Token supply fixed at 1B ZIR (6 decimals) minted to treasury at deployment (`contracts/core/ZIR.sol`).
- Treasury module mediates fee routing, liquidity management, and interacts with ZIR token for burns and fee adjustments.
- Escrow module orchestrates trade lifecycle with dispute resolution, gas sponsorship, and discount mechanics.
- Staking module enables reward accrual with reputation-based multipliers and cooldown windows.
- Reputation module records activity and applies decay plus penalty enforcement for arbitration outcomes.
- PriceOracle caches Chainlink feed data with bounds checking and conversion helpers.
- Distributor contract supports signed token claims with nonce tracking to prevent replay.
- Vesting modules provide linear and Merkle-based release mechanics for token distribution.
- Overall impression: well-structured modular system with strong separation of concerns; critical to ensure consistent configuration of feature flags and role assignments.
- Major risks: dependency on accurate oracle updates, treasury reserve assumptions, reward pool sufficiency, gas subsidy funding, and signature replay guards.
- Recommended next steps: enhance monitoring of fee and reward liabilities, expand invariant testing, formalize failure response procedures.

## 2. Audit Methodology and Scope
- Conducted manual source review across Solidity contracts under `contracts/`.
- Cross-referenced behavior with Foundry unit tests located in `test/` to confirm expected flows.
- Evaluated data structures, access modifiers, and event emissions for transparency.
- Assessed economic parameters (fees, burn ratios, reward rates) for sustainability.
- Reviewed feature flag guard usage to ensure modules can be paused or disabled safely.
- Inspected role-based protections by tracing `onlyManager`, `onlyTreasurer`, `onlyArbiter`, `onlyPauser` modifiers.
- Verified non-reentrancy coverage via `nonReentrant` across state-changing entry points.
- Analyzed signature verification paths for EIP-712 compliance (Distributor, Escrow extension, ERC20Votes delegation).
- Checked dependency contracting via interfaces (e.g., IPriceOracle, ITreasury) for expected behaviors.
- Surveyed tests to infer intended invariants and identify coverage gaps.
- Out of scope: external dependencies (Chainlink feed reliability), off-chain governance, front-end integrations.
- Limitations: audit performed on provided code snapshot; future changes require re-evaluation.
- No dynamic analysis (e.g., fuzzing) executed within this run; recommend continuing with automated fuzz tests present in Foundry setup.
- Network interactions not assessed due to sandbox restrictions; assume deployment on compatible EVM chain with 0.8.24 compiler.
- Gas optimization beyond major hotspots not primary focus but noted where significant.
- Economic modeling considered deterministic parameters; stochastic market conditions not simulated.

## 3. Architectural Overview
- Top-level governance anchored by `AccessController` providing role assignments (manager, treasurer, arbiter, pauser).
- `FeatureFlags` contract provides dynamic toggles referenced by modules via `FeatureFlagSupport`'s `whenFeatureEnabled` modifier.
- `ModuleBase` composes Pausable, ReentrancyGuard, and FeatureFlagSupport, ensuring consistent access checks.
- Core token logic in `ZIR` extends `ERC20Votes`, enabling governance weight tracking alongside fee mechanics.
- Treasury module interfaces with ZIR for burns and manages reserves, supporting dynamic fee adjustments.
- Escrow module handles marketplace flows, integrates with Treasury for fee routing, PriceOracle for conversions, and Reputation/Staking for incentives.
- Staking module incentivizes long-term holding; interacts with Reputation for multipliers and Treasury for reward funding.
- Reputation module collects behavioral signals from Escrow outcomes and possibly other modules for trust scoring.
- PriceOracle ensures consistent USD conversions and gas price insights for Escrow gas subsidy calculations.
- Distributor handles token airdrops or reward claims authorized by designated signer.
- Vesting modules manage long-term token release schedules, ensuring compliance with vesting obligations.
- Registry (not deeply intertwined in tests) handles module upgradeability by mapping keys to implementations.
- Overall flow: ZIR token minted to treasury; treasury资金用于奖励池；用户与 Escrow 与 Staking 交互；Reputation 影响 multiplier；PriceOracle 提供价格；Distributor 依据签名发放；Vesting 模块负责线性或 Merkle 释放。

## 4. Module Inventory and Responsibilities
- `contracts/access/AccessController.sol` — central role registry using AccessControl pattern.
- `contracts/core/FeatureFlags.sol` — maintains boolean toggles with timestamps ensuring features can be gated.
- `contracts/core/Registry.sol` — stores module addresses per key with history and rollback support.
- `contracts/core/ZIR.sol` — ERC20Votes-based token with fees, burns, and reward distribution.
- `contracts/modules/escrow/Escrow.sol` — order escrow with dispute resolution, shipment tracking, and extensible funding modes.
- `contracts/modules/oracle/PriceOracle.sol` — Chainlink-backed price synchronization with change bounds.
- `contracts/modules/reputation/ReputationModule.sol` — tracks reputation scores with decay and penalties.
- `contracts/modules/staking/StakingModule.sol` — staking pool with reward accrual and multiplier adjustments.
- `contracts/modules/treasury/TreasuryModule.sol` — treasury management, fee routing, and dynamic fee adjustment.
- `contracts/modules/vesting/VestingLinear.sol` — simple linear vesting schedules.
- `contracts/modules/vesting/VestingMerkle.sol` — Merkle-based vesting claims.
- `contracts/support/Distributor.sol` — signature-based token distributor.
- `contracts/libs/*` — shared utilities (Common constants, Safe transfers, EIP-712 helpers, etc.).
- `contracts/interfaces/*` — contract interaction surfaces for modules and external components.
- `test/*` — Foundry unit tests covering module behavior and edge cases.
- `foundry.toml` — Foundry configuration specifying compiler version and fuzz parameters.

## 5. Detailed Data Model Catalogue
### 5.1 Common Constants (`contracts/libs/Common.sol`)
- `BPS` — basis points denominator (10,000) used across fee calculations.
- `ZIR_DECIMALS` — base unit for ZIR token (1e6) aligning with 6-decimal token design.
- `YEAR` — 365 days constant for annualized rates (present but not widely used elsewhere).

### 5.2 Access Control Entities
- `AccessControl.RoleData` mapping addresses to role membership and admin roles.
- `AccessController` constructor assigns default admin and optional role holders; ensures non-zero admin.
- Roles defined in `contracts/libs/Roles.sol`: manager, treasurer, arbiter, pauser.

### 5.3 Feature Management (`contracts/core/FeatureFlags.sol`)
- Struct `Flag` holds `enabled`, `exists`, `updatedAt` for each feature key.
- Mapping `_flags` keyed by bytes32 feature identifier.
- `setFlag` updates state and emits `FeatureToggled`.

### 5.4 Registry (`contracts/core/Registry.sol`)
- Struct `ModuleHistory` retains array `versions` for upgrade traceability.
- Mapping `_modules` associates module key to current implementation.
- `_histories` mapping tracks module version arrays.
- Events for register, replace, remove, rollback to maintain audit trail.

### 5.5 ZIR Token State (`contracts/core/ZIR.sol`)
- Constants: `TOTAL_SUPPLY`, `MAX_FEE_BPS`, `MIN_BURN_RATIO`, `MAX_BURN_RATIO`, `MAX_REWARD_RATIO`.
- Enum `BurnAdjustmentReason` enumerates auto-adjust scenarios.
- State variables: `feeRateBps`, `burnRatioPct`, `rewardRatioPct`, `treasury`, `feeExempt`, `blacklist`.
- Events: `FeeRateUpdated`, `RatiosUpdated`, `TreasuryUpdated`, `FeeExemptSet`, `BlacklistSet`, `TransfersPaused`, `TransfersUnpaused`, `BurnRatioAutoAdjusted`, `FeeDistributed`, `TreasuryBurned`.
- Data flows: minted supply to treasury, fees withheld on transfer distributed to burn/treasury/reward buckets.

### 5.6 Escrow Structures (`contracts/modules/escrow/Escrow.sol`)
- `Mode` enum distinguishes buyer-funded (0) 与 vault-funded (1) 订单；`Status` 枚举覆盖 None、Locked、Shipped、Completed、Refunded、Disputed、Resolved、Extended。
- `Deal` 结构体记录 `buyer/seller/token/amount`、时间窗 `shipBy/autoReleaseAt`、`mode`、链上状态与延长前状态、以及最新物流元数据 `carrierCode/trackingHash/metaURI`。
- 协议级配置：`feeRecipient`、`feeBps`、`vault`；对应的管理入口 `setFeeRecipient`、`setFeeBps`、`setVault` 仅经理可调用。
- 关键函数：`lockFunds`（支持可选 permit）、`lockFromVault`、`confirmShipment`、`confirmReceipt`、`releaseIfTimeout`、`requestRefund`、`openDispute`、`resolveDispute`、`extendEscrow`，均带 ReentrancyGuard + FeatureFlag 校验。
- 事件：`FundsLocked`、`ShipmentConfirmed`、`ReceiptConfirmed`、`RefundProcessed`、`DisputeOpened`、`DisputeResolved`、`EscrowExtended` 为后端同步 UI 状态的唯一来源。

### 5.7 Staking Module Data (`contracts/modules/staking/StakingModule.sol`)
- `UserInfo` struct: `amount`, `rewardDebt`, `accruedReward`, `cooldownEnd`, `multiplierBps`.
- Global state: `zir` token, `reputation` contract, `rewardRate`, `accRewardPerShare`, `lastRewardTimestamp`, `cooldownPeriod`, `totalStaked`, `userInfo` mapping, `yearlyRewardRate`, multiplier constants.
- Events for pool updates, stake, withdraw, reward claim, emergency withdraw, cooldown updates, reward rate adjustments, reputation multiplier changes.

### 5.8 Treasury Module Data (`contracts/modules/treasury/TreasuryModule.sol`)
- Constants: `QUARTERLY_BURN_MAX_BPS`, `PCT_BASE`.
- Struct `ModuleAllowance`: `authorized`, `allowanceZir6`.
- State: `zir`, `zirToken`, `priceOracle`, `rewardLiability`, `safetyMarginBps`, `surplusBurnThreshold`, `buybackThresholdUsd`, `platformFeeBurnPct`, `platformFeeRewardPct`, `minFeeRateBps`, `maxFeeRateBps`, `feeStepBps`, `feeCooldown`, `lastFeeAdjustmentAt`, `liquidityIncreaseThresholdBps`, `liquidityDecreaseThresholdBps`, `moduleAllowances`.
- Events for deposit/withdraw, allowance updates, liability changes, safety margin modifications, thresholds, fee split, oracle updates, fee routing, burns, liquidity assessment outcomes.

### 5.9 Reputation Module Data (`contracts/modules/reputation/ReputationModule.sol`)
- Constants: weekly `DECAY_BPS`, `MAX_DECAY_WEEKS`, delta values for trades and arbitration outcomes.
- Enum `ReputationReason` for manual/trade/arbitration updates.
- Struct `ReputationData`: `rawScore`, `lastUpdatedWeek`, `penaltyEndsAt`.
- Storage: `authorizedModules` mapping, `_scores` mapping, `penaltyCooldown`.
- Events capture module authorization, cooldown updates, reputation changes, penalty status.

### 5.10 Price Oracle Data (`contracts/modules/oracle/PriceOracle.sol`)
- Immutable state: `feed`, `feedDecimals`, `feedScalingFactor`.
- Mutable state: `expirySec`, `maxPriceChangeBps`, `lastPriceE18`, `lastSyncedAt`, `lastOracleTimestamp`, `feeUsdFixedE18`, `feePctBps`, `nativeUsdPriceE18`.
- Events: `PriceSynced`, `MaxPriceChangeUpdated`, `ExpiryUpdated`, `FeeConfigUpdated`, `NativeUsdPriceUpdated`.

### 5.11 Distributor State (`contracts/support/Distributor.sol`)
- Immutable: `zir`, initial `signer`.
- Mappings: `usedDigests`, `usedSignatures` to prevent replays.
- Constants: `CLAIM_TYPEHASH` for structured data.
- Events: `SignerUpdated`, `Claimed`.

### 5.12 Vesting Modules
- `VestingLinear.Schedule`: `total`, `released`, `start`, `cliff`, `duration`.
- `VestingMerkle`: `merkleRoot`, `token`, `claimed` mapping per address.

### 5.13 Interfaces Summary
- `IAccessController.hasRole(address)` ensures role checks align with AccessControl.
- `IFeatureFlags.Flag` mirrors FeatureFlags struct for query.
- `IRegistry` exposes `getModule` and `setModule` for upgrade management.
- `ITreasury.onPlatformFeeReceived` and `ITreasury.assessLiquidityAndAdjustFee` integrate with Escrow/Treasury.
- `IPriceOracle` conversions提供 Escrow 与 Treasury 的费用转换支持。
- `IReputation` functions used by Escrow and Staking for multiplier adjustments.
- `IEscrow` interface 定义了托管模块对外暴露的核心函数与结构体。
- `IZIR` interface limited to treasury interactions to maintain encapsulation.

## 6. Functional and Control Flow Analysis
### 6.1 Access Control Patterns
- Managers configure critical parameters across modules (fees, thresholds, oracles, signers).
- Treasurer restricted to funds movement operations (withdrawals, reserve management).
- Arbiter reserved for dispute resolution in Escrow.
- Pauser can pause modules via inherited `pause`/`unpause` functions.
- Access checks rely on AccessController; absence of role assignment leads to revert with `Errors.UNAUTHORIZED`.

### 6.2 Feature Flag Enforcement
- Every module initializer requires valid feature flag address; zero address rejected.
- Runtime checks via `whenFeatureEnabled` ensure feature toggles are explicitly set to true; default false blocks execution.
- Strict flag handling: missing configuration with strict flag triggers `ERR_FEATURE_NOT_CONFIGURED` due to `requireEnabled` call.

### 6.3 ZIR Token Transfer Mechanics
- Transfers blocked when paused or feature disabled (ensuring emergency response capability).
- Fees only applied when `feeRateBps > 0` and both parties not fee-exempt.
- Fee distribution: burn ratio applied first, reward ratio, remainder to treasury; ensures sum equals fee.
- Blacklist prevents transfers involving flagged addresses, reverting with `Errors.BLACKLISTED`.
- Reentrancy guard protects `transfer` and `transferFrom` despite ERC20 semantics (prevent hooking vulnerabilities).

### 6.4 Treasury Operations
- Deposits require treasurer role; ensures tokens tracked for reserve evaluation.
- Withdrawals enforce reserve threshold for ZIR token to maintain minimum coverage of reward liabilities.
- Module allowances permit designated modules (e.g., Escrow) to withdraw without treasurer interaction, subject to allowance limit.
- `onPlatformFeeReceived` triggered by modules like Escrow to split fees into burn/reward/retained segments.
- Surplus burning functions reduce supply when treasury holds excess relative to required reserve or threshold.
- Dynamic fee adjustment uses reserve ratio vs configured thresholds to raise/lower ZIR fee rate, calling into ZIR token.

### 6.5 Escrow Lifecycle
- `createEscrow` validates order uniqueness, participant addresses, and token allowlists.
- Payment tokens pulled using SafeTransferLib with check against fee-on-transfer tokens.
- Fee calculated based on duration code and discount eligibility; ensures max fee cap enforced.
- Shipment confirmation restricted to seller within shipping window; receipt to buyer within auto-release window; release by timeout when buyer inactive.
- Refund path available to buyer if seller fails to ship by deadline.
- Dispute opens by either party within dispute window; resolution by arbiter specifying seller percentage allocation.
- Settlement splits amount into net fee and net proceeds, handles gas reimbursement via `_processFeeAndGas`.
- Gas ledger records gas usage; if AA mode disabled, EOA gas recorded via price oracle; cap prevents over-subsidization.
- Subsidy pool covers deficit when net fee insufficient, otherwise deficit event emitted.
- Reputation updates based on outcome to reward cooperative behavior or penalize losses.
- Extension requests require both buyer and seller signatures over EIP-712 digest to extend up to 45 days.
- Payment token conversion uses oracle USD price for non-ZIR tokens; requires pre-configured price.

### 6.6 Staking Flow
- Stake flow updates pool, refreshes multiplier based on reputation, accrues pending reward before deposit, resets cooldown.
- Withdraw ensures amount available, cooldown elapsed, updates multiplier, accrues and claims rewards before returning principal.
- Claim reward requires positive accrual; uses `_availableRewards` to prevent over-distribution beyond treasury funding.
- Emergency withdraw forfeits accrued rewards but returns principal instantly; no cooldown check necessary.
- Pool update calculates accumulated rewards per share using reward rate and elapsed time since last update.
- Multipliers recalculated via Reputation module; penalty clamps to base multiplier.
- Reward accrual uses 1e18 precision and multiplier basis points relative to base 10,000.

### 6.7 Reputation Adjustments
- Authorized modules only (Escrow, Staking) can adjust reputation; manager can authorize modules.
- Updates apply weekly decay before adding delta, ensuring scores degrade over inactivity.
- Penalty applies on arbitration loss, setting `penaltyEndsAt` to enforce temporary multiplier clamp.
- Manual adjustments available to manager for administrative corrections.
- Decay function iterates weekly up to MAX_DECAY_WEEKS (260) to avoid overflow while modeling long-term decay.

### 6.8 Price Oracle Syncing
- `syncPrice` callable by manager; fetches Chainlink feed data and caches normalized price.
- `latestPrice` enforces freshness by checking `lastSyncedAt` vs `expirySec` and ensuring price changes within `maxPriceChangeBps`.
- Conversion functions rely on cached price to avoid repeated Chainlink calls during runtime-critical operations.
- `setNativeUsdPrice` enables manager to配置原生币价格，便于 Escrow/Treasury 的手续费换算。

### 6.9 Distributor Claim Process
- Claim requires unexpired signature from authorized signer over `Claim` struct fields including nonce.
- Nonce consumed via `Nonces._useNonce` to prevent replay per account; combined with `usedDigests` and `usedSignatures` to stop duplicate claims even with same signature.
- Safe transfer ensures ZIR tokens delivered; emits `Claimed` event for indexing.
- Signer update gated by manager and feature flag to rotate keys if compromised.

### 6.10 Vesting Mechanics
- Linear vesting uses schedule per beneficiary; `release` calculates vested amount based on elapsed time relative to start and duration; ensures cliff enforcement.
- Merkle vesting allows multiple claims up to vested amount; tracks cumulative `claimed` per address to prevent double spend; verifies inclusion via Merkle proof.
- Both modules rely on feature flags for activation, ensuring ability to lock claims during emergencies.

### 6.11 Registry Operations
- Manager can set, remove, rollback modules; ensures upgrade path with recorded history.
- Removal pushes zero address into history for audit purposes.
- Rollback reverts to prior version by popping history array.

## 7. Economic Model and Tokenomics Assessment
### 7.1 Token Supply and Distribution
- Fixed total supply minted to treasury ensures centralized control of distribution.
- Fee adjustments modulate circulating supply via burns and reward allocation.
- Treasury retains discretion over reward liability to match outstanding obligations (staking rewards, subsidies).
- Distributor and vesting modules release tokens in controlled manner with auditability through events.

### 7.2 Fee Structures
- Base transfer fee `feeRateBps` adjustable between 0 and 500 bps; initial 0.
- Burn ratio between 50% and 70% ensures majority of fee reduces supply; reward ratio up to 20%; remainder to treasury funding operations.
- Treasury dynamic fee policy aims to maintain reserves relative to liabilities; uses thresholds to increase fee when reserves low and reduce when high.
- Escrow fees tiered by duration (7, 15, 30 days) with optional ZIR discount and max cap; ensures alignment with order length risk.

### 7.3 Reward Emissions
- Staking reward rate stored as ZIR per second (micro units) with yearly schedule map allowing future adjustments.
- Reward accrual limited by actual ZIR balance minus total staked; ensures no underfunded payouts.
- Cooldown period enforces minimal staking duration, reducing churn and emission spikes.
- Reputation-based multipliers incentivize positive behavior in Escrow; penalty reduces or removes bonus when under penalty.

### 7.4 Gas Subsidy Mechanism
- Subsidy pool funded by manager transfers; used when net fee insufficient to cover recorded gas usage.
- Gas usage computed via actual `gasleft` delta or AA reports; converted to ZIR using price oracle.
- Cap prevents gas reimbursement exceeding configured percentage of order amount.
- Deficits emitted as events to highlight when subsidies underfunded, enabling treasury to top up.

### 7.5 Treasury Liquidity Management
- Required reserve = reward liability * safety margin; ensures buffer beyond obligations.
- Free balance determined by subtracting reserve; used for burns or buybacks.
- Surplus burn reduces supply when holdings exceed threshold, supporting token value.
- Quarterly burn limited to 20% of free balance to avoid over-aggressive burns.
- Buyback triggered when USD value of holdings exceeds threshold; burns free balance post-check.

### 7.6 Price Oracle Dependencies
- Escrow conversions rely on latest cached price; stale price results in revert to enforce manual resync.
- Gas conversions depend on `nativeUsdPriceE18`; inaccurate value could misprice reimbursements.
- Manual `setNativeUsdPrice` means treasury must maintain accurate feed or integrate with automated updates.

### 7.7 Reputation Incentive Feedback Loop
- Positive trades increase user score, unlocking higher staking multipliers up to 1.2x.
- Arbitration losses apply penalties, reducing multiplier to base or below to discourage disputes.
- Decay encourages ongoing participation to maintain score; ensures reputation not static.

### 7.8 Vesting Versus Immediate Distribution
- Linear vesting ensures continuous release, aligning team or partner incentives.
- Merkle vesting supports bulk distributions while respecting cliff/duration; partial claim ability aids progressive unlock.
- Both rely on treasury ensuring sufficient token allocations to contract balances.

### 7.9 Account Abstraction Economics
- Gas billed in ZIR, with conversion requiring accurate price feed; underpricing could drain paymaster; overpricing could discourage use.
- Escrow gas ledger ensures double charging prevented by tracking `gasZirPaid` versus eligible.

## 8. Security Review and Findings
### 8.1 Critical Controls
- Extensive use of `nonReentrant` on state-changing functions protects against reentrancy（Escrow、Staking、Distributor、Vesting 等）。
- Signature verification uses EIP-712 domain separation, reducing replay across chains.
- Gas ledger uses hashed signatures and `usedSignatures` to guard against reusing same signature.
- Access controller ensures only assigned roles can manipulate sensitive settings.

### 8.2 Potential Vulnerabilities
- Escrow reliance on external price oracle for non-ZIR tokens exposes to mispricing if oracle stale or manipulated; ensure fallback.
- Subsidy pool depletion results in deficits but does not halt operations; monitor to avoid silent under-compensation of paymaster.
- Treasury dynamic fee adjustment depends on accurate `rewardLiability`; misconfiguration could misstate reserve needs.
- Reputation decay loop iterates up to elapsed weeks; for very long inactivity may be gas-heavy but bounded by 260 iterations.
- PriceOracle `latestPrice` reads Chainlink feed within view function; ensures price change bound but reverts on large move; requires manual resync to adopt new price beyond bound.
- Escrow `_convertTokenToZir` requires `usdPerTokenE18` manual config for ERC20 tokens other than ZIR; stale pricing leads to incorrect fee conversions.
- Distributor `usedSignatures` hashed on raw signature; slight variations (e.g., different signature for same message) may bypass this guard but digest check ensures unique claim per nonce.

### 8.3 Observed Mitigations
- Feature flags allow rapid disabling of modules in emergencies without redeploy.
- Treasury reserve checks prevent draining below obligations.
- Staking `_availableRewards` ensures claims limited to actual surplus to avoid insolvency.
- Escrow fallback event `GasPricingFallback` emits when price oracle lacks native price, allowing off-chain monitoring.
- Vesting modules require manager or beneficiary interactions; emergency withdraw controlled by manager under feature flag.

### 8.4 Testing Coverage Insights
- Tests confirm signature handling (Distributor), paymaster whitelisting and post-op billing, treasury reserve enforcement, staking multipliers, escrow settlements.
- Further fuzzing recommended for Escrow dispute resolution and gas subsidy combinations.
- Invariant tests in `test/invariant` directory (not fully reviewed) should ensure system-level consistency; verify coverage extends to new modules.

### 8.5 Tooling Considerations
- Foundry tests (Forge) provide deterministic coverage; ensure `forge test` executed in CI before deployment.
- Suggest integrating static analyzers (Slither, MythX) for automated checks beyond manual review.

## 9. Risk Register and Mitigation Roadmap
- Risk ID R1: Oracle misconfiguration leading to incorrect fee/gas conversions; Mitigation: automate `syncPrice` and `setNativeUsdPrice`, monitor events, add fallback pricing logic.
- Risk ID R2: Subsidy pool exhaustion causing gas deficits; Mitigation: implement alerting on `GasSubsidyDeficit` events, auto top-up from treasury, adjust discount policy.
- Risk ID R3: Treasury reserve calculation error; Mitigation: periodic audits of `rewardLiability`, multi-sig approvals for updates, integrate accounting dashboard.
- Risk ID R4: Feature flags left disabled inadvertently causing service outage; Mitigation: build operational checklist and monitoring of flag states via `flagInfo` queries.
- Risk ID R5: Reputation module decay loop gas usage; Mitigation: limit manual `applyDecay` calls per transaction, consider storing exponential factor to avoid loops.
- Risk ID R6: Escrow payment token pricing stale; Mitigation: weekly review of `usdPerTokenE18`, integrate off-chain price feeders, consider on-chain oracles per token.
- Risk ID R8: Distributor signer compromise; Mitigation: maintain hardware wallet signer, rotate via `setSigner`, log `SignerUpdated` events.
- Risk ID R9: Vesting tokens not funded; Mitigation: enforce deposit process before schedule creation, track `token.balanceOf` vs outstanding commitments.
- Risk ID R10: Registry rollback misuse; Mitigation: require governance approval, log audits of `_histories`, consider time lock on `rollback`.
- Risk ID R11: Blacklist misuse in ZIR token; Mitigation: transparent governance process, event monitoring, maintain appeals procedure.
- Risk ID R12: Escrow dispute resolution centralization; Mitigation: potential to add multi-arbiter or DAO voting, ensure arbiter actions logged and reviewable.
- Risk ID R13: Staking reward rate drift; Mitigation: align `yearlyRewardRate` schedule with treasury projections, require multi-sig for updates.
- Risk ID R14: PriceOracle expiry too short causing frequent reverts; Mitigation: calibrate `expirySec` to network update frequency.
- Risk ID R15: Gas ledger rounding errors; Mitigation: add unit tests for boundary cases, monitor `GasSponsored` events for anomalies.
- Risk ID R16: Multi-token escrow conversions bridging decimal mismatches; Mitigation: enforce decimals <=18, test tokens with 6, 8, 18 decimals.
- Risk ID R17: AccessController admin key risk; Mitigation: secure admin via multi-sig, rotate keys, maintain audit logs of role grants/revocations.
- Risk ID R18: Treasury `triggerBuyback` reliant on manual price set; Mitigation: integrate automated price feed or require price update proof.
- Risk ID R19: Escrow `extensionsUsed` limited to 1; may be insufficient for real-world delays; Mitigation: evaluate need for multi-extension with governance oversight.
- Risk ID R20: Staking `rewardRate` default may not align with actual emission plan; Mitigation: document schedule and update `yearlyRewardRate` before activation.

## 10. Testing, Tooling, and Quality Assurance
- Foundry configuration indicates fuzz runs `1000` cases by default (review `foundry.toml` if adjusted).
- Tests present for modules: AccessController, FeatureFlags, Registry, ZIR, Escrow, Staking, Treasury, Reputation, Oracle, Distributor, Vesting.
- Suggest adding scenario tests for cross-module integration (e.g., Escrow settlement feeding Treasury, then Staking reward top-up).
- Invariant tests (e.g., `invariant` folder) should verify total supply consistency, but confirm coverage for escrow gas ledger invariants.
- Recommend adding fuzz tests for Escrow `resolveDispute` to ensure no division by zero or unexpected states.
- Add assertion to ZIR token tests verifying `autoAdjustBurnRatio` behavior under boundary inflation values.
- Utilize `forge coverage` to measure line coverage; target >80% for core modules.
- Encourage integration with CI pipeline executing `forge fmt`, `forge test`, `slither .`.

## 11. Governance, Operations, and Monitoring Considerations
- Role assignments should be managed via governance process; consider multi-sig for manager/treasurer roles.
- Feature flag status should be exposed via dashboards; include alerting when flags toggled unexpectedly.
- Monitor Treasury metrics: `rewardLiability`, `freeBalance`, burn events, dynamic fee adjustments.
- Track Escrow events (FundsLocked, DisputeResolved, GasSubsidyDeficit) to detect abuse or system stress.
- Reputation updates (ReputationUpdated events) offer insight into user behavior; integrate into analytics.
- Ensure PriceOracle `PriceSynced` activity scheduled and logged; watch for `Oracle: price jump too large` reverts indicating volatility.
- Document process for updating payment token configurations and verifying USD pricing.
- Maintain incident response runbooks for pausing modules via `pause` and `setFlag` toggles.

## 12. Recommendations and Action Items
1. Automate price oracle sync via off-chain keeper or cron to avoid stale price reverts.
2. Implement alerting for subsidy pool balance and deficits; possibly auto fund from treasury based on threshold.
3. Extend tests covering Escrow dispute flows including partial seller percentages (e.g., 30/70 split).
5. Add governance safeguard for `setFeeRate` by requiring treasury to call through time-locked contract or multi-sig.
6. Document tokenomics plan, including timeline for adjusting `rewardRate` and `yearlyRewardRate` schedule.
7. Evaluate storing decimal-normalized USD price per token via oracle integration to reduce manual upkeep.
8. Add on-chain check ensuring Treasury holds enough ZIR before approving Escrow orders above certain size.
9. Consider migrating reputation decay to multiplicative exponentiation (e.g., `pow` approximation) to reduce loop cost.
10. Provide UI or script for generating Distributor signatures with correct nonce and expiry handling.
11. Add events for `setYearlyRewardRate` and `setYearlySchedule` to better track emission changes.
12. Explore splitting Escrow disputes among multiple arbiters or DAO vote to decentralize resolution.
13. Record `feeGross` vs `netFee` difference when applying minimum fee to aid analytics.
15. Enforce consistent `decimals` check for payment tokens (reject 0 decimals) to avoid division issues.
16. Add unit tests for `VestingMerkle` invalid proofs ensuring revert messages align with expectations.
17. Provide script to query `FeatureFlags.flagInfo` for operational dashboards.
18. Document procedure for emergency `pause` of token transfers and module operations.

## 13. Appendix A: Configuration Parameters
- AccessController constructor parameters: admin, manager, treasurer, arbiter, pauser addresses.
- FeatureFlags keys (from `FeatureFlagKeys` library): ESCROW, ZIR_TOKEN, TREASURY, REGISTRY, STAKING, REPUTATION, DISTRIBUTOR, VESTING, PAYMASTER, ORACLE.
- ZIR token defaults: `feeRateBps = 0`, `burnRatioPct = 55`, `rewardRatioPct = 20`, treasury = deployer-specified.
- Staking module defaults: `rewardRate = 1_585_489`, `cooldownPeriod = 3 days`, `lastRewardTimestamp = deployment timestamp`.
- Escrow fee config defaults: `feeBps7d=100`, `feeBps15d=125`, `feeBps30d=150`, `maxFeeBps=300`, `zirDiscountBps=3000`, `gasCapBps=200`, `gasSurchargeBps=1500`.
- Escrow minimums default: `minOrderAmountZir6 = 0`, `minFeeZir6 = 0` until configured.
- Escrow `aaSubsidyMode` default false; `gasCollector` must be set before enabling AA.
- Treasury defaults: `safetyMarginBps=11_000`, `platformFeeBurnPct=50`, `platformFeeRewardPct=20`, `minFeeRateBps=50`, `maxFeeRateBps=500`, `feeStepBps=25`, `feeCooldown=7 days`, `liquidityIncreaseThresholdBps=2_000`, `liquidityDecreaseThresholdBps=5_000`.
- Reputation module `penaltyCooldown = 3 days`, `DECAY_BPS = 50` (0.5% weekly).
- Vesting modules require token address; no schedules or root by default.

## 14. Appendix B: Event Catalogue
- AccessController: `RoleGranted`, `RoleRevoked`, `RoleAdminChanged` for role management auditing.
- FeatureFlags: `FeatureToggled` per flag update.
- Registry: `ModuleRegistered`, `ModuleReplaced`, `ModuleRemoved`, `ModuleRolledBack` tracking deployments.
- ZIR token: events for fee adjustments, treasury updates, burns, transfers paused/unpaused.
- Treasury: `Deposited`, `Withdrawn`, `ModuleAllowanceUpdated`, `RewardLiabilityUpdated`, `SafetyMarginUpdated`, `SurplusBurnThresholdUpdated`, `BuybackThresholdUpdated`, `PlatformFeeSplitUpdated`, `PriceOracleUpdated`, `PlatformFeeRouted`, `SurplusBurned`, `QuarterlyBurnTriggered`, `BuybackTriggered`, `LiquidityAssessed`.
- Escrow: `FundsLocked`, `ShipmentConfirmed`, `ReceiptConfirmed`, `AutoReleased`, `Refunded`, `DisputeOpened`, `DisputeResolved`, `Extended`, `PaymentTokenConfigured`, `FeeConfigUpdated`, `MinimumsUpdated`, `GasConfigUpdated`, `AccountBlacklisted`, `GasAccrued`, `GasPricingFallback`, `GasSponsored`, `GasSubsidyDeficit`, `FeeAndGasSettled`, `AAGasReported`, `SubsidyPoolFunded`.
- Staking: `PoolUpdated`, `Stake`, `Withdraw`, `RewardClaimed`, `EmergencyWithdraw`, `CooldownUpdated`, `RewardRateUpdated`, `ReputationUpdated`.
- Reputation: `ModuleAuthorizationUpdated`, `PenaltyCooldownUpdated`, `ReputationUpdated`, `PenaltyApplied`, `PenaltyCleared`.
- PriceOracle: `PriceSynced`, `MaxPriceChangeUpdated`, `ExpiryUpdated`, `FeeConfigUpdated`, `NativeUsdPriceUpdated`.
- Distributor: `SignerUpdated`, `Claimed`.
- VestingLinear: `ScheduleCreated`, `ScheduleUpdated`, `TokensReleased`.
- VestingMerkle: `MerkleRootUpdated`, `Claimed`, `EmergencyWithdraw`.

## 15. Appendix C: Assumptions and Open Questions
- Assumption: AccessController configured with secure admin (e.g., multi-sig) and roles assigned appropriately.
- Assumption: Treasury maintains accurate `rewardLiability` reflecting outstanding obligations (staking, subsidies, future vesting).
- Assumption: Price oracle feed available and updated at least every `expirySec` interval (default 60-300 seconds).
- Assumption: `nativeUsdPriceE18` sourced reliably to convert gas costs; consider using Chainlink ETH/USD feed if available.
- Assumption: Payment token USD prices maintained by governance; question: should rely on on-chain price feeds for major stablecoins instead of static values?
- Assumption: Staking reward pool funded periodically by treasury; question: what mechanism ensures reward pool top-ups align with claim demand?
- Assumption: Escrow arbitrations resolved by trusted arbiter; question: plan for decentralizing arbitration or appealing decisions?
- Assumption: Distributor signer rotates securely; question: is there monitoring to detect unusual claim patterns or nonce gaps?
- Assumption: Feature flag toggles recorded and monitored; question: do we have automated health checks verifying required flags (e.g., STAKING, ESCROW) are enabled before operations begin each day?
- Assumption: Vesting contracts funded to handle all claims; question: is there accounting to ensure tokens reserved vs outstanding schedules?
- Assumption: Registry used for module discovery by other components; question: do modules fetch latest addresses on demand or rely on constructor injection only?
- Assumption: Invariant tests cover supply conservation; question: have invariants been rerun after latest code changes?
- Assumption: Off-chain services listen to event logs for analytics; question: is there redundancy to avoid data loss if one indexer fails?

## 16. Document Revision Log
- 2024-06-XX: Initial Codex-generated audit summary covering full contract suite with focus on functionality, data models, and economics.
- Future revisions should append entries noting changes to contracts, parameters, or audit findings.

## 17. Appendix D: Cross-Module Interaction Matrix
- AccessController -> All modules: supplies role checks for management operations.
- FeatureFlags -> Modules: gating via `whenFeatureEnabled` to ensure safe activation.
- Treasury <-> ZIR: adjusts fee rate, initiates burns, receives platform fees.
- Treasury -> PriceOracle: relies on price conversions for buybacks and assessments.
- Escrow -> Treasury: calls `onPlatformFeeReceived` to route platform fees.
- Escrow -> PriceOracle: converts token amounts and gas costs between USD and ZIR.
- Escrow -> Reputation: records wins/losses affecting participant scores.
- Escrow -> Staking: optional integration placeholder for staking incentives.
- Staking -> Reputation: fetches multiplier via `getReputation`.
- Staking -> ZIR: transfers tokens in and out for staking and rewards.
- Reputation -> AccessController: manager authorizes modules to adjust reputation.
- Distributor -> ZIR: transfers claimed tokens to recipients.
- Vesting modules -> IERC20 token (ZIR or others): release tokens to beneficiaries.
- Registry -> Modules: provides address lookup for upgradeable architecture.
- Tests -> Contracts: verify functionality, replicating role assignments and feature flag toggles.

## 18. Appendix E: Gas Cost Observations (Qualitative)
- Escrow settlement path `_settle` heavy due to multiple transfers and oracle conversions; recommend gas profiling for large order load.
- Reputation decay loop scales with weeks elapsed; consider optimizing if accounts inactive for >5 years.
- Staking reward claim operation involves `_updatePool`, `_refreshMultiplier`, `_accrueReward`, `_claimAccruedReward`; ensure reward claim frequency not excessive to avoid high gas per reward.
- Treasury dynamic fee adjustment minimal gas but interacts with ZIR `setFeeRate` which emits events; schedule adjustments sparingly.
- Distributor `claim` primarily signature recovery and ERC20 transfer; gas acceptable for airdrop operations.
- VestingMerkle `claim` cost proportional to proof length; ensure tree depth manageable (e.g., <= 32 nodes).

## 19. Appendix F: Deployment Checklist
- [ ] Deploy AccessController with secure admin and initial role assignments.
- [ ] Deploy FeatureFlags referencing AccessController.
- [ ] Deploy ZIR token with AccessController and FeatureFlags, set treasury address post Treasury deployment.
- [ ] Deploy TreasuryModule with references to AccessController, FeatureFlags, ZIR, PriceOracle.
- [ ] Deploy PriceOracle with Chainlink feed address and configure expiry, max change, fee settings.
- [ ] Deploy ReputationModule and authorize Escrow, Staking once live.
- [ ] Deploy StakingModule with ZIR and Reputation references; configure reward rate schedule.
- [ ] Deploy Escrow 与依赖模块（Treasury、PriceOracle、Reputation、Staking）；配置 feeRecipient、feeBps、vault 等基础参数。
- [ ] Deploy Distributor with signer address and fund with ZIR tokens.
- [ ] Deploy VestingLinear/Merkle for distribution programs; fund contracts and configure schedules or Merkle root.
- [ ] Deploy Registry if module discovery required; register module addresses with keys from `ModuleKeys`.
- [ ] Configure FeatureFlags enabling modules in rollout order (e.g., ORACLE, TREASURY, ZIR_TOKEN, ESCROW, STAKING, REPUTATION, PAYMASTER, DISTRIBUTOR, VESTING).
- [ ] Execute integration tests and sanity checks post-deployment (e.g., minimal escrow trade, staking stake/claim, distributor claim).
- [ ] Set up monitoring for critical events and balances (treasury reserves, escrow subsidy pool, paymaster balance).

## 20. Appendix G: Suggested Monitoring Metrics
- Metric: `zir.feeRateBps()` — track daily to detect unexpected adjustments.
- Metric: Treasury `rewardLiability` vs `zir.balanceOf(treasury)` — ensure reserve coverage.
- Metric: Escrow `GasSubsidyDeficit` count — high frequency indicates subsidy issues.
- Metric: Staking `totalStaked` and `accRewardPerShare` — evaluate engagement and emission pace.
- Metric: Reputation average score of active users — gauge system health.
- Metric: PriceOracle `lastSyncedAt` age — alert if exceeding `expirySec`.
- Metric: Distributor `usedDigests` growth — monitor claim rate.
- Metric: Vesting contracts `tokensReleased` vs schedules — verify pacing.

## 21. Appendix H: Future Work and Research Questions
- Investigate integrating decentralized arbitration mechanisms to reduce centralized arbiter trust.
- Explore dynamic discounting in Escrow based on staking level or reputation tier.
- Analyze potential to leverage restaked assets or L2 yield for treasury surplus before burns.
- Consider migrating to modular upgrade framework (e.g., UUPS) with Registry serving as beacon.
- Evaluate bridging ZIR token to other chains and implications for burn/fee accounting.
- Assess whether staking rewards should adjust automatically based on treasury reserve ratio signals.
- Research zero-knowledge proofs for escrow disputes to preserve privacy while proving shipment evidence.
- Study impact of account abstraction adoption on paymaster reserves and subsidy modeling.
- Prototype analytics dashboard aggregating key events (FeeDistributed, GasSponsored, ReputationUpdated).

## 22. Appendix I: Glossary
- `AA` — Account Abstraction, enabling sponsored transactions through paymasters.
- `BPS` — Basis points, 1/100th of a percent, used for fee calculations.
- `Cooldown` — Period after staking before withdrawal allowed.
- `Escrow` — Contract holding funds until trade conditions met.
- `FeeExempt` — Address exempt from transfer fee in ZIR token.
- `Gas Ledger` — Record of gas costs eligible for reimbursement in Escrow.
- `Merkle Root` — Hash commitment used to verify inclusion in distribution sets.
- `Penalty` — Temporary restriction applied in Reputation module after arbitration loss.
- `Reward Liability` — Treasury accounting of outstanding rewards owed to stakeholders.
- `Supply Burn` — Destruction of tokens reducing total supply.

## 23. Appendix J: References
- contracts/access/AccessController.sol — role initialization logic.
- contracts/core/ZIR.sol — token economics and fee handling.
- contracts/modules/escrow/Escrow.sol — trade lifecycle implementation.
- contracts/modules/treasury/TreasuryModule.sol — reserve management.
- contracts/modules/staking/StakingModule.sol — staking and reward accrual.
- contracts/modules/reputation/ReputationModule.sol — reputation tracking.
- contracts/modules/oracle/PriceOracle.sol — price caching and validation.
- contracts/support/Distributor.sol — signature-based claims.
- contracts/modules/vesting/VestingLinear.sol — linear vesting schedules.
- contracts/modules/vesting/VestingMerkle.sol — Merkle vesting claims.
- test/* — Foundry-based unit and integration tests validating behavior.

## 24. Appendix K: Contact and Escalation Paths
- Governance Council — responsible for high-level parameter changes and module upgrades.
- Operations Team — monitors feature flags, price oracle updates, and day-to-day health.
- Treasury Committee — oversees reserves, reward liabilities, and burn schedules.
- Arbitration Panel — handles escrow disputes using `resolveDispute` authority.
- Security Response Team — empowered to pause modules and disable features in emergencies.
- Engineering Team — maintains codebase, executes deployments, and updates tests.
- External Auditors — engage for periodic reviews and certification of upgrades.
- Community Support — field questions from users, escalate issues to governance.
