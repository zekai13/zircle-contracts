// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {TreasuryModule} from "../contracts/modules/treasury/TreasuryModule.sol";

contract TreasuryOps is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address zirToken = vm.envAddress("ZIR_TOKEN_ADDRESS");

        address target = vm.envOr("TREASURY_TARGET_ADDRESS", address(0));
        if (target == address(0)) {
            target = vm.envAddress("ESCROW_ADDRESS");
        }

        uint256 amount = vm.envOr("TREASURY_WITHDRAW_AMOUNT", 1_000_000 * 1e6);

        vm.startBroadcast(privateKey);
        TreasuryModule(treasury).withdraw(zirToken, target, amount);
        vm.stopBroadcast();
    }
}
