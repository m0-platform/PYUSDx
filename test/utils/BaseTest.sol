// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { Test } from "../../lib/evm-m-extensions/lib/forge-std/src/Test.sol";

/// @title BaseTest
/// @notice Base test contract with common test infrastructure
abstract contract BaseTest is Test {
    // Role addresses
    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public freezeManager = makeAddr("freezeManager");
    address public forcedTransferManager = makeAddr("forcedTransferManager");
    address public earnerManager = makeAddr("earnerManager");
    address public rateLimitManager = makeAddr("rateLimitManager");
    address public rateManager = makeAddr("rateManager");
    address public yieldRecipient = makeAddr("yieldRecipient");
    address public yieldRecipientManager = makeAddr("yieldRecipientManager");
    address public operator = makeAddr("operator");
    address public executor = makeAddr("executor");
    address public assetCapManager = makeAddr("assetCapManager");
    address public factoryManager = makeAddr("factoryManager");
    address public beaconManager = makeAddr("beaconManager");
    address public versionManager = makeAddr("versionManager");

    // Generic test addresses
    address public recipient = makeAddr("recipient");
    address public caller = makeAddr("caller");
    address public other = makeAddr("other");

    // Test user addresses (with private keys for permit testing)
    address public alice;
    uint256 internal aliceKey;

    address public bob;
    uint256 internal bobKey;

    address public carol = makeAddr("carol");
    address public david = makeAddr("david");
    address[] public accounts;

    // Constants
    uint128 public constant PRECISION = 1e12;
    uint16 public constant MAX_RATE = 10_000;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant BEACON_MANAGER_ROLE = keccak256("BEACON_MANAGER_ROLE");

    function setUp() public virtual {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        accounts = [alice, bob, carol, david];
    }
}
