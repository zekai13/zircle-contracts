// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceOracle {
    function syncPrice() external;
    function latestPrice() external view returns (uint256);
    function convertToUsd(uint256 amountZir6) external view returns (uint256);
    function convertFromUsd(uint256 amountUsd18) external view returns (uint256);
    function quoteFee(uint256 amountZir6) external view returns (uint256);
    function nativeUsdPriceE18() external view returns (uint256);
}
