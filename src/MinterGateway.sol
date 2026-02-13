// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IMinterGateway } from "./interfaces/IMinterGateway.sol";
import { IPYUSDX } from "./interfaces/IPYUSDX.sol";
import { AccessControlUpgradeable } from "../lib/m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/// @notice ERC-7201 namespaced storage layout for MinterGateway.
abstract contract MinterGatewayStorageLayout {
    /// @custom:storage-location erc7201:M0.storage.MinterGateway
    struct MinterGatewayStorageStruct {
        uint32 mintDelay;
        uint32 mintTTL;
        uint48 mintNonce;
        mapping(uint48 mintId => MintProposal) mintProposals;
    }

    struct MintProposal {
        uint40 createdAt;
        address minter;
        address recipient;
        uint256 amount;
    }

    // keccak256(abi.encode(uint256(keccak256("M0.storage.MinterGateway")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _MINTER_GATEWAY_STORAGE_LOCATION =
        0xda46dec3db1918d8d4832c5443057c953d7a27444565c41e9c2acac962bf4c00;

    function _getMinterGatewayStorageLocation() internal pure returns (MinterGatewayStorageStruct storage $) {
        assembly {
            $.slot := _MINTER_GATEWAY_STORAGE_LOCATION
        }
    }
}

/// @title MinterGateway
/// @author M0 Labs
/// @notice Gateway contract for proposing and executing mints on PYUSDX with a time delay.
contract MinterGateway is IMinterGateway, MinterGatewayStorageLayout, AccessControlUpgradeable {
    /* ============ Constants ============ */

    /// @inheritdoc IMinterGateway
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /* ============ Immutable Variables ============ */

    /// @inheritdoc IMinterGateway
    address public immutable pyusdx;

    /* ============ Constructor ============ */

    /// @notice Constructs the MinterGateway implementation contract.
    /// @param pyusdx_ The PYUSDX token contract address.
    constructor(address pyusdx_) {
        if (pyusdx_ == address(0)) revert ZeroPYUSDXToken();
        pyusdx = pyusdx_;

        _disableInitializers();
    }

    /* ============ Initializer ============ */

    /// @inheritdoc IMinterGateway
    function initialize(address admin, address minter, uint32 mintDelay_, uint32 mintTTL_) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);

        _setMintDelay(mintDelay_);
        _setMintTTL(mintTTL_);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc IMinterGateway
    function proposeMint(uint256 amount, address recipient) external onlyRole(MINTER_ROLE) returns (uint48 mintId) {
        if (amount == 0) revert ZeroMintAmount();
        if (recipient == address(0)) revert ZeroMintRecipient();

        MinterGatewayStorageStruct storage $ = _getMinterGatewayStorageLocation();
        mintId = ++$.mintNonce;

        $.mintProposals[mintId] = MintProposal({
            createdAt: uint40(block.timestamp),
            minter: msg.sender,
            recipient: recipient,
            amount: amount
        });

        emit MintProposed(mintId, msg.sender, amount, recipient);
    }

    /// @inheritdoc IMinterGateway
    function mint(uint48 mintId) external {
        MinterGatewayStorageStruct storage $ = _getMinterGatewayStorageLocation();
        MintProposal storage proposal = $.mintProposals[mintId];

        if (proposal.createdAt == 0) revert InvalidMintProposal();

        uint40 activeAt = proposal.createdAt + $.mintDelay;
        if (block.timestamp < activeAt) revert PendingMintProposal(activeAt);

        uint40 expiresAt = activeAt + $.mintTTL;
        if (block.timestamp > expiresAt) revert ExpiredMintProposal(expiresAt);

        address recipient = proposal.recipient;
        uint256 amount = proposal.amount;

        delete $.mintProposals[mintId];

        IPYUSDX(pyusdx).mint(recipient, amount);

        emit MintExecuted(mintId, msg.sender, amount, recipient);
    }

    /// @inheritdoc IMinterGateway
    function burn(uint256 amount) external onlyRole(MINTER_ROLE) {
        if (amount == 0) revert ZeroBurnAmount();

        IPYUSDX(pyusdx).burn(msg.sender, amount);

        emit BurnExecuted(msg.sender, amount);
    }

    /// @inheritdoc IMinterGateway
    function cancelMint(uint48 mintId) external {
        MinterGatewayStorageStruct storage $ = _getMinterGatewayStorageLocation();
        MintProposal storage proposal = $.mintProposals[mintId];

        if (proposal.createdAt == 0) revert InvalidMintProposal();
        if (proposal.minter != msg.sender) revert NotMintProposalCreator();

        uint40 activeAt = proposal.createdAt + $.mintDelay;
        if (block.timestamp >= activeAt) revert ActiveMintProposal(activeAt);

        delete $.mintProposals[mintId];

        emit MintCanceled(mintId, msg.sender);
    }

    /* ============ View Functions ============ */

    /// @inheritdoc IMinterGateway
    function mintDelay() external view returns (uint32) {
        return _getMinterGatewayStorageLocation().mintDelay;
    }

    /// @inheritdoc IMinterGateway
    function mintTTL() external view returns (uint32) {
        return _getMinterGatewayStorageLocation().mintTTL;
    }

    /// @inheritdoc IMinterGateway
    function mintNonce() external view returns (uint48) {
        return _getMinterGatewayStorageLocation().mintNonce;
    }

    /// @inheritdoc IMinterGateway
    function getMintProposal(
        uint48 mintId
    ) external view returns (uint40 createdAt, address minter, address recipient, uint256 amount) {
        MintProposal memory proposal = _getMinterGatewayStorageLocation().mintProposals[mintId];
        return (proposal.createdAt, proposal.minter, proposal.recipient, proposal.amount);
    }

    /* ============ Admin Functions ============ */

    /// @inheritdoc IMinterGateway
    function setMintDelay(uint32 mintDelay_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMintDelay(mintDelay_);
    }

    /// @inheritdoc IMinterGateway
    function setMintTTL(uint32 mintTTL_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMintTTL(mintTTL_);
    }

    /* ============ Internal Functions ============ */

    /// @notice Updates the mint delay
    /// @param mintDelay_ The mint delay in seconds
    function _setMintDelay(uint32 mintDelay_) internal {
        MinterGatewayStorageStruct storage $ = _getMinterGatewayStorageLocation();
        $.mintDelay = mintDelay_;
        emit MintDelaySet(mintDelay_);
    }

    /// @notice Updates the mint TTL
    /// @param mintTTL_ The mint TTL in seconds
    function _setMintTTL(uint32 mintTTL_) internal {
        MinterGatewayStorageStruct storage $ = _getMinterGatewayStorageLocation();
        $.mintTTL = mintTTL_;
        emit MintTTLSet(mintTTL_);
    }
}
