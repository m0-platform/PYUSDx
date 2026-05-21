// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

/// @title  PYUSDX Extension Factory interface.
/// @author M0 Labs
interface IExtensionFactory {
    /* ============ Enums ============ */

    /// @notice The type of PYUSDX extension.
    enum ExtensionType {
        NONE,
        YIELD_TO_ONE,
        MULTI_MINT
    }

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
        address versionManager;
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
        address versionManager;
    }

    /* ============ Events ============ */

    /// @notice Emitted when an extension is deployed.
    /// @param  extensionType  The type of extension deployed.
    /// @param  proxy          The address of the proxy contract.
    /// @param  implementation The address of the implementation contract.
    /// @param  deployer       The address that deployed the extension.
    event ExtensionDeployed(
        ExtensionType indexed extensionType,
        address proxy,
        address indexed implementation,
        address indexed deployer
    );

    /// @notice Emitted when an extension's type is set (or cleared to NONE).
    /// @param  extension     The address of the extension.
    /// @param  extensionType The new extension type.
    event ExtensionTypeSet(address indexed extension, ExtensionType indexed extensionType);

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

    /// @notice Thrown if a beacon address is 0x0.
    error ZeroBeacon();

    /// @notice Thrown if a beacon is invalid (e.g. wrong pyusdx/swapFacility wiring).
    error InvalidBeacon();

    /// @notice Thrown if the YieldToOne and MultiMint beacons share the same address.
    error SameBeacon();

    /// @notice Thrown if the extension is 0x0.
    error ZeroExtension();

    /// @notice Thrown if the extension address is invalid (e.g. wrong pyusdx/swapFacility wiring).
    error InvalidExtension();

    /// @notice Thrown when attempting to change a registered extension's type to a different non-NONE type.
    error ExtensionAlreadyRegistered();

    /* ============ View/Pure Functions ============ */

    /// @notice The role identifier for the factory manager role.
    function FACTORY_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Returns the predicted deployment address for an extension with the given extension name and deployer.
    /// @param  deployer      The address of the deployer (embedded in salt for deployer-specific addresses).
    /// @param  extensionName The name of the extension (determines the deployment address).
    /// @return The predicted proxy address.
    function getExtensionAddress(address deployer, string calldata extensionName) external view returns (address);

    /// @notice Returns the extension type for a given extension address.
    /// @param  extension The address of the extension.
    /// @return The extension type (NONE if not registered).
    function getExtensionType(address extension) external view returns (ExtensionType);

    /// @notice Returns the latest implementation address for a given extension type.
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

    /// @notice The address of the YieldToOne beacon contract.
    function yieldToOneBeacon() external view returns (address);

    /// @notice The address of the MultiMint beacon contract.
    function multiMintBeacon() external view returns (address);

    /* ============ Deployment Functions ============ */

    /// @notice Deploys a new YieldToOne extension.
    /// @param  extensionName The name of the extension (determines the deployment address).
    /// @param  params        The deployment parameters (token name, symbol, roles, etc.).
    /// @return proxy         The address of the deployed proxy.
    /// @return implementation The address of the deployed implementation.
    function deployYieldToOne(
        string calldata extensionName,
        YieldToOneParams calldata params
    ) external returns (address proxy, address implementation);

    /// @notice Deploys a new MultiMint extension.
    /// @param  extensionName The name of the extension (determines the deployment address).
    /// @param  params        The deployment parameters (token name, symbol, roles, etc.).
    /// @return proxy         The address of the deployed proxy.
    /// @return implementation The address of the deployed implementation.
    function deployMultiMint(
        string calldata extensionName,
        MultiMintParams calldata params
    ) external returns (address proxy, address implementation);

    /* ============ Admin Functions ============ */

    /// @notice Registers an extension under a given type. Setting to NONE revokes approval.
    /// @dev    MUST only be callable by an address with the `FACTORY_MANAGER_ROLE` role.
    ///         Validates the extension via `_revertIfInvalidExtension` when setting to a non-NONE type.
    ///         Reverts with `ExtensionAlreadyRegistered` when the extension is already registered
    ///         and a different non-NONE type is requested.
    ///         The extension must be unregistered (set to NONE) before being re-registered at a new type.
    /// @param  extension     The address of the extension.
    /// @param  extensionType The extension type to assign (NONE to revoke).
    function registerExtension(address extension, ExtensionType extensionType) external;
}
