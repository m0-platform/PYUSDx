// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPYUSDX } from "src/interfaces/IPYUSDX.sol";

/**
 * @title MinterGatewayMock
 * @notice Mock implementation of the Minter Gateway for testing
 * @dev Simulates the Minter Gateway that will mint and burn PYUSDX tokens
 */
contract MinterGatewayMock {
    /// @notice The PYUSDX token contract
    IPYUSDX public immutable pyusdx;

    /// @notice Error for unauthorized calls
    error Unauthorized();

    /// @notice The address authorized to call mint/burn (e.g., a bridge or vault)
    address public authorizedCaller;

    /**
     * @notice Constructs the MinterGatewayMock
     * @param _pyusdx Address of the PYUSDX token contract
     */
    constructor(address _pyusdx) {
        pyusdx = IPYUSDX(_pyusdx);
    }

    /**
     * @notice Sets the authorized caller
     * @param _caller Address to authorize (use address(0) to disable)
     */
    function setAuthorizedCaller(address _caller) external {
        authorizedCaller = _caller;
    }

    /**
     * @notice Mints PYUSDX to an account
     * @dev Only callable by authorized caller
     * @param account Recipient of minted tokens
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) external {
        if (msg.sender != authorizedCaller) revert Unauthorized();
        pyusdx.mint(account, amount);
    }

    /**
     * @notice Burns PYUSDX from an account
     * @dev Only callable by authorized caller
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burn(address account, uint256 amount) external {
        if (msg.sender != authorizedCaller) revert Unauthorized();
        pyusdx.burn(account, amount);
    }
}
