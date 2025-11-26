// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface IUUPSUpgradeable {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

/// @notice Performs a UUPS proxy upgrade using Foundry scripts.
contract UpgradeModuleUUPS is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY_ADDRESS");
        address newImplementation = vm.envAddress("NEW_IMPLEMENTATION");

        bytes memory callData;
        uint256 callValue;

        // UPGRADE_CALLDATA and UPGRADE_CALLVALUE are optional.
        try vm.envBytes("UPGRADE_CALLDATA") returns (bytes memory rawData) {
            callData = rawData;
        } catch (bytes memory) {
            callData = "";
        }

        try vm.envUint("UPGRADE_CALLVALUE") returns (uint256 value) {
            callValue = value;
        } catch (bytes memory) {
            callValue = 0;
        }

        vm.startBroadcast(privateKey);
        if (callData.length == 0) {
            IUUPSUpgradeable(proxy).upgradeTo(newImplementation);
        } else {
            IUUPSUpgradeable(proxy).upgradeToAndCall{value: callValue}(newImplementation, callData);
        }
        vm.stopBroadcast();
    }
}
