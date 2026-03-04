// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/// @title  PYUSDX Extension Factory interface.
/// @author M0 Labs
interface IPYUSDXExtensionFactory {
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

    /// @notice Emitted when an extension's active status is set.
    /// @param  extension The address of the extension.
    /// @param  active    True if the extension is active, false otherwise.
    event ExtensionStatusSet(address indexed extension, bool indexed active);

    /// @notice Emitted when an implementation address is set for an extension type.
    /// @param  extensionType  The type of extension.
    /// @param  implementation The new implementation address.
    event ImplementationSet(ExtensionType indexed extensionType, address indexed implementation);

    /* ============ Custom Errors ============ */

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

    /// @notice Thrown if the extension is not registered in the factory.
    error ExtensionNotRegistered(address extension);

    /// @notice Thrown if the implementation address is invalid (e.g., wrong pyusdx/swapFacility wiring).
    error InvalidImplementation();

    /// @notice Thrown if the extension type is invalid for setting implementation.
    error InvalidExtensionType();

    /* ============ View/Pure Functions ============ */

    /// @notice The role identifier for the factory manager role.
    function FACTORY_MANAGER_ROLE() external view returns (bytes32);

    /// @notice Returns true if the extension is approved (active).
    /// @param  extension The address of the extension to check.
    /// @return True if approved, false otherwise.
    function isApprovedExtension(address extension) external view returns (bool);

    /// @notice Returns the extension type for a given extension address.
    /// @param  extension The address of the extension.
    /// @return The extension type (NONE if not registered).
    function getExtensionType(address extension) external view returns (ExtensionType);

    /// @notice Returns the cached implementation address for a given extension type.
    /// @param  extensionType The type of extension.
    /// @return The implementation address.
    function getImplementation(ExtensionType extensionType) external view returns (address);

    /// @notice The address of the PYUSDX token contract.
    function pyusdx() external view returns (address);

    /// @notice The address of the SwapFacility contract.
    function swapFacility() external view returns (address);

    /* ============ Deployment Functions ============ */

    /// @notice Deploys a new YieldToOne extension.
    /// @param  name                  The name of the token.
    /// @param  symbol                The symbol of the token.
    /// @param  yieldRecipient        The address of the yield recipient.
    /// @param  admin                 The address of the admin (also used as proxy admin owner).
    /// @param  freezeManager         The address of the freeze manager.
    /// @param  yieldRecipientManager The address of the yield recipient manager.
    /// @param  pauser                The address of the pauser.
    /// @return proxy                 The address of the deployed proxy.
    /// @return proxyAdmin            The address of the deployed ProxyAdmin.
    /// @return implementation        The address of the deployed implementation.
    function deployYieldToOne(
        string calldata name,
        string calldata symbol,
        address yieldRecipient,
        address admin,
        address freezeManager,
        address yieldRecipientManager,
        address pauser
    ) external returns (address proxy, address proxyAdmin, address implementation);

    /// @notice Deploys a new MultiMint extension.
    /// @param  name                  The name of the token.
    /// @param  symbol                The symbol of the token.
    /// @param  yieldRecipient        The address of the yield recipient.
    /// @param  admin                 The address of the admin (also used as proxy admin owner).
    /// @param  assetCapManager       The address of the asset cap manager.
    /// @param  freezeManager         The address of the freeze manager.
    /// @param  pauser                The address of the pauser.
    /// @param  yieldRecipientManager The address of the yield recipient manager.
    /// @return proxy                 The address of the deployed proxy.
    /// @return proxyAdmin            The address of the deployed ProxyAdmin.
    /// @return implementation        The address of the deployed implementation.
    function deployMultiMint(
        string calldata name,
        string calldata symbol,
        address yieldRecipient,
        address admin,
        address assetCapManager,
        address freezeManager,
        address pauser,
        address yieldRecipientManager
    ) external returns (address proxy, address proxyAdmin, address implementation);

    /* ============ Admin Functions ============ */

    /// @notice Sets whether an extension is active.
    /// @dev    MUST only be callable by an address with the `FACTORY_MANAGER_ROLE` role.
    /// @param  extension The address of the extension.
    /// @param  status    True if the extension should be active, false otherwise.
    function setExtensionStatus(address extension, bool status) external;

    /// @notice Sets the cached implementation address for a given extension type.
    /// @dev    MUST only be callable by an address with the `FACTORY_MANAGER_ROLE` role.
    ///         Only affects future deployments — existing proxies are unaffected.
    /// @param  extensionType  The type of extension.
    /// @param  implementation The new implementation address.
    function setImplementation(ExtensionType extensionType, address implementation) external;
}
