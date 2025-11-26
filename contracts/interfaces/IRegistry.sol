// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRegistry {
    function getModule(bytes32 key) external view returns (address);
    function setModule(bytes32 key, address implementation) external;
}
