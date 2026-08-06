// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { IERC20 } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20.sol";

import { Config } from "../../script/Config.sol";
import { DeployMultiMint } from "../../script/deploy/DeployMultiMint.s.sol";

import { IExtensionFactory } from "../../src/platform/interfaces/IExtensionFactory.sol";
import { MultiMint } from "../../src/platform/projects/MultiMint.sol";

import { IntegrationForkTest } from "../utils/IntegrationForkTest.sol";

/// @notice Exposes DeployMultiMint internals externally to avoid forge-std diamond inheritance in tests.
contract MultiMintScriptDeployer is DeployMultiMint {
    function deployMultiMintWith(
        address factory_,
        string memory extensionName_,
        MultiMintConfig memory config_
    ) external returns (address proxy, address implementation) {
        _validateMultiMintConfig(config_);
        return _deployMultiMint(address(this), factory_, extensionName_, config_);
    }

    function verifyMultiMintDeployment(address factory_, address proxy_, MultiMintConfig memory config_) external view {
        _verifyMultiMintDeployment(address(this), factory_, proxy_, config_);
    }

    function validateMultiMintConfig(MultiMintConfig memory config_) external pure {
        _validateMultiMintConfig(config_);
    }

    function parseMultiMintConfig(
        string memory json_,
        string memory extensionName_
    ) external view returns (MultiMintConfig memory) {
        return _parseMultiMintConfig(json_, extensionName_);
    }
}

