// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IERC20} from "../contracts/interfaces/IERC20.sol";

contract QueryCustodyBalance is Script {
    function run() external view returns (uint256 balance) {
        address zirToken = vm.envAddress("ZIR_TOKEN_ADDRESS");
        address custody = vm.envAddress("ESCROW_ADDRESS");

        balance = IERC20(zirToken).balanceOf(custody);
        console2.log("Custody ZIR balance (6 decimals):", balance);
    }
}
