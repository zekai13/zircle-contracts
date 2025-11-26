// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "../../contracts/libs/ERC1967Proxy.sol";

library ProxyUtils {
    function deployProxy(address implementation, bytes memory initCalldata) internal returns (address) {
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initCalldata);
        return address(proxy);
    }
}
