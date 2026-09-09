// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { UUPSUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { ERC20ExtendedUpgradeable } from "../../lib/evm-m-extensions/lib/common/src/ERC20ExtendedUpgradeable.sol";
import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IERC1822Proxiable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC1822.sol";
import { ERC1967Utils } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { StorageSlot } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol";

import { MultiMint } from "../../src/platform/projects/MultiMint.sol";
import { YieldToOneStorageLayout } from "../../src/platform/projects/YieldToOne.sol";

/// @dev Step 1: the only implementation M0 has to register on the shared beacon. Identical to
///      MultiMint except that it can rewrite the ERC-1967 implementation slot itself once pinned.
contract MultiMintUUPSBridge is MultiMint, UUPSUpgradeable {
    constructor(address pyusdx_, address swapFacility_) MultiMint(pyusdx_, swapFacility_) {}

    function _authorizeUpgrade(address) internal override onlyRole(VERSION_MANAGER_ROLE) {}
}

/// @dev Step 2: an implementation the extension owner deploys and installs without M0. Still a
///      MultiMint, but the beacon return path is severed.
contract MultiMintSelfManagedV2 is MultiMintUUPSBridge {
    error Detached();

    constructor(address pyusdx_, address swapFacility_) MultiMintUUPSBridge(pyusdx_, swapFacility_) {}

    function spikeVersion() external pure returns (uint256) {
        return 2;
    }

    function pinVersion(uint256) external pure override {
        revert Detached();
    }

    function unpinVersion() external pure override {
        revert Detached();
    }
}

/// @dev Step 3 (the migration case): a token that has left the PYUSDX platform entirely. No
///      Extension base, no pyusdx/swapFacility immutables, issuer-driven mint/burn. Reuses the
///      ERC-7201 namespaces so balances, allowances, metadata, and roles carry over unchanged.
contract StandaloneToken is
    ERC20ExtendedUpgradeable,
    YieldToOneStorageLayout,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant VERSION_MANAGER_ROLE = keccak256("VERSION_MANAGER_ROLE");

    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    /// @dev Runs inside upgradeToAndCall, so msg.sender is the upgrader.
    function migrate(address issuer) external reinitializer(2) onlyRole(VERSION_MANAGER_ROLE) {
        _grantRole(ISSUER_ROLE, issuer);
    }

    function mint(address to, uint256 amount) external onlyRole(ISSUER_ROLE) {
        YieldToOneStorage storage $ = _getYieldToOneStorage();
        $.totalSupply += amount;
        $.balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(ISSUER_ROLE) {
        YieldToOneStorage storage $ = _getYieldToOneStorage();
        uint256 balance = $.balanceOf[from];
        if (balance < amount) revert InsufficientBalance(from, balance, amount);
        $.balanceOf[from] = balance - amount;
        $.totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @dev The former PYUSDX backing is plain ERC20 inventory to the new code.
    function sweep(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(to, amount);
    }

    function balanceOf(address account) public view returns (uint256) {
        return _getYieldToOneStorage().balanceOf[account];
    }

    function totalSupply() public view returns (uint256) {
        return _getYieldToOneStorage().totalSupply;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        YieldToOneStorage storage $ = _getYieldToOneStorage();
        uint256 balance = $.balanceOf[sender];
        if (balance < amount) revert InsufficientBalance(sender, balance, amount);
        $.balanceOf[sender] = balance - amount;
        $.balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}

/// @dev Size-conscious alternative to inheriting OZ UUPSUpgradeable: the same ERC-1967 write and
///      ERC-1822 target check, without proxiableUUID/UPGRADE_INTERFACE_VERSION/onlyProxy plumbing.
///      Scoped to one proxy so registering it on the shared beacon is not a global exit door.
contract MultiMintLeanBridge is MultiMint {
    error NotPinnedForUpgrade();
    error NotProxiable(address implementation);
    error NotAllowedProxy(address proxy);

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable allowedProxy;

    constructor(address pyusdx_, address swapFacility_, address allowedProxy_) MultiMint(pyusdx_, swapFacility_) {
        allowedProxy = allowedProxy_;
    }

    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable onlyRole(VERSION_MANAGER_ROLE) {
        if (address(this) != allowedProxy) revert NotAllowedProxy(address(this));
        if (StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value == address(0)) revert NotPinnedForUpgrade();
        if (IERC1822Proxiable(newImplementation).proxiableUUID() != _IMPLEMENTATION_SLOT) {
            revert NotProxiable(newImplementation);
        }
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}
