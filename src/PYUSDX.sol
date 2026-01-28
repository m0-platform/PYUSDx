// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPYUSDX} from "./interfaces/IPYUSDX.sol";

/**
 * @title PYUSDX
 * @notice Upgradeable, non-rebasing ERC20 token with claimable yield and compliance features
 * @dev Uses ERC-7201 namespaced storage pattern to prevent collisions across inherited contracts
 * @author M0 Labs
 */
abstract contract PYUSDXLayout is IPYUSDX {
    /* ============ Structs ============ */

    /**
     * @notice Account state storage
     * @dev Packed to exactly 2 slots (64 bytes) for efficiency
     */
    struct Account {
        bool isEarning;           // 1 byte  - Whether account is actively earning yield
        uint240 balance;          // 30 bytes - Token balance (excluding accrued yield)
        uint112 earningPrincipal; // 14 bytes - Principal amount for yield calculations
        bool hasClaimRecipient;   // 1 byte  - Whether custom claim recipient is set
        bool hasEarnerDetails;    // 1 byte  - Whether earner details are set
        // 16 bytes padding to align to slot boundary
    }

    /**
     * @notice Main storage struct for PYUSDX
     * @dev Stored at ERC-7201 namespaced storage slot
     */
    struct PYUSDXStorageStruct {
        mapping(address => Account) accounts;     // Account states
        mapping(address => address) claimRecipients; // Custom claim recipients
        uint112 totalEarningPrincipal;             // Sum of all earning principals
        uint240 totalEarningSupply;                // Total supply of earning tokens
        uint240 totalNonEarningSupply;             // Total supply of non-earning tokens
    }

    /* ============ Storage Layout ============ */

    /// @dev ERC-7201 namespaced storage slot: keccak256(abi.encode(uint256(keccak256("M0.storage.PYUSDX")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PYUSDX_STORAGE_LOCATION =
        0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;

    /**
     * @notice Get the storage location for PYUSDX state
     * @return $ Storage pointer to PYUSDXStorageStruct
     */
    function _getPYUSDXStorageLocation() internal pure returns (PYUSDXStorageStruct storage $) {
        assembly {
            $.slot := _PYUSDX_STORAGE_LOCATION
        }
    }
}
