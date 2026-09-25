// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

// JSON fixtures use the quoting selected by Prettier to avoid escaped property names.
/* solhint-disable quotes */

import { Test } from "../../../lib/forge-std/src/Test.sol";
import { VmSafe } from "../../../lib/forge-std/src/Vm.sol";

import { ScriptBase } from "../../../script/ScriptBase.s.sol";
import { DeploymentRecordHarness } from "../../harness/DeploymentRecordHarness.sol";

/// @title  DeploymentRecordTests
/// @notice Covers `deployments/<chainid>.json` (INT-468): the YieldToOne and MultiMint beacon proxies
///         are first-class fields rather than extension entries, an existing record must carry every
///         emitted key, and updates preserve every core and extension entry already on record.
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

    /// @dev Every key `_writeDeployment` emits, in the order `_recordJson` renders them.
    uint256 internal constant RECORD_KEY_COUNT = 11;

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

    function _seedRecord(DeploymentRecordHarness harness, string memory json) internal {
        vm.createDir(harness.outputDir(), true);
        vm.writeFile(harness.outputPath(CHAIN_ID), json);
    }

    function _recordKeys() internal pure returns (string[RECORD_KEY_COUNT] memory) {
        return
            [
                "extensionAddresses",
                "extensionFactory",
                "extensionNames",
                "issuerGateway",
                "layerZeroBridgeAdapter",
                "multiMintBeacon",
                "portal",
                "pyusdx",
                "pyusdxPortalOFTWrapper",
                "swapFacility",
                "yieldToOneBeacon"
            ];
    }

    /// @dev A complete record carrying every emitted key, minus `omitted` (pass "" to keep all).
    function _recordJson(string memory omitted) internal pure returns (string memory json) {
        string[RECORD_KEY_COUNT] memory keys = _recordKeys();
        string[RECORD_KEY_COUNT] memory values = [
            '["0x00000000000000000000000000000000000000C1"]',
            '"0x000000000000000000000000000000000000AAA4"',
            '["capUSD0"]',
            '"0x000000000000000000000000000000000000AAA2"',
            '"0x000000000000000000000000000000000000AAA6"',
            '"0x0000000000000000000000000000000000BEAC02"',
            '"0x000000000000000000000000000000000000AAA5"',
            '"0x000000000000000000000000000000000000AAA1"',
            '"0x000000000000000000000000000000000000AAA7"',
            '"0x000000000000000000000000000000000000AAA3"',
            '"0x0000000000000000000000000000000000BEAC01"'
        ];

        string memory separator = "";
        json = "{";

        for (uint256 i; i < RECORD_KEY_COUNT; ++i) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(omitted))) continue;

            json = string.concat(json, separator, '"', keys[i], '":', values[i]);
            separator = ",";
        }

        json = string.concat(json, "}");
    }

    /// @dev The error Foundry raises when the strict reader parses a key the record does not carry.
    function _missingKeyError(string memory key) internal pure returns (bytes memory) {
        string memory cheatcode = "parseJsonAddress";

        if (keccak256(bytes(key)) == keccak256("extensionAddresses")) cheatcode = "parseJsonAddressArray";
        if (keccak256(bytes(key)) == keccak256("extensionNames")) cheatcode = "parseJsonStringArray";

        return bytes(string.concat("vm.", cheatcode, ': path ".', key, '" must return exactly one JSON value'));
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

    /// @notice A fresh incremental deployment writes one key at a time, so the first write must emit
    ///         every key, with zero for what is not deployed yet and both arrays empty.
    function test_writeDeployment_firstWriteEmitsEveryKey() external {
        DeploymentRecordHarness harness = _newHarness("firstWriteEmitsEveryKey");

        harness.writeDeployment(CHAIN_ID, "pyusdx", PYUSDX);

        string memory json = vm.readFile(harness.outputPath(CHAIN_ID));
        string[RECORD_KEY_COUNT] memory keys = _recordKeys();

        for (uint256 i; i < RECORD_KEY_COUNT; ++i) {
            assertTrue(vm.keyExistsJson(json, string.concat(".", keys[i])), keys[i]);
        }

        assertEq(vm.parseJsonAddress(json, ".pyusdxPortalOFTWrapper"), address(0));

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdx, PYUSDX);
        assertEq(record.issuerGateway, address(0));
        assertEq(record.pyusdxPortalOFTWrapper, address(0));
        assertEq(record.extensionNames.length, 0);
        assertEq(record.extensionAddresses.length, 0);
    }

    /* ============ Strict Record Reads ============ */

    function test_readDeployment_completeRecord() external {
        DeploymentRecordHarness harness = _newHarness("completeRecord");

        _seedRecord(harness, _recordJson(""));

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdx, PYUSDX);
        assertEq(record.issuerGateway, ISSUER_GATEWAY);
        assertEq(record.swapFacility, SWAP_FACILITY);
        assertEq(record.extensionFactory, EXTENSION_FACTORY);
        assertEq(record.portal, PORTAL);
        assertEq(record.layerZeroBridgeAdapter, LZ_BRIDGE_ADAPTER);
        assertEq(record.pyusdxPortalOFTWrapper, OFT_WRAPPER);
        assertEq(record.yieldToOneBeacon, YIELD_TO_ONE_BEACON);
        assertEq(record.multiMintBeacon, MULTI_MINT_BEACON);
        assertEq(record.extensionNames.length, 1);
        assertEq(record.extensionNames[0], "capUSD0");
        assertEq(record.extensionAddresses[0], address(0xC1));
    }

    /// @notice Regression: a key missing from an existing record must fail loudly rather than read as
    ///         address(0), which would send an update script to the env fallback or redeploy.
    function test_readDeployment_missingKey() external {
        DeploymentRecordHarness harness = _newHarness("missingKey");
        string[RECORD_KEY_COUNT] memory keys = _recordKeys();

        for (uint256 i; i < RECORD_KEY_COUNT; ++i) {
            _seedRecord(harness, _recordJson(keys[i]));

            vm.expectRevert(_missingKeyError(keys[i]));
            harness.readDeployment(CHAIN_ID);
        }
    }

    /// @notice A record written before the beacon fields existed is incomplete and no longer loads.
    function test_readDeployment_legacyRecordWithoutBeaconFields() external {
        DeploymentRecordHarness harness = _newHarness("legacyRecordWithoutBeaconFields");

        _seedRecord(harness, LEGACY_RECORD);

        vm.expectRevert(_missingKeyError("multiMintBeacon"));
        harness.readDeployment(CHAIN_ID);
    }

    /// @notice "Not deployed" is an explicit zero on record, not an absent key.
    function test_readDeployment_explicitZeroWrapper() external {
        DeploymentRecordHarness harness = _newHarness("explicitZeroWrapper");

        _seedRecord(
            harness,
            vm.replace(
                _recordJson(""),
                '"pyusdxPortalOFTWrapper":"0x000000000000000000000000000000000000AAA7"',
                '"pyusdxPortalOFTWrapper":"0x0000000000000000000000000000000000000000"'
            )
        );

        ScriptBase.Deployments memory record = harness.readDeployment(CHAIN_ID);

        assertEq(record.pyusdxPortalOFTWrapper, address(0));
        assertEq(record.pyusdx, PYUSDX);
    }

    function test_readDeployment_rejectsMismatchedExtensionArrays() external {
        DeploymentRecordHarness harness = _newHarness("mismatchedArrays");

        _seedRecord(harness, vm.replace(_recordJson(""), '["capUSD0"]', '["capUSD0","orphan"]'));

        vm.expectRevert(bytes("deployment record: extension names/addresses length mismatch"));
        harness.readDeployment(CHAIN_ID);
    }

    /// @notice A write reads the record first, so an incomplete record aborts the write and is left
    ///         exactly as it was rather than being rewritten with zeros for the missing keys.
    function test_writeDeployment_incompleteRecordIsNotRewritten() external {
        DeploymentRecordHarness harness = _newHarness("incompleteRecordIsNotRewritten");

        _seedRecord(harness, LEGACY_RECORD);

        vm.expectRevert(_missingKeyError("multiMintBeacon"));
        harness.writeDeployment(CHAIN_ID, "yieldToOneBeacon", YIELD_TO_ONE_BEACON);

        assertEq(vm.readFile(harness.outputPath(CHAIN_ID)), LEGACY_RECORD);
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

    /// @notice Every checked-in `deployments/<chainid>.json` loads through the strict reader, has a
    ///         matching protocol config, and carries the backfilled beacon addresses. The values were
    ///         taken from the DeployAll broadcast receipts (CREATE3 salt `PYUSDXYieldToOneBeacon` /
    ///         `PYUSDXMultiMintBeacon`) and confirmed against each chain's live `ExtensionFactory`.
    /// @dev    Records are discovered from the directory, so a new record cannot be left unchecked.
    function test_checkedInRecords_carryBackfilledBeacons() external {
        string memory dir = string.concat(vm.projectRoot(), "/deployments");
        DeploymentRecordHarness records = new DeploymentRecordHarness(dir);
        VmSafe.DirEntry[] memory entries = vm.readDir(dir);
        uint256 checked;

        for (uint256 i; i < entries.length; ++i) {
            assertEq(entries[i].errorMessage, "", entries[i].path);
            string[] memory segments = vm.split(entries[i].path, "/");
            string memory fileName = segments[segments.length - 1];
            string[] memory parts = vm.split(fileName, ".");

            if (entries[i].isDir || keccak256(bytes(parts[parts.length - 1])) != keccak256("json")) continue;

            assertEq(parts.length, 2, string.concat("record name must be <chainid>.json: ", fileName));

            uint256 chainId = vm.parseUint(parts[0]);

            // Round-tripping rejects hex, leading zeros and zero, so the name is the canonical chain ID.
            assertEq(vm.toString(chainId), parts[0], string.concat("record name is not a chain ID: ", fileName));
            assertGt(chainId, 0, string.concat("record name is not a chain ID: ", fileName));
            assertTrue(
                vm.isFile(string.concat(vm.projectRoot(), "/deploymentConfigs/", parts[0], "/protocol.json")),
                string.concat("record has no protocol config: ", fileName)
            );

            ScriptBase.Deployments memory record = records.readDeployment(chainId);

            assertEq(
                record.yieldToOneBeacon,
                DEPLOYED_YIELD_TO_ONE_BEACON,
                string.concat("yieldToOneBeacon mismatch on chain ", parts[0])
            );
            assertEq(
                record.multiMintBeacon,
                DEPLOYED_MULTI_MINT_BEACON,
                string.concat("multiMintBeacon mismatch on chain ", parts[0])
            );

            // The beacons are core fields, so they must not also appear as extension handles.
            for (uint256 j; j < record.extensionNames.length; ++j) {
                assertTrue(keccak256(bytes(record.extensionNames[j])) != keccak256("yieldToOneBeacon"));
                assertTrue(keccak256(bytes(record.extensionNames[j])) != keccak256("multiMintBeacon"));
            }

            ++checked;
        }

        assertGt(checked, 0, "no deployment records discovered");
    }
}
