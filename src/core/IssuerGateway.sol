// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.34;

import { AccessControlUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import { IIssuerGateway } from "./IIssuerGateway.sol";
import { IPYUSDX } from "../IPYUSDX.sol";

/// @notice ERC-7201 namespaced storage layout for IssuerGateway.
abstract contract IssuerGatewayStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.IssuerGateway
    struct IssuerGatewayStorage {
        uint32 mintDelay; // ──╮ Delay in seconds before a mint can be executed.
        uint32 mintTTL; //     │ Time to live in seconds for a mint proposal.
        uint48 mintNonce; // ──╯ Incremental counter for generating unique mint IDs.
        mapping(uint48 mintId => MintProposal) mintProposals;
    }

    struct MintProposal {
        uint40 createdAt; // ──╮ Timestamp when the proposal was created, good for 100+ years.
        address minter; // ────╯ Address that proposed the mint.
        address recipient; //    Address that will receive the minted tokens.
        uint256 amount; //       Amount of PYUSDX to mint.
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.IssuerGateway")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _ISSUER_GATEWAY_STORAGE_LOCATION =
        0xda46dec3db1918d8d4832c5443057c953d7a27444565c41e9c2acac962bf4c00;

    function _getIssuerGatewayStorage() internal pure returns (IssuerGatewayStorage storage $) {
        assembly {
            $.slot := _ISSUER_GATEWAY_STORAGE_LOCATION
        }
    }
}

/// @title  IssuerGateway
/// @author M0 Labs
/// @notice Gateway contract for proposing and executing mints on PYUSDX with a time delay.
contract IssuerGateway is IIssuerGateway, IssuerGatewayStorageLayout, AccessControlUpgradeable {
    /* ============ Constants ============ */

    /// @inheritdoc IIssuerGateway
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @inheritdoc IIssuerGateway
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /* ============ Immutable Variables ============ */

    /// @inheritdoc IIssuerGateway
    address public immutable pyusdx;

    /* ============ Constructor ============ */

    /// @notice Constructs the IssuerGateway implementation contract.
    /// @param  pyusdx_ The PYUSDX token contract address.
    constructor(address pyusdx_) {
        if ((pyusdx = pyusdx_) == address(0)) revert ZeroPYUSDX();

        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /// @inheritdoc IIssuerGateway
    function initialize(
        address admin,
        address operator,
        address executor,
        uint32 mintDelay_,
        uint32 mintTTL_
    ) external initializer {
        if (admin == address(0)) revert ZeroAdmin();
        if (operator == address(0)) revert ZeroOperator();
        if (executor == address(0)) revert ZeroExecutor();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(EXECUTOR_ROLE, executor);

        _setMintDelay(mintDelay_);
        _setMintTTL(mintTTL_);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IIssuerGateway
    function proposeMint(uint256 amount, address recipient) external onlyRole(OPERATOR_ROLE) returns (uint48 mintId) {
        if (amount == 0) revert ZeroMintAmount();
        if (recipient == address(0)) revert ZeroMintRecipient();

        IssuerGatewayStorage storage $ = _getIssuerGatewayStorage();

        // NOTE: safe to use unchecked, overflow would occur after 281 trillion proposals,
        //       at which point nonce wrapping could theoretically reuse a deleted mintId.
        unchecked {
            mintId = ++$.mintNonce;
        }

        uint40 createdAt = uint40(block.timestamp);
        uint40 activeAt;
        uint40 expiresAt;

        // NOTE: safe to use unchecked, uint40 timestamps overflow past year 36812,
        //       and max uint32 delay (~136 years) cannot push them past that until then.
        unchecked {
            activeAt = createdAt + $.mintDelay;
            expiresAt = activeAt + $.mintTTL;
        }

        $.mintProposals[mintId] = MintProposal({
            createdAt: createdAt,
            minter: msg.sender,
            recipient: recipient,
            amount: amount
        });

        emit MintProposed(mintId, msg.sender, amount, recipient, activeAt, expiresAt);
    }

    /// @inheritdoc IIssuerGateway
    function cancelMint(uint48 mintId) external {
        IssuerGatewayStorage storage $ = _getIssuerGatewayStorage();
        MintProposal storage proposal = $.mintProposals[mintId];

        if (proposal.createdAt == 0) revert InvalidMintProposal();
        if (proposal.minter != msg.sender) revert NotMintProposalCreator();

        uint40 activeAt;

        // NOTE: safe to use unchecked, uint40 timestamps overflow past year 36812,
        //       and max uint32 delay (~136 years) cannot push them past that until then.
        unchecked {
            activeAt = proposal.createdAt + $.mintDelay;
        }

        if (block.timestamp >= activeAt) revert ActiveMintProposal(activeAt);

        delete $.mintProposals[mintId];

        emit MintCanceled(mintId, msg.sender);
    }

    /// @inheritdoc IIssuerGateway
    function mint(uint48 mintId) external onlyRole(EXECUTOR_ROLE) {
        IssuerGatewayStorage storage $ = _getIssuerGatewayStorage();
        MintProposal storage proposal = $.mintProposals[mintId];

        if (proposal.createdAt == 0) revert InvalidMintProposal();

        uint40 activeAt;
        uint40 expiresAt;

        // NOTE: compute activeAt first; expiresAt only needed if proposal is active.
        //       Safe to use unchecked, uint40 timestamps overflow past year 36812,
        //       and max uint32 delay (~136 years) cannot push them past that until then.
        unchecked {
            activeAt = proposal.createdAt + $.mintDelay;
        }

        if (block.timestamp < activeAt) revert PendingMintProposal(activeAt);

        unchecked {
            expiresAt = activeAt + $.mintTTL;
        }

        if (block.timestamp > expiresAt) revert ExpiredMintProposal(expiresAt);

        address recipient = proposal.recipient;
        uint256 amount = proposal.amount;

        delete $.mintProposals[mintId];

        emit MintExecuted(mintId, msg.sender, amount, recipient);

        IPYUSDX(pyusdx).mint(recipient, amount);
    }

    /// @inheritdoc IIssuerGateway
    function burn(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroBurnAmount();

        emit BurnExecuted(msg.sender, amount);

        IPYUSDX(pyusdx).burn(msg.sender, amount);
    }

    /* ============ Admin Functions ============ */

    /// @inheritdoc IIssuerGateway
    function setMintDelay(uint32 mintDelay_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMintDelay(mintDelay_);
    }

    /// @inheritdoc IIssuerGateway
    function setMintTTL(uint32 mintTTL_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMintTTL(mintTTL_);
    }

    /* ============ View Functions ============ */

    /// @inheritdoc IIssuerGateway
    function mintDelay() external view returns (uint32) {
        return _getIssuerGatewayStorage().mintDelay;
    }

    /// @inheritdoc IIssuerGateway
    function mintTTL() external view returns (uint32) {
        return _getIssuerGatewayStorage().mintTTL;
    }

    /// @inheritdoc IIssuerGateway
    function mintNonce() external view returns (uint48) {
        return _getIssuerGatewayStorage().mintNonce;
    }

    /// @inheritdoc IIssuerGateway
    function getMintProposal(
        uint48 mintId
    ) external view returns (uint40 createdAt, address minter, address recipient, uint256 amount) {
        MintProposal memory proposal = _getIssuerGatewayStorage().mintProposals[mintId];
        return (proposal.createdAt, proposal.minter, proposal.recipient, proposal.amount);
    }

    /* ============ Internal Functions ============ */

    /// @notice Updates the mint delay
    /// @param  mintDelay_ The mint delay in seconds
    function _setMintDelay(uint32 mintDelay_) internal {
        IssuerGatewayStorage storage $ = _getIssuerGatewayStorage();

        if ($.mintDelay == mintDelay_) return;

        $.mintDelay = mintDelay_;

        emit MintDelaySet(mintDelay_);
    }

    /// @notice Updates the mint TTL
    /// @param  mintTTL_ The mint TTL in seconds
    function _setMintTTL(uint32 mintTTL_) internal {
        if (mintTTL_ == 0) revert ZeroMintTTL();

        IssuerGatewayStorage storage $ = _getIssuerGatewayStorage();

        if ($.mintTTL == mintTTL_) return;

        $.mintTTL = mintTTL_;

        emit MintTTLSet(mintTTL_);
    }
}
