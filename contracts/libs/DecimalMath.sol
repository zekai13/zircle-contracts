// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Decimal Math Utilities
/// @notice Placeholder for mulDiv style helpers supporting 6 and 18 decimal conversions.
library DecimalMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant SIX_TO_WAD = 1e12;

    function toWad(uint256 amount6) internal pure returns (uint256) {
        return amount6 * SIX_TO_WAD;
    }

    function fromWad(uint256 amountWad) internal pure returns (uint256) {
        return amountWad / SIX_TO_WAD;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        require(denominator != 0, "DecimalMath: div by zero");
        result = (x * y) / denominator;
    }
}
