// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

// JSON fixtures use the quoting selected by Prettier to avoid escaped property names.
/* solhint-disable quotes */

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { ScriptBase } from "../../../script/ScriptBase.s.sol";
import { DeploymentRecordHarness } from "../../harness/DeploymentRecordHarness.sol";

/// @title  DeploymentRecordTests
/// @notice Covers `deployments/<chainid>.json` (INT-468): the YieldToOne and MultiMint beacon proxies
///         are first-class fields rather than extension entries, records written before those fields
///         existed still load, and updates preserve every core and extension entry already on record.
contract DeploymentRecordTests is Test {
    uint256 internal constant CHAIN_ID = 8453;

    address internal constant PYUSDX = address(0xAAA1);
    address internal constant ISSUER_GATEWAY = address(0xAAA2);
    address internal constant SWAP_FACILITY = address(0xAAA3);
    address internal constant EXTENSION_FACTORY = address(0xAAA4);
    address internal constant PORTAL = address(0xAAA5);
    address internal constant LZ_BRIDGE_ADAPTER = address(0xAAA6);
    address internal constant OFT_WRAPPER = address(0xAAA7);
    address internal constant YIELD_TO_ONE_BEACON = address(0xBEAC01);
    address internal constant MULTI_MINT_BEACON = address(0xBEAC02);

    /// @dev The beacon addresses backfilled into every checked-in record, verified against the
    ///      DeployAll broadcast receipts and each chain's live `ExtensionFactory`.
    address internal constant DEPLOYED_YIELD_TO_ONE_BEACON = 0x4c9989F704b52B230C7C38618CBef171986969e7;
    address internal constant DEPLOYED_MULTI_MINT_BEACON = 0x00B1c02CeBa9dbdccd4fddf822ea6DEAf6e412b3;

    /// @dev A legacy record, as written before the beacon fields existed.
    string internal constant LEGACY_RECORD =
        '{"extensionAddresses":["0x00000000000000000000000000000000000000C1"],'
        '"extensionFactory":"0x000000000000000000000000000000000000AAA4",'
        '"extensionNames":["capUSD0"],'
        '"issuerGateway":"0x000000000000000000000000000000000000AAA2",'
        '"layerZeroBridgeAdapter":"0x000000000000000000000000000000000000AAA6",'
        '"portal":"0x000000000000000000000000000000000000AAA5",'
        '"pyusdx":"0x000000000000000000000000000000000000AAA1",'
        '"pyusdxPortalOFTWrapper":"0x000000000000000000000000000000000000AAA7",'
        '"swapFacility":"0x000000000000000000000000000000000000AAA3"}';

    function test_readDeployment_rejectsMismatchedExtensionArrays() external {
        DeploymentRecordHarness harness = _newHarness("mismatchedArrays");
        vm.createDir(harness.outputDir(), true);
        vm.writeFile(harness.outputPath(CHAIN_ID), '{"extensionNames":["orphan"]}');
        vm.expectRevert(bytes("deployment record: extension names/addresses length mismatch"));
        harness.readDeployment(CHAIN_ID);
    }

    /* ============ Helpers ============ */

    /// @dev Each test gets its own scratch directory: forge may run the tests in this contract
    ///      concurrently, and they would otherwise race on one record file. `out/` is gitignored and
    ///      permitted for writing by `fs_permissions` in foundry.toml, so the checked-in
    ///      `deployments/` records are never touched.
    function _newHarness(string memory testName) internal returns (DeploymentRecordHarness harness) {
        harness = new DeploymentRecordHarness(
            string.concat(vm.projectRoot(), "/out/test-deployments/DeploymentRecord/", testName)
        );

        string memory path = harness.outputPath(CHAIN_ID);
        if (vm.isFile(path)) vm.removeFile(path);
    }

    function _seedLegacyRecord(DeploymentRecordHarness harness) internal {
        vm.createDir(harness.outputDir(), true);
        vm.writeFile(harness.outputPath(CHAIN_ID), LEGACY_RECORD);
    }

    function _writeFullRecord(DeploymentRecordHarness harness) internal {
        harness.writeDeployment(CHAIN_ID, "pyusdx", PYUSDX);
        harness.writeDeployment(CHAIN_ID, "issuerGateway", ISSUER_GATEWAY);
        harness.writeDeployment(CHAIN_ID, "swapFacility", SWAP_FACILITY);
        harness.writeDeployment(CHAIN_ID, "extensionFactory", EXTENSION_FACTORY);
        harness.writeDeployment(CHAIN_ID, "portal", PORTAL);
        harness.writeDeployment(CHAIN_ID, "layerZeroBridgeAdapter", LZ_BRIDGE_ADAPTER);
        harness.writeDeployment(CHAIN_ID, "yieldToOneBeacon", YIELD_TO_ONE_BEACON);
        harness.writeDeployment(CHAIN_ID, "multiMintBeacon", MULTI_MINT_BEACON);
    }

    /* ============ Core Key Classification ============ */

    /// @notice The beacons are shared infrastructure, not extension proxies, so they must be
    ///         top-level keys and must never be appended to `extensionNames`.
    function test_isCoreDeploymentKey_treatsBeaconsAsCore() external {
        DeploymentRecordHarness harness = _newHarness("isCoreDeploymentKey_beacons");

        assertTrue(harness.isCoreDeploymentKey("yieldToOneBeacon"));
        assertTrue(harness.isCoreDeploymentKey("multiMintBeacon"));
    }

    function test_isCoreDeploymentKey_treatsExtensionHandlesAsExtensions() external {
        DeploymentRecordHarness harness = _newHarness("isCoreDeploymentKey_extensions");

        assertFalse(harness.isCoreDeploymentKey("capUSD0"));
        assertFalse(harness.isCoreDeploymentKey("Concrete USD"));
        // Near-misses of core keys are extension handles, not core fields.
        assertFalse(harness.isCoreDeploymentKey("yieldToOne"));
        assertFalse(harness.isCoreDeploymentKey("multiMint"));
    }

    /* ============ Write / Read Round Trip ============ */

    function test_writeDeployment_recordsBothBeacons() external {
        DeploymentRecordHarness harness = _newHarness("recordsBothBeacons");

        _writeFullRecord(harness);

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.yieldToOneBeacon, YIELD_TO_ONE_BEACON);
        assertEq(record.multiMintBeacon, MULTI_MINT_BEACON);
        assertTrue(record.yieldToOneBeacon != record.multiMintBeacon);
    }

    function test_writeDeployment_beaconsAreNotExtensionEntries() external {
        DeploymentRecordHarness harness = _newHarness("beaconsAreNotExtensionEntries");

        _writeFullRecord(harness);

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.extensionNames.length, 0);
        assertEq(record.extensionAddresses.length, 0);

        string memory json = vm.readFile(harness.outputPath(CHAIN_ID));
        assertTrue(vm.keyExistsJson(json, ".yieldToOneBeacon"));
        assertTrue(vm.keyExistsJson(json, ".multiMintBeacon"));
    }

    function test_writeDeployment_preservesCoreAndExtensionEntries() external {
        DeploymentRecordHarness harness = _newHarness("preservesCoreAndExtensionEntries");

        _writeFullRecord(harness);
        harness.writeDeployment(CHAIN_ID, "capUSD0", address(0xC1));
        harness.writeDeployment(CHAIN_ID, "Concrete USD", address(0xC2));

        // A later beacon update (e.g. a beacon redeploy) must not disturb anything else on record.
        harness.writeDeployment(CHAIN_ID, "multiMintBeacon", address(0xBEAC99));

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdx, PYUSDX);
        assertEq(record.issuerGateway, ISSUER_GATEWAY);
        assertEq(record.swapFacility, SWAP_FACILITY);
        assertEq(record.extensionFactory, EXTENSION_FACTORY);
        assertEq(record.portal, PORTAL);
        assertEq(record.layerZeroBridgeAdapter, LZ_BRIDGE_ADAPTER);
        assertEq(record.yieldToOneBeacon, YIELD_TO_ONE_BEACON);
        assertEq(record.multiMintBeacon, address(0xBEAC99));

        assertEq(record.extensionNames.length, 2);
        assertEq(record.extensionNames[0], "capUSD0");
        assertEq(record.extensionAddresses[0], address(0xC1));
        assertEq(record.extensionNames[1], "Concrete USD");
        assertEq(record.extensionAddresses[1], address(0xC2));
    }

    /// @notice An extension write must not disturb the beacons, and vice versa.
    function test_writeDeployment_extensionWritePreservesBeacons() external {
        DeploymentRecordHarness harness = _newHarness("extensionWritePreservesBeacons");

        _writeFullRecord(harness);
        harness.writeDeployment(CHAIN_ID, "capUSD0", address(0xC1));

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.yieldToOneBeacon, YIELD_TO_ONE_BEACON);
        assertEq(record.multiMintBeacon, MULTI_MINT_BEACON);
        assertEq(record.extensionNames.length, 1);
        assertEq(record.extensionNames[0], "capUSD0");
    }

    function test_writeDeployment_preservesPortalOFTWrapper() external {
        DeploymentRecordHarness harness = _newHarness("preservesPortalOFTWrapper");

        _writeFullRecord(harness);
        harness.writeDeployment(CHAIN_ID, "pyusdxPortalOFTWrapper", OFT_WRAPPER);
        harness.writeDeployment(CHAIN_ID, "yieldToOneBeacon", address(0xBEAC98));

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdxPortalOFTWrapper, OFT_WRAPPER);
        assertEq(record.yieldToOneBeacon, address(0xBEAC98));
        assertEq(record.multiMintBeacon, MULTI_MINT_BEACON);
    }

    /* ============ Legacy Compatibility ============ */

    /// @notice Regression: a record written before the beacon fields existed must still load. The
    ///         reader must not `abi.decode` the whole object, which fails on a missing key.
    function test_readDeployment_legacyRecordWithoutBeaconFields() external {
        DeploymentRecordHarness harness = _newHarness("legacyRecordWithoutBeaconFields");

        _seedLegacyRecord(harness);

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdx, PYUSDX);
        assertEq(record.issuerGateway, ISSUER_GATEWAY);
        assertEq(record.swapFacility, SWAP_FACILITY);
        assertEq(record.extensionFactory, EXTENSION_FACTORY);
        assertEq(record.portal, PORTAL);
        assertEq(record.layerZeroBridgeAdapter, LZ_BRIDGE_ADAPTER);
        assertEq(record.pyusdxPortalOFTWrapper, OFT_WRAPPER);
        assertEq(record.extensionNames.length, 1);
        assertEq(record.extensionNames[0], "capUSD0");
        assertEq(record.extensionAddresses[0], address(0xC1));

        // Absent fields read as the zero address rather than reverting.
        assertEq(record.yieldToOneBeacon, address(0));
        assertEq(record.multiMintBeacon, address(0));
    }

    /// @notice Upgrading a legacy record in place must add the beacons without losing anything.
    function test_writeDeployment_backfillsLegacyRecordInPlace() external {
        DeploymentRecordHarness harness = _newHarness("backfillsLegacyRecordInPlace");

        _seedLegacyRecord(harness);

        harness.writeDeployment(CHAIN_ID, "yieldToOneBeacon", YIELD_TO_ONE_BEACON);
        harness.writeDeployment(CHAIN_ID, "multiMintBeacon", MULTI_MINT_BEACON);

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.yieldToOneBeacon, YIELD_TO_ONE_BEACON);
        assertEq(record.multiMintBeacon, MULTI_MINT_BEACON);
        assertEq(record.pyusdx, PYUSDX);
        assertEq(record.pyusdxPortalOFTWrapper, OFT_WRAPPER);
        assertEq(record.extensionNames.length, 1);
        assertEq(record.extensionNames[0], "capUSD0");
        assertEq(record.extensionAddresses[0], address(0xC1));
    }

    /// @notice A record for a chain that has never been deployed reads as an empty struct.
    function test_readDeployment_missingFileReadsEmpty() external {
        DeploymentRecordHarness harness = _newHarness("missingFileReadsEmpty");

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdx, address(0));
        assertEq(record.yieldToOneBeacon, address(0));
        assertEq(record.multiMintBeacon, address(0));
        assertEq(record.extensionNames.length, 0);
        assertEq(record.extensionAddresses.length, 0);
    }

    /* ============ Checked-in Record Tests ============ */

    /// @notice Every checked-in record carries the backfilled beacon addresses. The values were taken
    ///         from the DeployAll broadcast receipts (CREATE3 salt `PYUSDXYieldToOneBeacon` /
    ///         `PYUSDXMultiMintBeacon`) and confirmed against each chain's live `ExtensionFactory`.
    function test_checkedInRecords_carryBackfilledBeacons() external view {
        uint256[8] memory chainIds = [uint256(1), 143, 8453, 42161, 10143, 84532, 421614, 11155111];

        for (uint256 i; i < chainIds.length; ++i) {
            string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(chainIds[i]), ".json");

            assertTrue(vm.isFile(path), string.concat("missing record for chain ", vm.toString(chainIds[i])));

            string memory json = vm.readFile(path);

            assertEq(
                vm.parseJsonAddress(json, ".yieldToOneBeacon"),
                DEPLOYED_YIELD_TO_ONE_BEACON,
                string.concat("yieldToOneBeacon mismatch on chain ", vm.toString(chainIds[i]))
            );
            assertEq(
                vm.parseJsonAddress(json, ".multiMintBeacon"),
                DEPLOYED_MULTI_MINT_BEACON,
                string.concat("multiMintBeacon mismatch on chain ", vm.toString(chainIds[i]))
            );

            // The beacons are core fields, so they must not also appear as extension handles.
            string[] memory names = vm.parseJsonStringArray(json, ".extensionNames");
            for (uint256 j; j < names.length; ++j) {
                assertTrue(keccak256(bytes(names[j])) != keccak256("yieldToOneBeacon"));
                assertTrue(keccak256(bytes(names[j])) != keccak256("multiMintBeacon"));
            }
        }
    }
}
