// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { UnsafeUpgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IssuerGateway } from "../../src/core/IssuerGateway.sol";
import { MockPYUSDX } from "../mock/MockPYUSDX.sol";

/// @title IssuerGateway Base Unit Test
/// @notice Base test contract with common setup for IssuerGateway tests
abstract contract IssuerGatewayBaseUnitTest is Test {
    IssuerGateway public issuerGateway;
    MockPYUSDX public pyusdx;

    // Test addresses
    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public rateLimitManager = makeAddr("rateLimitManager");
    address public recipient = makeAddr("recipient");
    address public caller = makeAddr("caller");
    address public other = makeAddr("other");

    uint32 public constant DEFAULT_MINT_DELAY = 1 days;
    uint32 public constant DEFAULT_MINT_TTL = 7 days;

    function setUp() public virtual {
        // Predict MockPYUSDX address:
        // After this point: nonce N -> IssuerGateway impl, N+1 -> proxy, N+2 -> MockPYUSDX
        uint256 nonceBefore = vm.getNonce(address(this));
        address predictedPyusdx = vm.computeCreateAddress(address(this), nonceBefore + 2);

        // Deploy IssuerGateway with predicted address
        address issuerGatewayImplementation = address(new IssuerGateway(predictedPyusdx));
        issuerGateway = IssuerGateway(
            UnsafeUpgrades.deployTransparentProxy(
                issuerGatewayImplementation,
                admin,
                abi.encodeWithSelector(
                    IssuerGateway.initialize.selector,
                    admin,
                    minter,
                    rateLimitManager,
                    DEFAULT_MINT_DELAY,
                    DEFAULT_MINT_TTL
                )
            )
        );

        // Deploy MockPYUSDX - lands at predicted address
        pyusdx = new MockPYUSDX(address(issuerGateway));
        assertEq(address(pyusdx), predictedPyusdx, "address prediction failed");
    }

    /* ============ Helper Functions ============ */

    /// @notice Proposes a mint from the minter account
    /// @param amount The amount to mint
    /// @param recipient_ The recipient address
    /// @return mintId The ID of the created mint proposal
    function _proposeMint(uint256 amount, address recipient_) internal returns (uint48 mintId) {
        vm.prank(minter);
        mintId = issuerGateway.proposeMint(amount, recipient_);
    }

    /// @notice Warps time to when a mint proposal becomes executable
    /// @param mintId The mint proposal ID
    function _warpToMintable(uint48 mintId) internal {
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        vm.warp(createdAt + issuerGateway.mintDelay());
    }

    /// @notice Warps time to when a mint proposal is expired
    /// @param mintId The mint proposal ID
    /// @return expiresAt The timestamp at which the proposal expired
    function _warpToExpired(uint48 mintId) internal returns (uint40 expiresAt) {
        (uint40 createdAt, , , ) = issuerGateway.getMintProposal(mintId);
        expiresAt = createdAt + issuerGateway.mintDelay() + issuerGateway.mintTTL();
        vm.warp(expiresAt + 1);
    }
}
