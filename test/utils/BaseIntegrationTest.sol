// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IERC20Extended } from "../../lib/m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { BaseTest } from "./BaseTest.sol";

/// @title BaseIntegrationTest
/// @notice Base test contract with integration test utilities (permit signatures, etc.)
abstract contract BaseIntegrationTest is BaseTest {
    /* ============ Permit Helpers ============ */

    /// @dev Signs an EIP-2612 permit for any ERC20Extended token
    function _getPermitSignature(
        address token,
        address spender,
        address owner,
        uint256 ownerKey,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(IERC20Extended(token).PERMIT_TYPEHASH(), owner, spender, amount, nonce, deadline)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Extended(token).DOMAIN_SEPARATOR(), structHash));

        return vm.sign(ownerKey, digest);
    }

    /// @dev Returns permit signature as bytes (r, s, v packed)
    function _getPermitSignatureBytes(
        address token,
        address spender,
        address owner,
        uint256 ownerKey,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(token, spender, owner, ownerKey, amount, nonce, deadline);
        return abi.encodePacked(r, s, v);
    }
}
