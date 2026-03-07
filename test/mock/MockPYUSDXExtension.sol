// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import { ERC20 } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20.sol";
import { IPYUSDXExtension } from "../../src/interfaces/IPYUSDXExtension.sol";

/**
 * @title  Mock PYUSDX Extension
 * @notice Mock implementation of IPYUSDXExtension for testing
 */
contract MockPYUSDXExtension is ERC20 {
    /* ============ Immutable Storage ============ */

    /// @notice The address of the PYUSDX token contract.
    address public immutable pyusdx;

    /// @notice The address of the swap facility contract.
    address public immutable swapFacility;

    /* ============ Storage ============ */

    /// @notice Whether the contract is paused.
    bool private _paused;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the mock extension token.
     * @param pyusdx_       The address of the PYUSDX token contract.
     * @param swapFacility_ The address of the swap facility contract.
     */
    constructor(address pyusdx_, address swapFacility_) ERC20("Mock PYUSDX Extension", "mockEXT") {
        if (pyusdx_ == address(0)) revert IPYUSDXExtension.ZeroPYUSDX();
        if (swapFacility_ == address(0)) revert IPYUSDXExtension.ZeroSwapFacility();
        pyusdx = pyusdx_;
        swapFacility = swapFacility_;
    }

    /* ============ External Functions ============ */

    /**
     * @notice Returns the number of decimals used (6 for PYUSD compatibility).
     * @return The token decimals.
     */
    function decimals() public pure override(ERC20) returns (uint8) {
        return 6;
    }

    /**
     * @notice Wraps PYUSDX from the caller into extension tokens for the recipient.
     * @dev    Only callable by the swap facility.
     * @param  recipient The account receiving the minted extension tokens.
     * @param  amount    The amount of extension tokens to mint.
     */
    function wrap(address recipient, uint256 amount) external {
        if (msg.sender != swapFacility) revert IPYUSDXExtension.NotSwapFacility();
        // Transfer PYUSDX from swapFacility to this contract
        IERC20(pyusdx).transferFrom(swapFacility, address(this), amount);
        // Mint extension tokens to recipient
        _mint(recipient, amount);
    }

    /**
     * @notice Unwraps extension tokens from the caller back into PYUSDX.
     * @dev    Only callable by the swap facility.
     * @param  amount The amount of extension tokens to burn.
     */
    function unwrap(uint256 amount) external {
        if (msg.sender != swapFacility) revert IPYUSDXExtension.NotSwapFacility();
        // Burn extension tokens from caller
        _burn(msg.sender, amount);
        // Transfer PYUSDX to swapFacility
        IERC20(pyusdx).transfer(swapFacility, amount);
    }

    /**
     * @notice EIP-2612 permit with v, r, s signature components.
     * @dev    Mock implementation - no-op for testing.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Mock implementation - no-op
        // TODO: remove
    }

    /**
     * @notice EIP-2612 permit with bytes signature.
     * @dev    Mock implementation - no-op for testing.
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) external {
        // Mock implementation - no-op
        // TODO: remove
    }

    /**
     * @notice Returns the EIP712 typehash for permit (mock value).
     * @return The PERMIT_TYPEHASH.
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32) {
        // TODO: remove
        return keccak256("Permit(address owner,address spender,uint256 value,uint256 deadline)");
    }

    /**
     * @notice Mints extension tokens to the specified address (for test setup).
     * @param to     The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Pauses the contract.
     */
    function pause() external {
        _paused = true;
    }

    /**
     * @notice Returns whether the contract is paused.
     * @return True if paused, false otherwise.
     */
    function paused() external view returns (bool) {
        return _paused;
    }
}
