// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {MailboxTest} from "./_Mailbox_Shared.t.sol";
import {DummyStateTransitionManagerWBH} from "contracts/dev-contracts/test/DummyStateTransitionManagerWithBridgeHubAddress.sol";
import {DummyBridgehub} from "contracts/dev-contracts/test/DummyBridgehub.sol";
import {L1SharedBridge} from "contracts/bridge/L1SharedBridge.sol";
import {IBridgehub} from "contracts/bridgehub/IBridgehub.sol";

contract MailboxTransferEthToSharedBridge is MailboxTest {
    function setUp() public virtual {
        init();
    }

    function test_transferEthToSharedBridge() public {
        DummyBridgehub bridgeHub = new DummyBridgehub();
        address bridgehubAddress = address(bridgeHub);
        DummyStateTransitionManagerWBH stm = new DummyStateTransitionManagerWBH(address(bridgeHub));
        address l1WethAddress = makeAddr("l1Weth");

        L1SharedBridge baseTokenBridge = new L1SharedBridge({
            _l1WethAddress: l1WethAddress,
            _bridgehub: IBridgehub(bridgehubAddress),
            _eraChainId: eraChainId,
            _eraDiamondProxy: diamondProxy
        });

        address baseTokenBridgeAddress = address(baseTokenBridge);

        bridgeHub.setStateTransitionManager(eraChainId, address(stm));
        stm.setHyperchain(eraChainId, diamondProxy);

        utilsFacet.util_setChainId(eraChainId);
        utilsFacet.util_setBaseTokenBridge(baseTokenBridgeAddress);
        utilsFacet.util_setBridgehub(bridgehubAddress);

        vm.deal(diamondProxy, 1 ether);
        vm.prank(baseTokenBridgeAddress);
        mailboxFacet.transferEthToSharedBridge();
        assertEq(baseTokenBridgeAddress.balance, 1 ether);
    }

    function test_RevertWhen_transferEthToSharedBridgeBadCaller() public {
        address baseTokenBridge = makeAddr("bridge");
        utilsFacet.util_setChainId(eraChainId);

        vm.deal(diamondProxy, 1 ether);

        vm.expectRevert("Hyperchain: Only base token bridge can call this function");
        vm.prank(baseTokenBridge);
        mailboxFacet.transferEthToSharedBridge();
    }

    function test_RevertWhen_transferEthToSharedBridgeBadHyperchain() public {
        address baseTokenBridge = makeAddr("bridge");

        utilsFacet.util_setChainId(eraChainId + 1);
        utilsFacet.util_setBaseTokenBridge(baseTokenBridge);

        vm.deal(diamondProxy, 1 ether);

        vm.expectRevert("Mailbox: transferEthToSharedBridge only available for Era on mailbox");
        vm.prank(baseTokenBridge);
        mailboxFacet.transferEthToSharedBridge();
    }
}
