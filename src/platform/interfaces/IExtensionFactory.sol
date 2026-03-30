// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  PYUSDX Extension Factory interface.
/// @author M0 Labs
interface IExtensionFactory {
    /* ============ Structs ============ */

    /// @notice Parameters for deploying a YieldToOne extension.
    struct YieldToOneParams {
        string name;
        string symbol;
        address yieldRecipient;
        address admin;
        address freezeManager;
        address pauser;
        address yieldRecipientManager;
    }

    /// @notice Parameters for deploying a MultiMint extension.
    struct MultiMintParams {
        string name;
        string symbol;
        address yieldRecipient;
        address admin;
        address assetCapManager;
        address freezeManager;
        address pauser;
        address yieldRecipientManager;
    }

    /* ============ Enums ============ */

    /// @notice The type of PYUSDX extension.
    enum ExtensionType {
        NONE,
        YIELD_TO_ONE,
        MULTI_MINT
    }

    /* ============ Events ============ */

    /// @notice Emitted when an extension is deployed.
    /// @param  extensionType  The type of extension deployed.
    /// @param  proxy          The address of the proxy contract.
    /// @param  proxyAdmin     The address of the ProxyAdmin contract managing the proxy.
    /// @param  implementation The address of the implementation contract.
    /// @param  deployer       The address that deployed the extension.
    event ExtensionDeployed(
        ExtensionType indexed extensionType,
        address proxy,
        address proxyAdmin,
        address indexed implementation,
        address indexed deployer
    );

    /// @notice Emitted when an extension's type is set (or cleared to NONE).
    /// @param  extension     The address of the extension.
    /// @param  extensionType The new extension type.
    event ExtensionTypeSet(address indexed extension, ExtensionType indexed extensionType);

    /// @notice Emitted when an implementation address is set for an extension type.
    /// @param  extensionType  The type of extension.
    /// @param  implementation The new implementation address.
    event ImplementationSet(ExtensionType indexed extensionType, address indexed implementation);

    /// @notice Emitted when a beacon-proxied extension is deployed.
    /// @param  extensionType  The type of extension deployed.
    /// @param  proxy          The address of the BeaconProxy contract.
    /// @param  versionId      The version the proxy is pinned to at deployment.
    /// @param  implementation The resolved implementation address at deployment.
    /// @param  deployer       The address that deployed the extension.
    event BeaconExtensionDeployed(
        ExtensionType indexed extensionType,
        address proxy,
        uint256 versionId,
        address indexed implementation,
        address indexed deployer
    );

    /* ============ Errors ============ */

    /// @notice Thrown if the admin is 0x0.
    error ZeroAdmin();

    /// @notice Thrown if the factory manager is 0x0.
    error ZeroFactoryManager();

    /// @notice Thrown if PYUSDX is 0x0.
    error ZeroPYUSDX();

    /// @notice Thrown if swap facility is 0x0.
    error ZeroSwapFacility();

    /// @notice Thrown if PYUSDX address does not match the one in SwapFacility.
    error PYUSDXMismatch();

    /// @notice Thrown if the extension is 0x0.
    error ZeroExtension();

    /// @notice Thrown if the extension address is invalid (e.g. wrong pyusdx/swapFacility wiring).
    error InvalidExtension();

    /// @notice Thrown if the extension type is invalid for setting implementation.
    error InvalidExtensionType();

    /// @notice Thrown if the versioned beacon is 0x0.
    error ZeroVersionedBeacon();

    /// @notice Thrown if the deployed proxy address does not match the pre-computed address.
    error DeployedAddressMismatch();

    /* ============ View/Pure Functions ============ */

    /// @notice The role identifier for the factory manager role.
    function FACTORY_MANAGER_ROLE() external view returns (bytes32);

    /// @notice The type key for YieldToOne extensions in the VersionedBeacon.
    function YIELD_TO_ONE_TYPE_KEY() external pure returns (bytes32);

    /// @notice The type key for MultiMint extensions in the VersionedBeacon.
    function MULTI_MINT_TYPE_KEY() external pure returns (bytes32);

