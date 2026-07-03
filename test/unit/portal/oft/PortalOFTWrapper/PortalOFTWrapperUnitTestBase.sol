// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.34;

import { TransparentUpgradeableProxy } from "../../../../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { TypeConverter } from "../../../../../lib/evm-m-extensions/lib/common/src/libs/TypeConverter.sol";

import { SendParam } from "../../../../../src/portal/oft/interfaces/IOFT.sol";
import { PortalOFTWrapper } from "../../../../../src/portal/oft/PortalOFTWrapper.sol";

import { PortalUnitTestBase } from "../../Portal/PortalUnitTestBase.sol";

abstract contract PortalOFTWrapperUnitTestBase is PortalUnitTestBase {
    using TypeConverter for address;

    uint32 internal constant DESTINATION_EID = 30110;

    uint256 internal constant FEE = 0.001 ether;

    PortalOFTWrapper internal wrapperImplementation;

    /// @dev Wrapper exposing PYUSDX.
    PortalOFTWrapper internal wrapper;

    /// @dev Wrapper exposing the PYUSDX Extension.
    PortalOFTWrapper internal extensionWrapper;

    bytes32 internal recipient = makeAddr("recipient").toBytes32();

    function setUp() public virtual override {
        super.setUp();

        wrapperImplementation = new PortalOFTWrapper(address(portal), address(pyusdx), address(bridgeAdapter));
        wrapper = _deployWrapperProxy(wrapperImplementation);
        extensionWrapper = _deployWrapperProxy(
            new PortalOFTWrapper(address(portal), address(extension), address(bridgeAdapter))
        );

        vm.startPrank(operator);
        wrapper.setDestinationToken(DESTINATION_EID, peerPYUSDX);
        extensionWrapper.setDestinationToken(DESTINATION_EID, peerExtension);
        vm.stopPrank();

        // The wrapper derives the internal chain ID from the bridge adapter's Endpoint ID mapping.
        bridgeAdapter.setChainId(DESTINATION_EID, CHAIN_ID_2);
        bridgeAdapter.setQuote(FEE);
    }

    function _deployWrapperProxy(PortalOFTWrapper implementation_) internal returns (PortalOFTWrapper) {
        return
            PortalOFTWrapper(
                address(
                    new TransparentUpgradeableProxy(
                        address(implementation_),
                        admin,
                        abi.encodeCall(PortalOFTWrapper.initialize, (admin, operator))
                    )
                )
            );
    }

    function _sendParam(uint256 amount, uint256 minAmount) internal view returns (SendParam memory) {
        return
            SendParam({
                dstEid: DESTINATION_EID,
                to: recipient,
                amountLD: amount,
                minAmountLD: minAmount,
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });
    }
}
