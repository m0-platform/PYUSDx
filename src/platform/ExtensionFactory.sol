// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";

import { ExtensionBeaconProxy } from "./ExtensionBeaconProxy.sol";
import { IExtensionBeacon } from "./interfaces/IExtensionBeacon.sol";
import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";
import { MultiMint } from "./projects/MultiMint.sol";
import { YieldToOne } from "./projects/YieldToOne.sol";
import { IExtension } from "./interfaces/IExtension.sol";
import { IExtensionFactory } from "./interfaces/IExtensionFactory.sol";

/// @notice ERC-7201 namespaced storage layout for ExtensionFactory.
abstract contract ExtensionFactoryStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDXExtensionFactory
    struct ExtensionFactoryStorage {
        mapping(address extension => IExtensionFactory.ExtensionType extensionType) extensionTypes;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDXExtensionFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _EXTENSION_FACTORY_STORAGE_LOCATION =
        0xa4153a6682de332cda5838d23ee5e88a3b57ff66d9351fa396c29717c1349400;

    function _getExtensionFactoryStorage() internal pure returns (ExtensionFactoryStorage storage $) {
        bytes32 location = _EXTENSION_FACTORY_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }
}

/// @title  Extension Factory
/// @notice A factory contract for deploying and registering PYUSDX extensions (YieldToOne, MultiMint).
///         Serves as the single source of truth for extension approval in the SwapFacility.
///         Uses separate ExtensionBeacon instances for each extension type, deploying ExtensionBeaconProxy instances.
/// @author M0 Labs
contract ExtensionFactory is
    IExtensionFactory,
    Initializable,
    AccessControlUpgradeable,
    ExtensionFactoryStorageLayout,
    DeployHelpers
{
    /* ============ Variables ============ */

    /// @inheritdoc IExtensionFactory
    bytes32 public constant FACTORY_MANAGER_ROLE = keccak256("FACTORY_MANAGER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override pyusdx;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override swapFacility;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override yieldToOneBeacon;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override multiMintBeacon;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs ExtensionFactory implementation contract.
    /// @dev    Sets immutable storage and validates wiring.
    /// @param  pyusdx_            The address of the PYUSDX token.
    /// @param  swapFacility_      The address of the SwapFacility contract.
    /// @param  yieldToOneBeacon_  The address of the YieldToOne ExtensionBeacon contract.
    /// @param  multiMintBeacon_   The address of the MultiMint ExtensionBeacon contract.
    constructor(address pyusdx_, address swapFacility_, address yieldToOneBeacon_, address multiMintBeacon_) {
        _disableInitializers();

        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();
        if (pyusdx != ISwapFacility(swapFacility).pyusdx()) revert PYUSDXMismatch();

        _revertIfInvalidBeacon(yieldToOneBeacon_);
        _revertIfInvalidBeacon(multiMintBeacon_);
        if (yieldToOneBeacon_ == multiMintBeacon_) revert SameBeacon();

        yieldToOneBeacon = yieldToOneBeacon_;
        multiMintBeacon = multiMintBeacon_;
    }

    /* ============ Initializer ============ */

    /// @notice Initializes the ExtensionFactory proxy.
    /// @param  admin          The address of the admin.
    /// @param  factoryManager The address of the factory manager.
    function initialize(address admin, address factoryManager) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (factoryManager == address(0)) revert ZeroFactoryManager();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FACTORY_MANAGER_ROLE, factoryManager);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IExtensionFactory
    function deployYieldToOne(
        string calldata extensionName,
        YieldToOneParams calldata params
    ) external returns (address proxy, address implementation) {
        _revertIfZeroAdmin(params.admin);

        implementation = IExtensionBeacon(yieldToOneBeacon).implementation();

        bytes memory initData = abi.encodeWithSelector(
            YieldToOne.initialize.selector,
            params.name,
            params.symbol,
            params.yieldRecipient,
            params.admin,
            params.freezeManager,
            params.pauser,
            params.yieldRecipientManager,
            params.versionManager
        );

        proxy = _deployCreate3BeaconProxy(yieldToOneBeacon, initData, _computeExtensionSalt(msg.sender, extensionName));

        _setExtensionType(proxy, ExtensionType.YIELD_TO_ONE);

        emit ExtensionDeployed(ExtensionType.YIELD_TO_ONE, proxy, implementation, msg.sender);
    }

    /// @inheritdoc IExtensionFactory
    function deployMultiMint(
        string calldata extensionName,
        MultiMintParams calldata params
    ) external returns (address proxy, address implementation) {
        _revertIfZeroAdmin(params.admin);

        implementation = IExtensionBeacon(multiMintBeacon).implementation();

        bytes memory initData = abi.encodeWithSelector(
            MultiMint.initialize.selector,
            params.name,
            params.symbol,
            params.yieldRecipient,
            params.admin,
            params.assetCapManager,
            params.freezeManager,
            params.pauser,
            params.yieldRecipientManager,
            params.versionManager
        );

        proxy = _deployCreate3BeaconProxy(multiMintBeacon, initData, _computeExtensionSalt(msg.sender, extensionName));

        _setExtensionType(proxy, ExtensionType.MULTI_MINT);

        emit ExtensionDeployed(ExtensionType.MULTI_MINT, proxy, implementation, msg.sender);
    }

    /// @inheritdoc IExtensionFactory
    function registerExtension(
        address extension,
        ExtensionType extensionType
    ) external override onlyRole(FACTORY_MANAGER_ROLE) {
        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();
        IExtensionFactory.ExtensionType currentType = $.extensionTypes[extension];

        if (currentType == extensionType) return;

        if (extensionType != IExtensionFactory.ExtensionType.NONE) {
            if (currentType != IExtensionFactory.ExtensionType.NONE) revert ExtensionAlreadyRegistered();
            _revertIfInvalidExtension(extension);
        }

        $.extensionTypes[extension] = extensionType;

        emit ExtensionTypeSet(extension, extensionType);
    }

    /* ============ Public Functions ============ */

    /// @inheritdoc IExtensionFactory
    function getExtensionAddress(address deployer, string calldata extensionName) external view returns (address) {
        return _getCreate3Address(address(this), _computeExtensionSalt(deployer, extensionName));
    }

    /// @inheritdoc IExtensionFactory
    function getExtensionType(address extension) external view override returns (ExtensionType) {
        return _getExtensionFactoryStorage().extensionTypes[extension];
    }

    /// @inheritdoc IExtensionFactory
    function getImplementation(ExtensionType extensionType) external view override returns (address) {
        if (extensionType == ExtensionType.YIELD_TO_ONE) {
            return IExtensionBeacon(yieldToOneBeacon).implementation();
        } else if (extensionType == ExtensionType.MULTI_MINT) {
            return IExtensionBeacon(multiMintBeacon).implementation();
        }

        revert InvalidExtension();
    }

    /// @inheritdoc IExtensionFactory
    function isApprovedExtension(address extension) public view override returns (bool) {
        return _getExtensionFactoryStorage().extensionTypes[extension] != ExtensionType.NONE;
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev   Writes the extension type for `proxy` directly, without role or validation checks.
    /// @param proxy         The address of the proxy.
    /// @param extensionType The type of the extension.
    function _setExtensionType(address proxy, ExtensionType extensionType) internal {
        _getExtensionFactoryStorage().extensionTypes[proxy] = extensionType;
    }

    /// @dev    Deploys an ExtensionBeaconProxy via CREATE3.
    /// @param  beacon   The beacon address for the proxy.
    /// @param  initData The initializer calldata.
    /// @param  salt     The CREATE3 salt.
    /// @return proxy    The address of the deployed proxy.
    function _deployCreate3BeaconProxy(address beacon, bytes memory initData, bytes32 salt) internal returns (address) {
        bytes memory initCode = abi.encodePacked(type(ExtensionBeaconProxy).creationCode, abi.encode(beacon, initData));

        return _deployCreate3(initCode, salt);
    }

    /* ============ Internal View Functions ============ */

    /// @dev    Computes a deployer-namespaced salt whose first 20 bytes match `address(this)`.
    /// @param  deployer      The address of the deployer (e.g. `msg.sender` in deploy functions).
    /// @param  extensionName The human-readable extension name.
    /// @return The computed salt.
    function _computeExtensionSalt(address deployer, string calldata extensionName) internal view returns (bytes32) {
        return
            bytes32(
                abi.encodePacked(
                    bytes20(address(this)),
                    bytes1(0), // disable cross-chain redeploy protection
                    bytes11(keccak256(abi.encodePacked(deployer, extensionName)))
                )
            );
    }

    /// @dev   Reverts if the given admin address is the zero address.
    /// @param admin The admin address to check.
    function _revertIfZeroAdmin(address admin) internal pure {
        if (admin == address(0)) revert ZeroAdmin();
    }

    /// @dev   Reverts if the beacon address is zero or wired to wrong pyusdx/swapFacility.
    /// @param beacon The beacon address to validate.
    function _revertIfInvalidBeacon(address beacon) internal view {
        if (beacon == address(0)) revert ZeroBeacon();

        if (IExtensionBeacon(beacon).pyusdx() != pyusdx || IExtensionBeacon(beacon).swapFacility() != swapFacility)
            revert InvalidBeacon();
    }

    /// @dev   Reverts if the extension address is zero or wired to wrong pyusdx/swapFacility.
    /// @param extension The extension address to validate.
    function _revertIfInvalidExtension(address extension) internal view {
        if (extension == address(0)) revert ZeroExtension();

        if (IExtension(extension).pyusdx() != pyusdx || IExtension(extension).swapFacility() != swapFacility)
            revert InvalidExtension();
    }
}