/// @title DeployMultiMintIntegrationTests
/// @notice Validates the MultiMint deploy script produces an immediately usable extension.
contract DeployMultiMintIntegrationTests is IntegrationForkTest {
    MultiMintScriptDeployer public scriptDeployer;
    MultiMint public multiMint;

    uint256 public constant USDC_CAP = 100_000_000e6;
    uint256 public constant PYUSD_CAP = 50_000_000e6;

    address public user = makeAddr("user");
    address public solver = makeAddr("solver");

    function setUp() public override {
        super.setUp();

        scriptDeployer = new MultiMintScriptDeployer();

        (address proxy, ) = scriptDeployer.deployMultiMintWith(
            address(factory),
            "deploy-script-multimint",
            _defaultConfig()
        );

        multiMint = MultiMint(proxy);
    }

    /* ============ Helpers ============ */

    function _defaultConfig() internal view returns (Config.MultiMintConfig memory) {
        address[] memory assets_ = new address[](2);
        assets_[0] = address(USDC);
        assets_[1] = address(PYUSD);

        uint256[] memory assetCaps_ = new uint256[](2);
        assetCaps_[0] = USDC_CAP;
        assetCaps_[1] = PYUSD_CAP;

        address[] memory whitelist_ = new address[](1);
        whitelist_[0] = solver;

        return
            Config.MultiMintConfig({
                name: "MultiMint Deploy Test",
                symbol: "MMDT",
                yieldRecipient: yieldRecipient,
                admin: admin,
                assetCapManager: assetCapManager,
                freezeManager: freezeManager,
                pauser: pauser,
                yieldRecipientManager: yieldRecipientManager,
                versionManager: versionManager,
                assets: assets_,
                assetCaps: assetCaps_,
                replaceAssetWhitelist: whitelist_
            });
    }

    /* ============ Registration Tests ============ */

    function test_deployMultiMint_registersOnSwapFacility() public view {
        assertTrue(swapFacility.isApprovedExtension(address(multiMint)));
        assertEq(
            uint8(factory.getExtensionType(address(multiMint))),
            uint8(IExtensionFactory.ExtensionType.MULTI_MINT)
        );
    }

    /* ============ Asset Cap Tests ============ */

    function test_deployMultiMint_assetCapsSetAtDeploy() public view {
        assertTrue(multiMint.isAllowedAsset(address(USDC)));
        assertTrue(multiMint.isAllowedAsset(address(PYUSD)));
        assertEq(multiMint.assetCap(address(USDC)), USDC_CAP);
        assertEq(multiMint.assetCap(address(PYUSD)), PYUSD_CAP);
        assertEq(multiMint.assetDecimals(address(USDC)), 6);
        assertEq(multiMint.assetDecimals(address(PYUSD)), 6);
    }

    /// @notice Regression: collateral must be wrappable immediately after deployment, without
    ///         waiting on the external asset cap manager.
    function test_deployMultiMint_wrapWorksImmediately() public {
        uint256 amount = 1_000e6;

        _dealUSDC(user, amount);

        vm.prank(user);
        IERC20(address(USDC)).approve(address(swapFacility), amount);

        vm.prank(user);
        swapFacility.swap(address(USDC), address(multiMint), amount, user);

        assertEq(multiMint.balanceOf(user), amount);
        assertEq(multiMint.assetBalanceOf(address(USDC)), amount);
    }

    /* ============ Role Tests ============ */

    function test_deployMultiMint_rolesHandedOff() public view {
        assertTrue(multiMint.hasRole(multiMint.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(multiMint.hasRole(multiMint.ASSET_CAP_MANAGER_ROLE(), assetCapManager));
        assertTrue(multiMint.hasRole(multiMint.FREEZE_MANAGER_ROLE(), freezeManager));
        assertTrue(multiMint.hasRole(multiMint.PAUSER_ROLE(), pauser));
        assertTrue(multiMint.hasRole(multiMint.YIELD_RECIPIENT_MANAGER_ROLE(), yieldRecipientManager));
        assertTrue(multiMint.hasRole(multiMint.VERSION_MANAGER_ROLE(), versionManager));
        assertEq(multiMint.yieldRecipient(), yieldRecipient);

        // Deployer's transient roles must be renounced after deployment
        assertFalse(multiMint.hasRole(multiMint.DEFAULT_ADMIN_ROLE(), address(scriptDeployer)));
        assertFalse(multiMint.hasRole(multiMint.ASSET_CAP_MANAGER_ROLE(), address(scriptDeployer)));
    }

    /// @notice Regression: when the deployer is also the configured admin and asset cap manager,
    ///         the transient-role handoff must not strip those roles.
    function test_deployMultiMint_deployerIsTargetHolder_retainsRoles() public {
        MultiMintScriptDeployer selfDeployer = new MultiMintScriptDeployer();
        address self = address(selfDeployer);

        Config.MultiMintConfig memory config_ = _defaultConfig();
        config_.admin = self;
        config_.assetCapManager = self;

        (address proxy, ) = selfDeployer.deployMultiMintWith(address(factory), "self-admin-multimint", config_);
        MultiMint deployed = MultiMint(proxy);

        assertTrue(deployed.hasRole(deployed.DEFAULT_ADMIN_ROLE(), self));
        assertTrue(deployed.hasRole(deployed.ASSET_CAP_MANAGER_ROLE(), self));

        selfDeployer.verifyMultiMintDeployment(address(factory), proxy, config_);
    }

    /* ============ Whitelist Tests ============ */

    function test_deployMultiMint_replaceAssetWhitelistSeeded() public view {
        assertTrue(multiMint.isReplaceAssetWhitelistEnabled());

        address[] memory whitelist = multiMint.getReplaceAssetWhitelist();
        assertEq(whitelist.length, 1);
        assertEq(whitelist[0], solver);
    }

    /* ============ Verification Tests ============ */

    function test_deployMultiMint_verificationPasses() public view {
        scriptDeployer.verifyMultiMintDeployment(address(factory), address(multiMint), _defaultConfig());
    }

    /* ============ JSON Config Tests ============ */

    function _exampleJson() internal view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/extensions/example.json"));
    }

    /// @notice Keeps `extensions/example.json` in sync with the schema the script expects.
    function test_parseConfig_exampleTemplate() public view {
        Config.MultiMintConfig memory config_ = scriptDeployer.parseMultiMintConfig(_exampleJson(), "example");

        assertEq(config_.name, "Example USD");
        assertEq(config_.symbol, "exUSD");
        assertEq(config_.admin, address(1));
        assertEq(config_.assetCapManager, address(2));
        assertEq(config_.freezeManager, address(3));
        assertEq(config_.pauser, address(4));
        assertEq(config_.versionManager, address(5));
        assertEq(config_.yieldRecipient, address(6));
        assertEq(config_.yieldRecipientManager, address(7));

        assertEq(config_.assets.length, 2);
        assertEq(config_.assets[0], address(USDC));
        assertEq(config_.assetCaps[0], 100_000_000e6);
        assertEq(config_.assets[1], address(PYUSD));
        assertEq(config_.assetCaps[1], 50_000_000e6);

        assertEq(config_.replaceAssetWhitelist.length, 0);
    }

    function test_parseConfig_revertsOnExtensionNameMismatch() public {
        string memory json = _exampleJson();

        vm.expectRevert(bytes("config extensionName does not match EXTENSION_NAME"));
        scriptDeployer.parseMultiMintConfig(json, "some-other-extension");
    }

    function test_deployMultiMint_fromExampleConfigFile() public {
        Config.MultiMintConfig memory config_ = scriptDeployer.parseMultiMintConfig(_exampleJson(), "example");

        (address proxy, ) = scriptDeployer.deployMultiMintWith(address(factory), "example", config_);

        scriptDeployer.verifyMultiMintDeployment(address(factory), proxy, config_);
        assertTrue(swapFacility.isApprovedExtension(proxy));
        assertTrue(MultiMint(proxy).isAllowedAsset(address(USDC)));
        assertTrue(MultiMint(proxy).isAllowedAsset(address(PYUSD)));
    }

    /* ============ Config Validation Tests ============ */

    function test_validateConfig_revertsOnEmptyAssets() public {
        Config.MultiMintConfig memory config_ = _defaultConfig();
        config_.assets = new address[](0);
        config_.assetCaps = new uint256[](0);

        vm.expectRevert(bytes("ASSETS must list at least one collateral asset"));
        scriptDeployer.validateMultiMintConfig(config_);
    }

    function test_validateConfig_revertsOnLengthMismatch() public {
        Config.MultiMintConfig memory config_ = _defaultConfig();
        config_.assetCaps = new uint256[](1);
        config_.assetCaps[0] = USDC_CAP;

        vm.expectRevert(bytes("ASSETS and ASSET_CAPS length mismatch"));
        scriptDeployer.validateMultiMintConfig(config_);
    }

    function test_validateConfig_revertsOnZeroCap() public {
        Config.MultiMintConfig memory config_ = _defaultConfig();
        config_.assetCaps[1] = 0;

        vm.expectRevert(bytes("zero asset cap: a zero cap disables the asset"));
        scriptDeployer.validateMultiMintConfig(config_);
    }

    function test_validateConfig_revertsOnDuplicateAsset() public {
        Config.MultiMintConfig memory config_ = _defaultConfig();
        config_.assets[1] = address(USDC);

        vm.expectRevert(bytes("duplicate asset"));
        scriptDeployer.validateMultiMintConfig(config_);
    }
}
