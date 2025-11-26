// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Minimal Initializable helper
/// @notice Lightweight version inspired by OpenZeppelin Initializable supporting single and chained initializers.
abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    event Initialized(uint8 version);

    modifier initializer() {
        _initializerBefore();
        _;
        _initializerAfter();
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: not initializing");
        _;
    }

    function _initializedVersion() internal view returns (uint8) {
        return _initialized ? 1 : 0;
    }

    function _initializerBefore() internal {
        if (_initializing) {
            require(!_initialized, "Initializable: already initialized");
        } else {
            require(!_initialized, "Initializable: already initialized");
            _initializing = true;
            _initialized = true;
            emit Initialized(1);
        }
    }

    function _initializerAfter() internal {
        if (_initializing) {
            _initializing = false;
        }
    }

    function _disableInitializers() internal {
        require(!_initializing, "Initializable: initializing");
        if (_initialized) {
            return;
        }
        _initialized = true;
        emit Initialized(type(uint8).max);
    }
}
