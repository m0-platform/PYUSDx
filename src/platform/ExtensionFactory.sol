// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { DeployHelpers } from "../../lib/evm-m-extensions/lib/common/script/deploy/DeployHelpers.sol";

import { ISwapFacility } from "../swap/interfaces/ISwapFacility.sol";
import { IExtension } from "./interfaces/IExtension.sol";
import { IExtensionFactory } from "./interfaces/IExtensionFactory.sol";

import { MultiMint } from "./projects/MultiMint.sol";
import { YieldToOne } from "./projects/YieldToOne.sol";

/// @notice ERC-7201 namespaced storage layout for ExtensionFactory.
abstract contract ExtensionFactoryStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.PYUSDXExtensionFactory
    struct ExtensionFactoryStorage {
        mapping(address extension => IExtensionFactory.ExtensionType extensionType) extensionTypes;
        mapping(address extension => bool active) activeExtensions;
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
    /* ============ State Variables ============ */

    /// @inheritdoc IExtensionFactory
    bytes32 public constant FACTORY_MANAGER_ROLE = keccak256("FACTORY_MANAGER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override pyusdx;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    /// @inheritdoc IExtensionFactory
    address public immutable override swapFacility;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Constructs ExtensionFactory implementation contract.
    /// @dev    Sets immutable storage.
    /// @param  pyusdx_       The address of the PYUSDX token.
    /// @param  swapFacility_ The address of the SwapFacility contract.
    constructor(address pyusdx_, address swapFacility_) {
        _disableInitializers();

        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();
        if ((swapFacility = swapFacility_) == address(0)) revert ZeroSwapFacility();
        if (pyusdx != ISwapFacility(swapFacility).pyusdx()) revert PYUSDXMismatch();
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

        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();
        $.yieldToOneImplementation = address(new YieldToOne(pyusdx, swapFacility));
        $.multiMintImplementation = address(new MultiMint(pyusdx, swapFacility));
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
    function setExtensionStatus(address extension, bool status) external override onlyRole(FACTORY_MANAGER_ROLE) {
        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();

        if ($.extensionTypes[extension] == ExtensionType.NONE) {
            revert ExtensionNotRegistered(extension);
        }

        if ($.activeExtensions[extension] == status) return;

        $.activeExtensions[extension] = status;

        emit ExtensionStatusSet(extension, status);
    }

    /// @inheritdoc IExtensionFactory
    function setImplementation(
        ExtensionType extensionType,
        address implementation
    ) external override onlyRole(FACTORY_MANAGER_ROLE) {
        if (extensionType != ExtensionType.YIELD_TO_ONE && extensionType != ExtensionType.MULTI_MINT) {
            revert InvalidExtensionType();
        }

        if (IExtension(implementation).pyusdx() != pyusdx || IExtension(implementation).swapFacility() != swapFacility)
            revert InvalidImplementation();

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
        return _getExtensionFactoryStorage().activeExtensions[extension];
    }

    /* ============ Internal Interactive Functions ============ */

    /// @dev   Registers an extension in the factory.
    /// @param proxy         The address of the proxy.
    /// @param extensionType The type of the extension.
    function _registerExtension(address proxy, ExtensionType extensionType) internal {
        ExtensionFactoryStorage storage $ = _getExtensionFactoryStorage();
        $.extensionTypes[proxy] = extensionType;
        $.activeExtensions[proxy] = true;
    }

    /* ============ Internal View Functions ============ */

    /// @dev    Computes a deployer-namespaced salt whose first 20 bytes match `address(this)`.
    ///         This ensures CreateX's `_guard` takes the `SenderBytes.MsgSender` path (since
    ///         the Factory is CreateX's `msg.sender`), while the deployer-specific hash in
    ///         bytes 21-31 provides per-deployer uniqueness.
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
}
