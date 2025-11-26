// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployBase} from "./DeployBase.s.sol";

/// @notice Thin orchestrator that reuses `DeployBase` to execute the full proxy deployment flow.
contract DeployAllScript is DeployBase {}