    /// @notice Returns the predicted deployment address for an extension with the given extension name and deployer.
    /// @param  deployer      The address of the deployer (embedded in salt for deployer-specific addresses).
    /// @param  extensionName The name of the extension (determines the deployment address).
    /// @return The predicted proxy address.
    function getExtensionAddress(address deployer, string calldata extensionName) external view returns (address);

    /// @notice Returns the extension type for a given extension address.
    /// @param  extension The address of the extension.
    /// @return The extension type (NONE if not registered).
    function getExtensionType(address extension) external view returns (ExtensionType);

    /// @notice Returns the cached implementation address for a given extension type.
    /// @param  extensionType The type of extension.
    /// @return The implementation address.
    function getImplementation(ExtensionType extensionType) external view returns (address);

    /// @notice Returns true if the extension is approved (active).
    /// @param  extension The address of the extension to check.
    /// @return True if approved, false otherwise.
    function isApprovedExtension(address extension) external view returns (bool);

    /// @notice The address of the PYUSDX token contract.
    function pyusdx() external view returns (address);

    /// @notice The address of the SwapFacility contract.
    function swapFacility() external view returns (address);

    /// @notice The address of the VersionedBeacon contract.
    function versionedBeacon() external view returns (address);

    /* ============ Deployment Functions ============ */

    /// @notice Deploys a new YieldToOne extension.
    /// @param  extensionName The name of the extension (determines the deployment address, max 32 bytes).
    /// @param  params        The deployment parameters (token name, symbol, roles, etc.).
    /// @return proxy         The address of the deployed proxy.
    /// @return proxyAdmin    The address of the deployed ProxyAdmin.
    /// @return implementation The address of the deployed implementation.
    function deployYieldToOne(
        string calldata extensionName,
        YieldToOneParams calldata params
    ) external returns (address proxy, address proxyAdmin, address implementation);

    /// @notice Deploys a new MultiMint extension.
    /// @param  extensionName The name of the extension (determines the deployment address, max 32 bytes).
    /// @param  params        The deployment parameters (token name, symbol, roles, etc.).
    /// @return proxy         The address of the deployed proxy.
    /// @return proxyAdmin    The address of the deployed ProxyAdmin.
    /// @return implementation The address of the deployed implementation.
    function deployMultiMint(
        string calldata extensionName,
        MultiMintParams calldata params
    ) external returns (address proxy, address proxyAdmin, address implementation);

    /// @notice Deploys a new BeaconProxy YieldToOne extension pinned to a registered version.
    /// @param  extensionName The name of the extension (determines the deployment address, max 32 bytes).
    /// @param  versionId     The version ID to pin the extension to.
    /// @param  params        The deployment parameters (token name, symbol, roles, etc.).
    /// @return proxy         The address of the deployed BeaconProxy.
    function deployBeaconYieldToOne(
        string calldata extensionName,
        uint256 versionId,
        YieldToOneParams calldata params
    ) external returns (address proxy);

    /// @notice Deploys a new BeaconProxy MultiMint extension pinned to a registered version.
    /// @param  extensionName The name of the extension (determines the deployment address, max 32 bytes).
    /// @param  versionId     The version ID to pin the extension to.
    /// @param  params        The deployment parameters (token name, symbol, roles, etc.).
    /// @return proxy         The address of the deployed BeaconProxy.
    function deployBeaconMultiMint(
        string calldata extensionName,
        uint256 versionId,
        MultiMintParams calldata params
    ) external returns (address proxy);

    /* ============ Admin Functions ============ */

    /// @notice Sets the extension type for a given extension address. Setting to NONE revokes approval.
    /// @dev    MUST only be callable by an address with the `FACTORY_MANAGER_ROLE` role.
    ///         Validates the extension via `_revertIfInvalidExtension` when setting to a non-NONE type.
    /// @param  extension     The address of the extension.
    /// @param  extensionType The extension type to assign (NONE to revoke).
    function setExtensionType(address extension, ExtensionType extensionType) external;

    /// @notice Sets the cached implementation address for a given extension type.
    /// @dev    MUST only be callable by an address with the `FACTORY_MANAGER_ROLE` role.
    ///         Only affects future deployments — existing proxies are unaffected.
    /// @param  extensionType  The type of extension.
    /// @param  implementation The new implementation address.
    function setImplementation(ExtensionType extensionType, address implementation) external;
}
