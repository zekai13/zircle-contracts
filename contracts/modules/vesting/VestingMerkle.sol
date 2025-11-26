// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../../libs/FeatureFlagKeys.sol";
import {SafeERC20} from "../../libs/SafeERC20.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

/// @title VestingMerkle
/// @notice Merkle tree based vesting with partial claims.
contract VestingMerkle is ModuleBase {
    using SafeERC20 for IERC20;

    bytes32 public merkleRoot;
    IERC20 public token;
    mapping(address => uint256) public claimed;

    event MerkleRootUpdated(bytes32 indexed previousRoot, bytes32 indexed newRoot);
    event Claimed(address indexed account, uint256 amount);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    constructor(address accessController_, address featureFlags_, address token_)
        ModuleBase(address(0), address(0))
    {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_, token_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_, address featureFlags_, address token_) public initializer {
        __ModuleBase_init(accessController_, featureFlags_);
        require(token_ != address(0), "VestingMerkle: token zero");
        token = IERC20(token_);
    }

    function setMerkleRoot(bytes32 root)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.VESTING)
    {
        emit MerkleRootUpdated(merkleRoot, root);
        merkleRoot = root;
    }

    function claim(
        uint256 total,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant whenFeatureEnabled(FeatureFlagKeys.VESTING) {
        require(_verify(msg.sender, total, start, cliff, duration, proof), "VestingMerkle: invalid proof");
        require(duration > 0, "VestingMerkle: duration zero");
        require(cliff <= duration, "VestingMerkle: cliff>duration");

        uint256 vested = _vestedAmount(total, start, cliff, duration);
        uint256 available = vested - claimed[msg.sender];
        require(amount <= available, "VestingMerkle: amount exceeds vested");

        claimed[msg.sender] += amount;
        token.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    function emergencyWithdraw(address to, uint256 amount)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.VESTING)
    {
        require(to != address(0), "VestingMerkle: to zero");
        token.safeTransfer(to, amount);
        emit EmergencyWithdraw(to, amount);
    }

    function _vestedAmount(
        uint256 total,
        uint64 start,
        uint64 cliff,
        uint64 duration
    ) internal view returns (uint256) {
        if (block.timestamp <= start) return 0;
        uint256 elapsed = block.timestamp - start;
        if (elapsed < cliff) return 0;
        if (elapsed >= duration) return total;
        return (total * elapsed) / duration;
    }

    function _verify(
        address account,
        uint256 total,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account, total, start, cliff, duration));
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computed <= proofElement) {
                computed = keccak256(abi.encodePacked(computed, proofElement));
            } else {
                computed = keccak256(abi.encodePacked(proofElement, computed));
            }
        }
        return computed == merkleRoot;
    }

    uint256[45] private __gap;
}
