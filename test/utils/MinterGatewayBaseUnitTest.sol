// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MinterGateway } from "../../src/MinterGateway.sol";
import { PYUSDXMock } from "../mock/PYUSDXMock.sol";

/// @title MinterGateway Base Unit Test
/// @notice Base test contract with common setup for MinterGateway tests
abstract contract MinterGatewayBaseUnitTest is Test {
    MinterGateway public minterGateway;
    PYUSDXMock public pyusdx;

    // Test addresses
    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public recipient = makeAddr("recipient");
    address public caller = makeAddr("caller");
    address public other = makeAddr("other");

    uint32 public constant DEFAULT_MINT_DELAY = 1 days;
    uint32 public constant DEFAULT_MINT_TTL = 7 days;

    function setUp() public virtual {
        // Predict PYUSDXMock address:
        // After this point: nonce N -> MinterGateway impl, N+1 -> proxy, N+2 -> PYUSDXMock
        uint256 nonceBefore = vm.getNonce(address(this));
        address predictedPyusdx = vm.computeCreateAddress(address(this), nonceBefore + 2);

        // Deploy MinterGateway with predicted address
        address minterGatewayImplementation = address(new MinterGateway(predictedPyusdx));
        minterGateway = MinterGateway(
            UnsafeUpgrades.deployTransparentProxy(
                minterGatewayImplementation,
                admin,
                abi.encodeWithSelector(
                    MinterGateway.initialize.selector,
                    admin,
                    minter,
                    DEFAULT_MINT_DELAY,
                    DEFAULT_MINT_TTL
                )
            )
        );

        // Deploy PYUSDXMock - lands at predicted address
        pyusdx = new PYUSDXMock(address(minterGateway));
        assertEq(address(pyusdx), predictedPyusdx, "address prediction failed");
    }

    /* ============ Helper Functions ============ */

    /// @notice Proposes a mint from the minter account
    /// @param amount The amount to mint
    /// @param recipient_ The recipient address
    /// @return mintId The ID of the created mint proposal
    function _proposeMint(uint256 amount, address recipient_) internal returns (uint48 mintId) {
        vm.prank(minter);
        mintId = minterGateway.proposeMint(amount, recipient_);
    }

    /// @notice Warps time to when a mint proposal becomes executable
    /// @param mintId The mint proposal ID
    function _warpToMintable(uint48 mintId) internal {
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        vm.warp(createdAt + minterGateway.mintDelay());
    }

    /// @notice Warps time to when a mint proposal is expired
    /// @param mintId The mint proposal ID
    /// @return expiresAt The timestamp at which the proposal expired
    function _warpToExpired(uint48 mintId) internal returns (uint40 expiresAt) {
        (uint40 createdAt, , , ) = minterGateway.getMintProposal(mintId);
        expiresAt = createdAt + minterGateway.mintDelay() + minterGateway.mintTTL();
        vm.warp(expiresAt + 1);
    }
}
