// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "../../lib/m-extensions/lib/forge-std/src/Test.sol";

import { IndexingMath } from "../../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";
import { UnsafeUpgrades } from "../../lib/m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { PYUSDXHarness } from "../harness/PYUSDXHarness.sol";
import { MinterGatewayMock } from "../mock/MinterGatewayMock.sol";

/// @title PYUSDX Base Unit Test
/// @notice Base test contract with common setup for PYUSDX tests
abstract contract PYUSDXBaseUnitTest is Test {
    address public pyusd = makeAddr("pyusd");

    MinterGatewayMock public minterGateway;

    PYUSDXHarness public pyusdx;

    // Test addresses
    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public freezeManager = makeAddr("freezeManager");
    address public forcedTransferManager = makeAddr("forcedTransferManager");
    address public earnerManager = makeAddr("earnerManager");
    address public rateManager = makeAddr("rateManager");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public david = makeAddr("david");
    address[] public accounts;

    uint128 public constant PRECISION = 1e12;
    uint16 public constant MAX_FEE_RATE = 10_000;

    function setUp() public virtual {
        accounts = [alice, bob, carol, david];

        // Deploy minter gateway mock first with dummy address (will be updated later)
        // TODO: figure out how to avoid this circular dependency
        minterGateway = new MinterGatewayMock(address(0));

        address implementation = address(new PYUSDXHarness(address(minterGateway), pyusd));

        pyusdx = PYUSDXHarness(
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                admin,
                abi.encodeWithSelector(
                    PYUSDX.initialize.selector,
                    "PayPal USD Yield",
                    "PYUSDX",
                    admin,
                    pauser,
                    freezeManager,
                    forcedTransferManager,
                    earnerManager,
                    rateManager
                )
            )
        );

        minterGateway.setPyusdx(address(pyusdx));
    }

    /* ============ Indexing Math Helpers ============ */

    /// @dev Returns the expected principal amount (rounded down) for a given present amount and index
    function _getExpectedPrincipal(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedDown(uint240(presentAmount), index);
    }

    /// @dev Returns the expected present amount (rounded down) for a given principal amount and index
    function _getExpectedPresentAmount(uint112 principalAmount, uint128 index) internal pure returns (uint256) {
        return uint256(IndexingMath.getPresentAmountRoundedDown(principalAmount, index));
    }

    /// @dev Returns the expected principal amount (rounded up) for a given present amount and index
    function _getExpectedPrincipalRoundedUp(uint256 presentAmount, uint128 index) internal pure returns (uint112) {
        return IndexingMath.getPrincipalAmountRoundedUp(uint240(presentAmount), index);
    }
}
