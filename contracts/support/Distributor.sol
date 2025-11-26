// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ModuleBase} from "../libs/ModuleBase.sol";
import {FeatureFlagKeys} from "../libs/FeatureFlagKeys.sol";
import {SafeERC20} from "../libs/SafeERC20.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IZIR} from "../interfaces/IZIR.sol";
import {EIP712} from "../libs/EIP712.sol";
import {ECDSA} from "../libs/ECDSA.sol";
import {Nonces} from "../libs/Nonces.sol";

/// @title ZIRDistributor
/// @notice EIP-712 distributor allowing authorized signer to approve claims.
contract ZIRDistributor is ModuleBase, EIP712, Nonces {
    using SafeERC20 for IERC20;

    IZIR public zir;
    address public signer;

    mapping(bytes32 => bool) public usedDigests;
    mapping(bytes32 => bool) private usedSignatures;

    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(address account,uint256 amount,uint256 nonce,uint256 expiry)");

    event SignerUpdated(address indexed previousSigner, address indexed newSigner);
    event Claimed(address indexed account, uint256 amount, uint256 nonce);

    constructor(address accessController_, address featureFlags_, address zirToken_, address signer_)
        ModuleBase(address(0), address(0))
        EIP712("", "")
    {
        if (accessController_ != address(0)) {
            initialize(accessController_, featureFlags_, zirToken_, signer_);
        }
        _disableInitializers();
    }

    function initialize(address accessController_, address featureFlags_, address zirToken_, address signer_)
        public
        initializer
    {
        __ModuleBase_init(accessController_, featureFlags_);
        __EIP712_init("ZIRDistributor", "1");
        require(zirToken_ != address(0), "Distributor: ZIR required");
        require(signer_ != address(0), "Distributor: signer required");
        zir = IZIR(zirToken_);
        signer = signer_;
    }

    function setSigner(address newSigner)
        external
        onlyManager
        whenFeatureEnabled(FeatureFlagKeys.DISTRIBUTOR)
    {
        require(newSigner != address(0), "Distributor: signer zero");
        emit SignerUpdated(signer, newSigner);
        signer = newSigner;
    }

    function claim(uint256 amount, uint256 expiry, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        whenFeatureEnabled(FeatureFlagKeys.DISTRIBUTOR)
    {
        require(block.timestamp <= expiry, "Distributor: expired");

        bytes32 sigHash = keccak256(signature);
        require(!usedSignatures[sigHash], "Distributor: digest used");

        uint256 currentNonce = nonces(msg.sender);
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, msg.sender, amount, currentNonce, expiry));
        bytes32 digest = _hashTypedDataV4(structHash);
        require(!usedDigests[digest], "Distributor: digest used");

        address recovered = ECDSA.recover(digest, signature);
        require(recovered == signer, "Distributor: invalid signature");

        uint256 nonce = _useNonce(msg.sender);
        require(nonce == currentNonce, "Distributor: nonce mismatch");

        usedDigests[digest] = true;
        usedSignatures[sigHash] = true;

        IERC20(address(zir)).safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount, nonce);
    }

    uint256[45] private __gap;
}
