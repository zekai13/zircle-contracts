// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {TreasuryModule} from "../contracts/modules/treasury/TreasuryModule.sol";

contract DistributeZIR is Script {
    address constant DEFAULT_CUSTODY_WALLET = 0xaE20a3CcD95f2d1780B719B644fB8291F808c4fE;
    address constant DEFAULT_GAS_POOL_WALLET = 0xCA18ec274da3E13112A7ab0076846854B813c9b2;
    address constant DEFAULT_VAULT_WALLET = 0x284eDA5366372385ed21fd5e56247D55434B3F17;

    uint256 constant DEFAULT_AMOUNT_EACH = 1_000_000 * 1e6; // ZIR has 6 decimals

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address zirToken = vm.envAddress("ZIR_TOKEN_ADDRESS");

        address[3] memory wallets = [
            vm.envOr("CUSTODY_WALLET", DEFAULT_CUSTODY_WALLET),
            vm.envOr("GAS_POOL_WALLET", DEFAULT_GAS_POOL_WALLET),
            vm.envOr("VAULT_WALLET", DEFAULT_VAULT_WALLET)
        ];

        uint256 amountEach = vm.envOr("ZIR_DISTRIBUTION_AMOUNT", DEFAULT_AMOUNT_EACH);

        vm.startBroadcast(privateKey);
        for (uint256 i = 0; i < wallets.length; i++) {
            address wallet = wallets[i];
            require(wallet != address(0), "DistributeZIR: zero wallet");
            TreasuryModule(treasury).withdraw(zirToken, wallet, amountEach);
        }
        vm.stopBroadcast();
    }
}
