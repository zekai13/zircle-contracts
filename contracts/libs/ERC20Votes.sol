// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "./ERC20.sol";
import {EIP712} from "./EIP712.sol";
import {Nonces} from "./Nonces.sol";
import {ECDSA} from "./ECDSA.sol";

abstract contract ERC20Votes is ERC20, EIP712, Nonces {
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    mapping(address => address) private _delegates;
    mapping(address => Checkpoint[]) private _checkpoints;
    Checkpoint[] private _totalSupplyCheckpoints;

    bytes32 private constant _DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    constructor(string memory name, string memory symbol, uint8 decimals_, string memory version)
        ERC20("", "", 0)
        EIP712("", "")
    {
        if (bytes(name).length != 0 || bytes(symbol).length != 0) {
            _initializerBefore();
            __ERC20Votes_init(name, symbol, decimals_, version);
            _initializerAfter();
        }
    }

    function __ERC20Votes_init(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        string memory version
    ) internal onlyInitializing {
        __ERC20_init(name, symbol, decimals_);
        __EIP712_init(name, version);
        __ERC20Votes_init_unchained();
    }

    function __ERC20Votes_init_unchained() internal onlyInitializing {}

    function delegates(address account) public view returns (address) {
        return _delegates[account];
    }

    function getVotes(address account) public view returns (uint256) {
        uint256 pos = _checkpoints[account].length;
        return pos == 0 ? 0 : _checkpoints[account][pos - 1].votes;
    }

    function getPastVotes(address account, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "ERC20Votes: block not yet mined");
        return _checkpointsLookup(_checkpoints[account], blockNumber);
    }

    function getPastTotalSupply(uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "ERC20Votes: block not yet mined");
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }

    function delegate(address delegatee) public {
        _delegate(_msgSender(), delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= expiry, "ERC20Votes: signature expired");
        bytes32 structHash = keccak256(abi.encode(_DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        require(nonce == _useNonce(signer), "ERC20Votes: invalid nonce");
        _delegate(signer, delegatee);
    }

    function _checkpointWrite(Checkpoint[] storage ckpts, uint224 votes) private {
        if (ckpts.length > 0 && ckpts[ckpts.length - 1].fromBlock == block.number) {
            ckpts[ckpts.length - 1].votes = votes;
        } else {
            ckpts.push(Checkpoint({fromBlock: uint32(block.number), votes: votes}));
        }
    }

    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 blockNumber) private view returns (uint256) {
        uint256 high = ckpts.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (ckpts[mid].fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high == 0 ? 0 : ckpts[high - 1].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = _delegates[delegator];
        if (delegatee == currentDelegate) {
            return;
        }
        _delegates[delegator] = delegatee;
        emit DelegateChanged(delegator, currentDelegate, delegatee);
        _moveVotingPower(currentDelegate, delegatee, balanceOf(delegator));
    }

    function _moveVotingPower(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                uint256 prev = getVotes(from);
                uint256 next = prev - amount;
                _checkpointWrite(_checkpoints[from], uint224(next));
                emit DelegateVotesChanged(from, prev, next);
            }
            if (to != address(0)) {
                uint256 prevVotes = getVotes(to);
                uint256 newVotes = prevVotes + amount;
                _checkpointWrite(_checkpoints[to], uint224(newVotes));
                emit DelegateVotesChanged(to, prevVotes, newVotes);
            }
        }
    }

    function _mint(address account, uint256 amount) internal virtual override {
        super._mint(account, amount);
        _moveVotingPower(address(0), delegates(account), amount);
        _writeTotalSupplyCheckpoint(totalSupply());
    }

    function _burn(address account, uint256 amount) internal virtual override {
        super._burn(account, amount);
        _moveVotingPower(delegates(account), address(0), amount);
        _writeTotalSupplyCheckpoint(totalSupply());
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        _moveVotingPower(delegates(from), delegates(to), amount);
    }

    function _writeTotalSupplyCheckpoint(uint256 newTotalSupply) private {
        _checkpointWrite(_totalSupplyCheckpoints, uint224(newTotalSupply));
    }

    uint256[50] private __gap;
}
