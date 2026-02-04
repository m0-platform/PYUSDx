// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { PausableUpgradeable } from "../../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IFreezable } from "../../lib/m-extensions/src/components/freezable/IFreezable.sol";
import { IndexingMath } from "../../lib/m-extensions/lib/common/src/libs/IndexingMath.sol";

import { PYUSDX } from "../../src/PYUSDX.sol";
import { IPYUSDX } from "../../src/interfaces/IPYUSDX.sol";

contract YieldManagementTest is Test {
    PYUSDX public pyusdx;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public freezeManager = makeAddr("freezeManager");
    address public forcedTransferManager = makeAddr("forcedTransferManager");
    address public earnerManager = makeAddr("earnerManager");
    address public rateManager = makeAddr("rateManager");
    address public minterGateway = makeAddr("minterGateway");
    address public pyusd = makeAddr("pyusd");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant PRECISION = 1e12;

    function setUp() public {
        PYUSDX implementation = new PYUSDX(minterGateway, pyusd);

        bytes memory initData = abi.encodeWithSelector(
            PYUSDX.initialize.selector,
            "PYUSDX",
            "PYUSDX",
            admin,
            pauser,
            freezeManager,
            forcedTransferManager,
            earnerManager,
            rateManager
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        pyusdx = PYUSDX(address(proxy));
    }

    /* ============ accruedYieldOf ============ */

    function test_accruedYieldOf_nonEarner() public view {
        uint240 yield = pyusdx.accruedYieldOf(alice);
        assertEq(yield, 0, "Non-earner should have 0 accrued yield");
    }

    function test_accruedYieldOf_earner() public {
        // Set a rate so index grows over time
        vm.prank(rateManager);
        pyusdx.setRate(500);

        // Set up alice as an earner
        uint112 principal = 1000e6;
        uint240 balance = 1000e6;
        _setAccountState(alice, earnerManager, balance, true, principal, 0, address(0));

        // Warp time to accrue yield
        vm.warp(block.timestamp + 365 days);

        // Calculate expected yield
        uint128 index = pyusdx.currentIndex();
        uint240 expectedBalanceWithYield = IndexingMath.getPresentAmountRoundedDown(principal, index);
        uint240 expectedYield = expectedBalanceWithYield > balance ? expectedBalanceWithYield - balance : 0;

        // Verify yield calculation
        uint240 actualYield = pyusdx.accruedYieldOf(alice);
        assertEq(actualYield, expectedYield, "Accrued yield should match expected");
        assertGt(actualYield, 0, "Should have positive yield after time passes");
    }

    /* ============ balanceWithYieldOf ============ */

    function test_balanceWithYieldOf() public {
        // Set a rate so index grows over time
        vm.prank(rateManager);
        pyusdx.setRate(500); 

        // Set up alice as an earner
        _setAccountState(alice, earnerManager, 1000e6, true, 1000e6, 0, address(0));
        _setBalance(alice, 1000e6);

        vm.warp(block.timestamp + 365 days);

        uint256 balanceWithYield = pyusdx.balanceWithYieldOf(alice);
        uint256 expectedBalance = pyusdx.balanceOf(alice) + pyusdx.accruedYieldOf(alice);

        assertEq(balanceWithYield, expectedBalance, "balanceWithYieldOf should equal balance + accruedYield");
    }

    /* ============ claimFor ============ */

    function test_claimFor_happyPath() public {
        vm.prank(rateManager);
        pyusdx.setRate(500);

        uint112 principal = 1000e6;
        uint240 balance = 1000e6;
        _setAccountState(alice, earnerManager, balance, true, principal, 0, address(0));
        _setBalance(alice, balance);
        _setTotalSupply(balance);
        _setTotalEarningSupply(balance);

        vm.warp(block.timestamp + 365 days);

        uint240 expectedYield = pyusdx.accruedYieldOf(alice);
        assertGt(expectedYield, 0, "Should have yield to claim");

        uint256 totalSupplyBefore = pyusdx.totalSupply();
        uint256 balanceBefore = pyusdx.balanceOf(alice);

        vm.expectEmit(true, true, false, true);
        emit IPYUSDX.Claimed(alice, alice, expectedYield);

        uint240 claimed = pyusdx.claimFor(alice);

        assertEq(claimed, expectedYield, "Should return claimed yield");
        assertEq(pyusdx.totalSupply(), totalSupplyBefore + expectedYield, "Total supply should increase by yield");
        assertEq(pyusdx.balanceOf(alice), balanceBefore + expectedYield, "balanceOf should increase by yield");
        assertEq(pyusdx.accruedYieldOf(alice), 0, "Accrued yield should be 0 after claim");
    }

    function test_claimFor_revert_whenPaused() public {
        _setAccountState(alice, earnerManager, 1000e6, true, 1000e6, 0, address(0));

        vm.prank(pauser);
        pyusdx.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        pyusdx.claimFor(alice);
    }

    function test_claimFor_revert_whenFrozen() public {
        _setAccountState(alice, earnerManager, 1000e6, true, 1000e6, 0, address(0));

        vm.prank(freezeManager);
        pyusdx.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountFrozen.selector, alice));
        pyusdx.claimFor(alice);
    }

    /* ============ Helper Functions ============ */
    // TODO: Replace storage manipulation with setEarningDetails() once implemented
    function _setAccountState(
        address account,
        address earnerManager_,
        uint240 balance_,
        bool isEarning_,
        uint112 earningPrincipal_,
        uint16 feeRate_,
        address claimRecipient_
    ) internal {
        bytes32 storageLocation = 0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;
        bytes32 accountsSlot = bytes32(uint256(storageLocation) + 4);
        bytes32 accountSlot = keccak256(abi.encode(account, accountsSlot));

        vm.store(address(pyusdx), accountSlot, bytes32(uint256(uint160(earnerManager_))));
        vm.store(address(pyusdx), bytes32(uint256(accountSlot) + 1), bytes32(uint256(balance_) | (uint256(isEarning_ ? 1 : 0) << 240)));
        vm.store(address(pyusdx), bytes32(uint256(accountSlot) + 2), bytes32(uint256(earningPrincipal_) | (uint256(feeRate_) << 112)));
        vm.store(address(pyusdx), bytes32(uint256(accountSlot) + 3), bytes32(uint256(uint160(claimRecipient_))));
    }

    function _setBalance(address account, uint256 balance_) internal {
        bytes32 storageLocation = 0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;
        bytes32 balanceOfSlot = bytes32(uint256(storageLocation) + 5);
        bytes32 accountBalanceSlot = keccak256(abi.encode(account, balanceOfSlot));
        vm.store(address(pyusdx), accountBalanceSlot, bytes32(balance_));
    }

    function _setTotalSupply(uint256 totalSupply_) internal {
        bytes32 storageLocation = 0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;
        bytes32 totalSupplySlot = bytes32(uint256(storageLocation) + 3);
        vm.store(address(pyusdx), totalSupplySlot, bytes32(totalSupply_));
    }

    function _setTotalEarningSupply(uint240 totalEarningSupply_) internal {
        bytes32 storageLocation = 0xc1b8ab2f33ccbf01222f9cf35bd888d518c2bda5deec0a0df8b0cd454fcb8500;
        bytes32 slot1 = bytes32(uint256(storageLocation) + 1);
        vm.store(address(pyusdx), slot1, bytes32(uint256(totalEarningSupply_)));
    }
}
