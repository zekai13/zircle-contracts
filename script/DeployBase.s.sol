// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {AccessController} from "../contracts/access/AccessController.sol";
import {FeatureFlags} from "../contracts/core/FeatureFlags.sol";
import {Registry} from "../contracts/core/Registry.sol";
import {ZIR} from "../contracts/core/ZIR.sol";
import {PriceOracle} from "../contracts/modules/oracle/PriceOracle.sol";
import {TreasuryModule} from "../contracts/modules/treasury/TreasuryModule.sol";
import {ReputationModule} from "../contracts/modules/reputation/ReputationModule.sol";
import {StakingModule} from "../contracts/modules/staking/StakingModule.sol";
import {Escrow} from "../contracts/modules/escrow/Escrow.sol";
import {ZIRDistributor} from "../contracts/support/Distributor.sol";
import {VestingLinear} from "../contracts/modules/vesting/VestingLinear.sol";
import {VestingMerkle} from "../contracts/modules/vesting/VestingMerkle.sol";

import {FeatureFlagKeys} from "../contracts/libs/FeatureFlagKeys.sol";
import {ModuleKeys} from "../contracts/libs/ModuleKeys.sol";

import {AggregatorV3Interface} from "../contracts/interfaces/external/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "../contracts/mocks/MockV3Aggregator.sol";
import {ProxyUtils} from "./utils/ProxyUtils.sol";

