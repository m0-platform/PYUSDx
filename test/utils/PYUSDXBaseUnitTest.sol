// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IndexingMath } from "../../lib/evm-m-extensions/lib/common/src/libs/IndexingMath.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/IPYUSDX.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { IssuerGatewayMock } from "../mock/IssuerGatewayMock.sol";
import { BaseTest } from "./BaseTest.sol";

/// @title PYUSDX Base Unit Test
/// @notice Base test contract with common setup for PYUSDX tests
abstract contract PYUSDXBaseUnitTest is BaseTest {
    IssuerGatewayMock public issuerGateway;
    PYUSDXHarness public pyusdx;

    function setUp() public virtual override {
        super.setUp();

        // Deploy issuer gateway mock first with dummy address (will be updated later)
        // TODO: figure out how to avoid this circular dependency
        issuerGateway = new IssuerGatewayMock(address(0));

        address implementation = address(new PYUSDXHarness());

        pyusdx = PYUSDXHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeCall(
                    PYUSDX.initialize,
                    (
                        IPYUSDX.InitializeParams({
                            name: "PayPal USD Yield",
                            symbol: "PYUSDX",
                            admin: admin,
                            pauser: pauser,
                            freezeManager: freezeManager,
                            forcedTransferManager: forcedTransferManager,
                            earnerManager: earnerManager,
                            rateLimitManager: rateLimitManager,
                            issuer: address(issuerGateway)
                        })
                    )
                )
            )
        );

        issuerGateway.setPyusdx(address(pyusdx));
    }

    /* ============ Indexing Math Helpers ============ */

    /// @dev Returns the expected principal amount (rounded down) for a given present amount and index
    function _getExpectedPrincipal(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedDown(uint240(presentAmount), index);
    }

    /// @dev Returns the expected present amount (rounded down) for a given principal amount and index
    function _getExpectedPresentAmount(uint112 principalAmount, uint128 index) internal pure returns (uint240) {
        return IndexingMath.getPresentAmountRoundedDown(principalAmount, index);
    }

    /// @dev Returns the expected principal amount (rounded up) for a given present amount and index
    function _getExpectedPrincipalRoundedUp(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedUp(uint240(presentAmount), index);
    }

    /* ============ Additional Helper Functions ============ */

    /// @notice Calculate max safe mint amount that won't overflow totalSupply (uint240)
    /// @return maxAmount Maximum amount that can be minted
    function _maxSafeAmount() internal view returns (uint256) {
        return type(uint240).max - pyusdx.totalSupply();
    }

    /// @notice Check if burning amount is safe
    /// @param account The account to burn from
    /// @param amount The amount to burn
    /// @return True if account has sufficient balance
    function _canSafelyBurn(address account, uint256 amount) internal view returns (bool) {
        return pyusdx.balanceOf(account) >= amount;
    }

    /// @notice Calculate expected principal with round down (as used in mint)
    /// @param presentAmount The present amount
    /// @param index The current index
    /// @return Principal amount rounded down
    function _expectedPrincipalRoundDown(uint240 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedDown(presentAmount, index);
    }

    /// @notice Calculate expected principal with round up (as used in burn/transfer)
    /// @param presentAmount The present amount
    /// @param index The current index
    /// @return Principal amount rounded up
    function _expectedPrincipalRoundUp(uint240 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedUp(presentAmount, index);
    }

    /// @notice Calculate expected principal with round up, returning uint256 to avoid revert
    /// @param presentAmount The present amount
    /// @param index The current index
    /// @return Principal amount rounded up (as uint256, may exceed uint112 max)
    function _expectedPrincipalRoundUpSafe(uint256 presentAmount, uint128 index) internal pure returns (uint256) {
        if (index == 0) return 0;

        unchecked {
            return ((presentAmount * 1e12) + index - 1) / index;
        }
    }

    /// @notice Check if account has principal depletion (balance with zero principal)
    /// @param account The account to check
    /// @return True if account has non-zero balance but zero principal
    function _hasPrincipalDepletion(address account) internal view returns (bool) {
        return pyusdx.balanceOf(account) > 0 && pyusdx.earningPrincipalOf(account) == 0;
    }
}
