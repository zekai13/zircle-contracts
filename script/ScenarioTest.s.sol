// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {Registry} from "../contracts/core/Registry.sol";
import {FeatureFlags} from "../contracts/core/FeatureFlags.sol";
import {ZIR} from "../contracts/core/ZIR.sol";
import {PriceOracle} from "../contracts/modules/oracle/PriceOracle.sol";
import {TreasuryModule} from "../contracts/modules/treasury/TreasuryModule.sol";
import {ReputationModule} from "../contracts/modules/reputation/ReputationModule.sol";
import {StakingModule} from "../contracts/modules/staking/StakingModule.sol";
import {Escrow} from "../contracts/modules/escrow/Escrow.sol";
import {ZIRDistributor} from "../contracts/support/Distributor.sol";
import {VestingLinear} from "../contracts/modules/vesting/VestingLinear.sol";
import {ModuleKeys} from "../contracts/libs/ModuleKeys.sol";
import {FeatureFlagKeys} from "../contracts/libs/FeatureFlagKeys.sol";

contract ScenarioTest is Script {
    uint256 private constant ONE_ZIR = 1e6;
    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(address account,uint256 amount,uint256 nonce,uint256 expiry)");

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        uint256 buyerPk = vm.envUint("BUYER_PRIVATE_KEY");
        uint256 sellerPk = vm.envUint("SELLER_PRIVATE_KEY");
        uint256 stakerPk = vm.envUint("STAKER_PRIVATE_KEY");
        uint256 beneficiaryPk = vm.envOr("BENEFICIARY_PRIVATE_KEY", buyerPk);

        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        Registry registry = Registry(registryAddress);

        FeatureFlags featureFlags = FeatureFlags(registry.getModule(ModuleKeys.FEATURE_FLAGS));
        ZIR zir = ZIR(registry.getModule(ModuleKeys.ZIR_TOKEN));
        PriceOracle priceOracle = PriceOracle(registry.getModule(ModuleKeys.PRICE_ORACLE));
        TreasuryModule treasury = TreasuryModule(registry.getModule(ModuleKeys.TREASURY));
        ReputationModule reputation = ReputationModule(registry.getModule(ModuleKeys.REPUTATION));
        StakingModule staking = StakingModule(registry.getModule(ModuleKeys.STAKING));
        Escrow escrow = Escrow(registry.getModule(ModuleKeys.ESCROW));
        ZIRDistributor distributor = ZIRDistributor(registry.getModule(ModuleKeys.DISTRIBUTOR));
        VestingLinear vesting = VestingLinear(registry.getModule(ModuleKeys.VESTING_LINEAR));
        address aggregatorAddress = address(priceOracle.feed());

        address deployer = vm.addr(deployerPk);
        address buyer = vm.addr(buyerPk);
        address seller = vm.addr(sellerPk);
        address staker = vm.addr(stakerPk);
        address beneficiary = vm.addr(beneficiaryPk);

        console2.log("Scenario deployer:", deployer);
        console2.log("Buyer:", buyer);
        console2.log("Seller:", seller);
        console2.log("Staker:", staker);
        console2.log("Beneficiary:", beneficiary);

        _logModule("FeatureFlags", address(featureFlags));
        _logModule("ZIR Token", address(zir));
        _logModule("PriceOracle", address(priceOracle));
        _logModule("Treasury", address(treasury));
        _logModule("Reputation", address(reputation));
        _logModule("Staking", address(staking));
        _logModule("Escrow", address(escrow));
        _logModule("Distributor", address(distributor));
        _logModule("VestingLinear", address(vesting));
        _logModule("Aggregator", aggregatorAddress);

        uint256 escrowAmount = 1_000 * ONE_ZIR;
        uint256 buyerFunding = escrowAmount + (200 * ONE_ZIR);
        uint256 stakerFunding = 2_000 * ONE_ZIR;
        uint256 distributorFunding = 500 * ONE_ZIR;
        uint256 vestingFunding = 800 * ONE_ZIR;

        // === Governance setup & funding ===
        vm.startBroadcast(deployerPk);
        featureFlags.setFlag(FeatureFlagKeys.ESCROW, true);
        featureFlags.setFlag(FeatureFlagKeys.STAKING, true);
        featureFlags.setFlag(FeatureFlagKeys.DISTRIBUTOR, true);
        featureFlags.setFlag(FeatureFlagKeys.VESTING, true);
        featureFlags.setFlag(FeatureFlagKeys.ORACLE, true);
        featureFlags.setFlag(FeatureFlagKeys.REPUTATION, true);
        featureFlags.setFlag(FeatureFlagKeys.TREASURY, true);

        // Optional: authorize modules (idempotent)
        reputation.authorizeModule(address(escrow), true);
        reputation.authorizeModule(address(staking), true);
        treasury.setModuleAllowance(address(escrow), true, 0, 0);

        treasury.withdraw(address(zir), buyer, buyerFunding);
        treasury.withdraw(address(zir), staker, stakerFunding);
        treasury.withdraw(address(zir), address(distributor), distributorFunding);
        treasury.withdraw(address(zir), address(vesting), vestingFunding);

        console2.log("Funds distributed to participants");
        vm.stopBroadcast();

        // === Escrow scenario ===
        vm.startBroadcast(buyerPk);
        zir.approve(address(escrow), escrowAmount);
        bytes32 orderNo = keccak256("scenario-order-001");
        uint64 shipBy = uint64(block.timestamp + 3 days);
        uint64 autoReleaseAt = uint64(block.timestamp + 7 days);
        escrow.lockFunds(
            orderNo,
            buyer,
            seller,
            address(zir),
            escrowAmount,
            shipBy,
            autoReleaseAt,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        vm.stopBroadcast();

        vm.startBroadcast(sellerPk);
        escrow.confirmShipment(orderNo, bytes32("CR"), keccak256(bytes("TRACKING-XYZ")), "ipfs://tracking");
        vm.stopBroadcast();

        vm.startBroadcast(buyerPk);
        escrow.confirmReceipt(orderNo);
        vm.stopBroadcast();
        console2.log("Escrow scenario completed");

        // === Staking scenario ===
        uint256 stakeAmount = 1_500 * ONE_ZIR;
        vm.startBroadcast(stakerPk);
        zir.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        staking.emergencyWithdraw();
        vm.stopBroadcast();
        console2.log("Staking stake & emergency withdraw executed");

        // === Price oracle update ===
        vm.startBroadcast(deployerPk);
        (bool priceUpdated,) = aggregatorAddress.call(abi.encodeWithSignature(
            "updateAnswer(int256)",
            int256(2_200_000_000000000000)
        ));
        if (priceUpdated) {
            priceOracle.syncPrice();
            console2.log("Price oracle synchronized with new mock price");
        } else {
            console2.log("Aggregator updateAnswer() unavailable; skipped price update");
        }
        vm.stopBroadcast();

        // === Distributor claim ===
        uint256 claimAmount = 100 * ONE_ZIR;
        uint256 nonce = distributor.nonces(buyer);
        uint256 expiry = block.timestamp + 2 days;
        bytes memory signature = _signDistributorClaim(
            deployerPk,
            address(distributor),
            buyer,
            claimAmount,
            nonce,
            expiry
        );

        vm.startBroadcast(buyerPk);
        distributor.claim(claimAmount, expiry, signature);
        vm.stopBroadcast();
        console2.log("Distributor claim executed");

        // === Vesting linear release ===
        uint64 start = uint64(block.timestamp - 7 days);
        uint64 cliff = 0;
        uint64 duration = uint64(7 days);
        vm.startBroadcast(deployerPk);
        vesting.createOrUpdateSchedule(beneficiary, vestingFunding, start, cliff, duration);
        vm.stopBroadcast();

        vm.startBroadcast(beneficiaryPk);
        vesting.release();
        vm.stopBroadcast();
        console2.log("Vesting release completed");
    }

    function _signDistributorClaim(
        uint256 signerPk,
        address distributor,
        address account,
        uint256 amount,
        uint256 nonce,
        uint256 expiry
    ) internal returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            CLAIM_TYPEHASH,
            account,
            amount,
            nonce,
            expiry
        ));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZIRDistributor")),
                keccak256(bytes("1")),
                block.chainid,
                distributor
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _logModule(string memory name, address moduleAddress) internal pure {
        console2.log(string.concat(name, ":"), moduleAddress);
    }
}