/// @notice End-to-end deployment script targeting Base Sepolia (or compatible) networks.
/// @dev Expects the following environment variables to be present:
///      - PRIVATE_KEY: hex encoded deployer private key (0x-prefixed).
///      - AGGREGATOR_ADDRESS (optional): Chainlink (or compatible) price feed contract.
///        If omitted, a MockV3Aggregator will be deployed with configurable defaults.
///      - ENTRY_POINT (optional): ERC-4337 entry point address for the target network.
///        Defaults to the canonical 0x5FF1... address used by most test deployments.
///      - DISTRIBUTOR_SIGNER (optional): address authorized to sign distributor claims.
///        Defaults to the deployer if not provided (recommended to override).
///      Optional:
///      - NATIVE_USD_PRICE: cached native token/USD price (1e18 precision) for initial oracle config.
///      - MOCK_FEED_DECIMALS: decimals used when deploying the mock aggregator (default 18).
///      - MOCK_FEED_INITIAL_PRICE: initial price for the mock aggregator (default 2e18).
contract DeployBase is Script {
    uint256 internal constant DEFAULT_DEPLOYER_PK =
        0xa9bd3f0c051c9522bea3e0546a20d617094e6a4c8a774a2acda8e7473a841bc6;
    address internal constant DEFAULT_DEPLOYER = 0x7c5DA45c3631E91f4D2DC9F53f706775787dBF1E;
    string internal constant DEFAULT_RPC_URL = "https://sepolia.base.org";

    function run() external {
        uint256 deployerPk = vm.envOr("PRIVATE_KEY", DEFAULT_DEPLOYER_PK);
        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        if (deployer == address(0)) {
            deployer = vm.addr(deployerPk);
        }

        address distributorSigner = vm.envOr("DISTRIBUTOR_SIGNER", deployer);
        string memory rpcUrl = vm.envOr("RPC_URL", DEFAULT_RPC_URL);

        uint256 nativeUsdPrice = vm.envOr("NATIVE_USD_PRICE", uint256(0));
        uint256 oracleExpiry = vm.envOr("ORACLE_EXPIRY", uint256(180));
        uint16 oracleMaxChangeBps = uint16(vm.envOr("ORACLE_MAX_CHANGE_BPS", uint256(500)));
        uint256 oracleFeeFixed = vm.envOr("ORACLE_FEE_FIXED_E18", uint256(0));
        uint16 oracleFeePct = uint16(vm.envOr("ORACLE_FEE_PCT_BPS", uint256(0)));
        uint8 mockFeedDecimals = uint8(vm.envOr("MOCK_FEED_DECIMALS", uint256(18)));
        int256 mockFeedInitialPrice = int256(vm.envOr("MOCK_FEED_INITIAL_PRICE", uint256(2e18)));

        address aggregatorAddr = vm.envOr("AGGREGATOR_ADDRESS", address(0));

        console2.log("Deploying with EOA:", deployer);
        console2.log("Aggregator feed:", aggregatorAddr);
        console2.log("Distributor signer:", distributorSigner);

        vm.startBroadcast(deployerPk);

        if (aggregatorAddr == address(0)) {
            MockV3Aggregator mockAggregator = new MockV3Aggregator(mockFeedDecimals, mockFeedInitialPrice);
            aggregatorAddr = address(mockAggregator);
            console2.log("Mock aggregator deployed at:", aggregatorAddr);
        }

        // Core governance primitives via UUPS proxies.
        address controllerProxy = ProxyUtils.deployProxy(
            address(new AccessController(address(0), address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                AccessController.initialize.selector,
                deployer,
                deployer,
                deployer,
                deployer,
                deployer
            )
        );
        AccessController controller = AccessController(controllerProxy);

        address featureFlagsProxy = ProxyUtils.deployProxy(
            address(new FeatureFlags(address(0))),
            abi.encodeWithSelector(FeatureFlags.initialize.selector, controllerProxy)
        );
        FeatureFlags featureFlags = FeatureFlags(featureFlagsProxy);

        // External price oracle wrapper.
        AggregatorV3Interface feed = AggregatorV3Interface(aggregatorAddr);
        address priceOracleProxy = ProxyUtils.deployProxy(
            address(new PriceOracle(address(0), address(0), AggregatorV3Interface(address(0)), 0, 0, 0, 0)),
            abi.encodeWithSelector(
                PriceOracle.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                feed,
                oracleExpiry,
                oracleMaxChangeBps,
                oracleFeeFixed,
                oracleFeePct
            )
        );
        PriceOracle priceOracle = PriceOracle(priceOracleProxy);

        // Core token deployment (initial supply minted to deployer).
        address zirProxy = ProxyUtils.deployProxy(
            address(new ZIR(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                ZIR.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                deployer
            )
        );
        ZIR zir = ZIR(zirProxy);

        // Module deployments.
        address treasuryProxy = ProxyUtils.deployProxy(
            address(new TreasuryModule(address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                TreasuryModule.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                zirProxy,
                priceOracleProxy
            )
        );
        TreasuryModule treasury = TreasuryModule(treasuryProxy);

        address reputationProxy = ProxyUtils.deployProxy(
            address(new ReputationModule(address(0), address(0))),
            abi.encodeWithSelector(
                ReputationModule.initialize.selector,
                controllerProxy,
                featureFlagsProxy
            )
        );
        ReputationModule reputation = ReputationModule(reputationProxy);

        address stakingProxy = ProxyUtils.deployProxy(
            address(new StakingModule(address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                StakingModule.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                zirProxy,
                reputationProxy
            )
        );
        StakingModule staking = StakingModule(stakingProxy);

        address escrowProxy = ProxyUtils.deployProxy(
            address(new Escrow()),
            abi.encodeWithSelector(
                Escrow.initialize.selector,
                controllerProxy,
                featureFlagsProxy
            )
        );
        Escrow escrow = Escrow(escrowProxy);

        address distributorProxy = ProxyUtils.deployProxy(
            address(new ZIRDistributor(address(0), address(0), address(0), address(0))),
            abi.encodeWithSelector(
                ZIRDistributor.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                zirProxy,
                distributorSigner
            )
        );
        ZIRDistributor distributor = ZIRDistributor(distributorProxy);

        address vestingLinearProxy = ProxyUtils.deployProxy(
            address(new VestingLinear(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                VestingLinear.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                zirProxy
            )
        );
        VestingLinear vestingLinear = VestingLinear(vestingLinearProxy);

        address vestingMerkleProxy = ProxyUtils.deployProxy(
            address(new VestingMerkle(address(0), address(0), address(0))),
            abi.encodeWithSelector(
                VestingMerkle.initialize.selector,
                controllerProxy,
                featureFlagsProxy,
                zirProxy
            )
        );
        VestingMerkle vestingMerkle = VestingMerkle(vestingMerkleProxy);

        address registryProxy = ProxyUtils.deployProxy(
            address(new Registry(address(0), address(0))),
            abi.encodeWithSelector(
                Registry.initialize.selector,
                controllerProxy,
                featureFlagsProxy
            )
        );
        Registry registry = Registry(registryProxy);

        // Enable feature flags for deployed modules before invoking guarded functions.
        featureFlags.setFlag(FeatureFlagKeys.ORACLE, true);
        featureFlags.setFlag(FeatureFlagKeys.ZIR_TOKEN, true);
        featureFlags.setFlag(FeatureFlagKeys.TREASURY, true);
        featureFlags.setFlag(FeatureFlagKeys.REPUTATION, true);
        featureFlags.setFlag(FeatureFlagKeys.STAKING, true);
        featureFlags.setFlag(FeatureFlagKeys.ESCROW, true);
        featureFlags.setFlag(FeatureFlagKeys.DISTRIBUTOR, true);
        featureFlags.setFlag(FeatureFlagKeys.VESTING, true);
        featureFlags.setFlag(FeatureFlagKeys.REGISTRY, true);

        // Treasury should be the canonical custodian in the token contract.
        zir.setTreasury(address(treasury));

        uint256 deployerZirBalance = zir.balanceOf(deployer);
        if (deployerZirBalance > 0) {
            bool treasuryFunded = zir.transfer(address(treasury), deployerZirBalance);
            require(treasuryFunded, "DeployBase: initial treasury funding failed");
        }

        // Authorize protocol modules for reputation adjustments and treasury interactions.
        reputation.authorizeModule(address(escrow), true);
        reputation.authorizeModule(address(staking), true);

        treasury.setModuleAllowance(address(escrow), true, 0, 0);

        // Configure escrow defaults.
        escrow.setFeeRecipient(address(treasury));
        escrow.setFeeBps(500);
        escrow.setVault(address(treasury));
        escrow.setAllowedToken(zirProxy, true);
        escrow.setMaxExtensionCount(1);

        if (nativeUsdPrice > 0) {
            priceOracle.setNativeUsdPrice(nativeUsdPrice);
        }

        // Populate registry entries for discovery.
        registry.setModule(ModuleKeys.ACCESS_CONTROLLER, address(controller));
        registry.setModule(ModuleKeys.FEATURE_FLAGS, address(featureFlags));
        registry.setModule(ModuleKeys.ZIR_TOKEN, address(zir));
        registry.setModule(ModuleKeys.PRICE_ORACLE, address(priceOracle));
        registry.setModule(ModuleKeys.TREASURY, address(treasury));
        registry.setModule(ModuleKeys.REPUTATION, address(reputation));
        registry.setModule(ModuleKeys.STAKING, address(staking));
        registry.setModule(ModuleKeys.ESCROW, address(escrow));
        registry.setModule(ModuleKeys.DISTRIBUTOR, address(distributor));
        registry.setModule(ModuleKeys.VESTING_LINEAR, address(vestingLinear));
        registry.setModule(ModuleKeys.VESTING_MERKLE, address(vestingMerkle));
        registry.setModule(ModuleKeys.REGISTRY, address(registry));

        vm.stopBroadcast();

        // Deployment summary.
        console2.log("AccessController:", address(controller));
        console2.log("FeatureFlags:", address(featureFlags));
        console2.log("Registry:", address(registry));
        console2.log("ZIR token:", address(zir));
        console2.log("PriceOracle:", address(priceOracle));
        console2.log("TreasuryModule:", address(treasury));
        console2.log("ReputationModule:", address(reputation));
        console2.log("StakingModule:", address(staking));
        console2.log("Escrow:", address(escrow));
        console2.log("ZIRDistributor:", address(distributor));
        console2.log("VestingLinear:", address(vestingLinear));
        console2.log("VestingMerkle:", address(vestingMerkle));

        bool persistFiles = vm.envOr("DEPLOY_PERSIST_FILES", false);
        if (persistFiles) {
            string memory timestamp = vm.toString(block.timestamp);
            string memory jsonPath = string.concat("deployments/base_sepolia_", timestamp, ".json");
            string memory envPath = string.concat("deployments/base_sepolia_", timestamp, ".env");

            string memory contractsJson = vm.serializeAddress("contracts", "AccessController", address(controller));
            contractsJson = vm.serializeAddress("contracts", "FeatureFlags", address(featureFlags));
            contractsJson = vm.serializeAddress("contracts", "Registry", address(registry));
            contractsJson = vm.serializeAddress("contracts", "ZIRToken", address(zir));
            contractsJson = vm.serializeAddress("contracts", "PriceOracle", address(priceOracle));
            contractsJson = vm.serializeAddress("contracts", "TreasuryModule", address(treasury));
            contractsJson = vm.serializeAddress("contracts", "ReputationModule", address(reputation));
            contractsJson = vm.serializeAddress("contracts", "StakingModule", address(staking));
            contractsJson = vm.serializeAddress("contracts", "Escrow", address(escrow));
            contractsJson = vm.serializeAddress("contracts", "ZIRDistributor", address(distributor));
            contractsJson = vm.serializeAddress("contracts", "VestingLinear", address(vestingLinear));
            contractsJson = vm.serializeAddress("contracts", "VestingMerkle", address(vestingMerkle));
            contractsJson = vm.serializeAddress("contracts", "Aggregator", aggregatorAddr);
            contractsJson = vm.serializeAddress("contracts", "Deployer", deployer);
            vm.writeJson(contractsJson, jsonPath);

            bytes memory envContent = abi.encodePacked(
                "# Auto-generated by DeployBase.s.sol at ", timestamp, "\n",
                "RPC_URL=", rpcUrl, "\n",
                "DEPLOYER_ADDRESS=", vm.toString(deployer), "\n",
                "ACCESS_CONTROLLER_ADDRESS=", vm.toString(address(controller)), "\n",
                "FEATURE_FLAGS_ADDRESS=", vm.toString(address(featureFlags)), "\n",
                "REGISTRY_ADDRESS=", vm.toString(address(registry)), "\n",
                "ZIR_TOKEN_ADDRESS=", vm.toString(address(zir)), "\n",
                "PRICE_ORACLE_ADDRESS=", vm.toString(address(priceOracle)), "\n",
                "TREASURY_ADDRESS=", vm.toString(address(treasury)), "\n",
                "REPUTATION_ADDRESS=", vm.toString(address(reputation)), "\n",
                "STAKING_ADDRESS=", vm.toString(address(staking)), "\n",
                "ESCROW_ADDRESS=", vm.toString(address(escrow)), "\n",
                "DISTRIBUTOR_ADDRESS=", vm.toString(address(distributor)), "\n",
                "VESTING_LINEAR_ADDRESS=", vm.toString(address(vestingLinear)), "\n",
                "VESTING_MERKLE_ADDRESS=", vm.toString(address(vestingMerkle)), "\n",
                "AGGREGATOR_ADDRESS=", vm.toString(aggregatorAddr), "\n"
            );
            vm.writeFile(envPath, string(envContent));
        }
    }
}
