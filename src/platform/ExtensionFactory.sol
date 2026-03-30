// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";
import { BeaconProxy } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";
import { MultiMint } from "./projects/MultiMint.sol";
import { YieldToOne } from "./projects/YieldToOne.sol";
import { IExtension } from "./interfaces/IExtension.sol";
import { IExtensionFactory } from "./interfaces/IExtensionFactory.sol";
import { IVersionedBeacon } from "./interfaces/IVersionedBeacon.sol";

/// @notice ERC-7201 namespaced storage layout for ExtensionFactory.
abstract contract ExtensionFactoryStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDXExtensionFactory
    struct ExtensionFactoryStorage {
        mapping(address extension => IExtensionFactory.ExtensionType extensionType) extensionTypes;
        address yieldToOneImplementation;
        address multiMintImplementation;
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

    /// @inheritdoc IExtensionFactory
    bytes32 public constant YIELD_TO_ONE_TYPE_KEY = keccak256("YIELD_TO_ONE");

    /// @inheritdoc IExtensionFactory
    bytes32 public constant MULTI_MINT_TYPE_KEY = keccak256("MULTI_MINT");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override pyusdx;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override swapFacility;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override versionedBeacon;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs ExtensionFactory implementation contract.
    /// @dev    Sets immutable storage. `versionedBeacon_` may be address(0) if beacon deployment
    ///         functions are not needed (e.g., legacy deployments using TransparentProxy only).
    /// @param  pyusdx_          The address of the PYUSDX token.
    /// @param  swapFacility_    The address of the SwapFacility contract.
    /// @param  versionedBeacon_ The address of the VersionedBeacon contract (0x0 to disable beacon deploys).
    constructor(address pyusdx_, address swapFacility_, address versionedBeacon_) {
        _disableInitializers();

        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();
        if (pyusdx != ISwapFacility(swapFacility).pyusdx()) revert PYUSDXMismatch();

        versionedBeacon = versionedBeacon_;
    }

    /* ============ Initializer ============ */

    /// @notice Initializes the ExtensionFactory proxy.
    /// @param  admin                    The address of the admin.
    /// @param  factoryManager           The address of the factory manager.
    /// @param  yieldToOneImplementation The YieldToOne implementation address.
    /// @param  multiMintImplementation  The MultiMint implementation address.
    function initialize(
        address admin,
        address factoryManager,
        address yieldToOneImplementation,
        address multiMintImplementation
    ) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (factoryManager == address(0)) revert ZeroFactoryManager();
        _revertIfInvalidExtension(yieldToOneImplementation);
        _revertIfInvalidExtension(multiMintImplementation);

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FACTORY_MANAGER_ROLE, factoryManager);

        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();
        $.yieldToOneImplementation = yieldToOneImplementation;
        $.multiMintImplementation = multiMintImplementation;
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IExtensionFactory
    function deployYieldToOne(
        string calldata extensionName,
        YieldToOneParams calldata params
    ) external returns (address proxy, address proxyAdmin, address implementation) {
        _revertIfZeroAdmin(params.admin);

        implementation = _getExtensionFactoryStorage().yieldToOneImplementation;

        bytes memory initData = abi.encodeWithSelector(
            YieldToOne.initialize.selector,
            params.name,
            params.symbol,
            params.yieldRecipient,
            params.admin,
            params.freezeManager,
            params.pauser,
            params.yieldRecipientManager
        );

        // NOTE: Deploy at a predicted address using CREATE3, reverts when same deployer + extensionName.
        //       params.admin is the ProxyAdmin owner and extension admin.
        proxy = _deployCreate3TransparentProxy(
            implementation,
            params.admin,
            initData,
            _computeExtensionSalt(msg.sender, extensionName)
        );

        proxyAdmin = _getProxyAdmin(proxy);

        _registerExtension(proxy, ExtensionType.YIELD_TO_ONE);

        emit ExtensionDeployed(ExtensionType.YIELD_TO_ONE, proxy, proxyAdmin, implementation, msg.sender);
    }

    /// @inheritdoc IExtensionFactory
    function deployMultiMint(
        string calldata extensionName,
        MultiMintParams calldata params
    ) external returns (address proxy, address proxyAdmin, address implementation) {
        _revertIfZeroAdmin(params.admin);

        implementation = _getExtensionFactoryStorage().multiMintImplementation;

        bytes memory initData = abi.encodeWithSelector(
            MultiMint.initialize.selector,
            params.name,
            params.symbol,
            params.yieldRecipient,
            params.admin,
            params.assetCapManager,
            params.freezeManager,
            params.pauser,
            params.yieldRecipientManager
        );

        // NOTE: Deploy at a predicted address using CREATE3, reverts when same deployer + extensionName.
        //       params.admin is the ProxyAdmin owner and extension admin.
        proxy = _deployCreate3TransparentProxy(
            implementation,
            params.admin,
            initData,
            _computeExtensionSalt(msg.sender, extensionName)
        );

        proxyAdmin = _getProxyAdmin(proxy);

        _registerExtension(proxy, ExtensionType.MULTI_MINT);

        emit ExtensionDeployed(ExtensionType.MULTI_MINT, proxy, proxyAdmin, implementation, msg.sender);
    }

    /// @inheritdoc IExtensionFactory
    function deployBeaconYieldToOne(
        string calldata extensionName,
        uint256 versionId,
        YieldToOneParams calldata params
    ) external returns (address proxy) {
        _revertIfZeroAdmin(params.admin);

        address impl = IVersionedBeacon(versionedBeacon).getVersion(YIELD_TO_ONE_TYPE_KEY, versionId);

        bytes memory initData = abi.encodeWithSelector(
            YieldToOne.initialize.selector,
            params.name,
            params.symbol,
            params.yieldRecipient,
            params.admin,
            params.freezeManager,
            params.pauser,
            params.yieldRecipientManager
        );

        proxy = _deployBeaconProxy(extensionName, versionId, YIELD_TO_ONE_TYPE_KEY, params.admin, initData);

        _registerExtension(proxy, ExtensionType.YIELD_TO_ONE);

        emit BeaconExtensionDeployed(ExtensionType.YIELD_TO_ONE, proxy, versionId, impl, msg.sender);
    }

    /// @inheritdoc IExtensionFactory
    function deployBeaconMultiMint(
        string calldata extensionName,
        uint256 versionId,
        MultiMintParams calldata params
    ) external returns (address proxy) {
        _revertIfZeroAdmin(params.admin);

        address impl = IVersionedBeacon(versionedBeacon).getVersion(MULTI_MINT_TYPE_KEY, versionId);

        bytes memory initData = abi.encodeWithSelector(
            MultiMint.initialize.selector,
            params.name,
            params.symbol,
            params.yieldRecipient,
            params.admin,
            params.assetCapManager,
            params.freezeManager,
            params.pauser,
            params.yieldRecipientManager
        );

        proxy = _deployBeaconProxy(extensionName, versionId, MULTI_MINT_TYPE_KEY, params.admin, initData);

        _registerExtension(proxy, ExtensionType.MULTI_MINT);

        emit BeaconExtensionDeployed(ExtensionType.MULTI_MINT, proxy, versionId, impl, msg.sender);
    }

    /// @inheritdoc IExtensionFactory
    function setExtensionType(
        address extension,
        ExtensionType extensionType
    ) external override onlyRole(FACTORY_MANAGER_ROLE) {
        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();

        if ($.extensionTypes[extension] == extensionType) return;

        if (extensionType != ExtensionType.NONE) {
            _revertIfInvalidExtension(extension);
        }

        $.extensionTypes[extension] = extensionType;

        emit ExtensionTypeSet(extension, extensionType);
    }

    /// @inheritdoc IExtensionFactory
    function setImplementation(
        ExtensionType extensionType,
        address implementation
    ) external override onlyRole(FACTORY_MANAGER_ROLE) {
        if (extensionType != ExtensionType.YIELD_TO_ONE && extensionType != ExtensionType.MULTI_MINT) {
            revert InvalidExtensionType();
        }

        _revertIfInvalidExtension(implementation);

        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();

        if (extensionType == ExtensionType.YIELD_TO_ONE) {
            $.yieldToOneImplementation = implementation;
        } else {
            $.multiMintImplementation = implementation;
        }

        emit ImplementationSet(extensionType, implementation);
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
        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();

        if (extensionType == ExtensionType.YIELD_TO_ONE) return $.yieldToOneImplementation;
        if (extensionType == ExtensionType.MULTI_MINT) return $.multiMintImplementation;

        return address(0);
    }

    /// @inheritdoc IExtensionFactory
    function isApprovedExtension(address extension) public view override returns (bool) {
        return _getExtensionFactoryStorage().extensionTypes[extension] != ExtensionType.NONE;
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev   Deploys a BeaconProxy via CREATE3 and registers it in the VersionedBeacon.
    /// @param extensionName The human-readable extension name (determines deployment address).
    /// @param versionId     The version ID to pin the proxy to.
    /// @param typeKey       The extension type key for the VersionedBeacon.
    /// @param admin         The extension owner (registered in beacon for version pinning).
    /// @param initData      The encoded initializer call data.
    function _deployBeaconProxy(
        string calldata extensionName,
        uint256 versionId,
        bytes32 typeKey,
        address admin,
        bytes memory initData
    ) internal returns (address proxy) {
        if (versionedBeacon == address(0)) revert ZeroVersionedBeacon();

        bytes32 salt = _computeExtensionSalt(msg.sender, extensionName);

        // Pre-compute the proxy address for beacon registration.
        proxy = _getCreate3Address(address(this), salt);

        // Register in beacon BEFORE deploying so implementation() resolves during construction.
        IVersionedBeacon(versionedBeacon).registerProxy(proxy, typeKey, versionId, admin);

        // Deploy BeaconProxy via CREATE3.
        address deployed = _deployCreate3(
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(versionedBeacon, initData)),
            salt
        );

        if (deployed != proxy) revert DeployedAddressMismatch();
    }

    /// @dev   Registers an extension in the factory.
    /// @param proxy         The address of the proxy.
    /// @param extensionType The type of the extension.
    function _registerExtension(address proxy, ExtensionType extensionType) internal {
        _getExtensionFactoryStorage().extensionTypes[proxy] = extensionType;
    }

    /* ============ Internal View Functions ============ */

    /// @dev    Computes a deployer-namespaced salt whose first 20 bytes match `address(this)`.
    ///         This ensures CreateX's `_guard` takes the `SenderBytes.MsgSender` path (since
    ///         the Factory is CreateX's `msg.sender`), while the deployer-specific hash in
    ///         bytes 21-31 provides per-deployer uniqueness.
    ///         Note: the salt is scoped to deployer+name only, not extension type — the same
    ///         extensionName cannot be reused across YieldToOne and MultiMint by the same deployer.
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

    /// @dev    Computes the ProxyAdmin address deployed by the TransparentUpgradeableProxy.
    ///         The ProxyAdmin is created via CREATE in the proxy constructor with nonce 1.
    /// @param  proxy The address of the proxy.
    /// @return The address of the ProxyAdmin.
    function _getProxyAdmin(address proxy) internal pure returns (address) {
        // NOTE: ProxyAdmin is deployed by the proxy via CREATE with nonce 1
        //       Address = keccak256(0xd6 || 0x94 || proxy || 0x01)
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01)));
        return address(uint160(uint256(hash)));
    }

    /// @dev   Reverts if the given admin address is the zero address.
    /// @param admin The admin address to check.
    function _revertIfZeroAdmin(address admin) internal pure {
        if (admin == address(0)) revert ZeroAdmin();
    }

    /// @dev   Reverts if the extension address is zero or wired to wrong pyusdx/swapFacility.
    /// @param extension The extension address to validate.
    function _revertIfInvalidExtension(address extension) internal view {
        if (extension == address(0)) revert ZeroExtension();

        if (IExtension(extension).pyusdx() != pyusdx || IExtension(extension).swapFacility() != swapFacility)
            revert InvalidExtension();
    }
}
