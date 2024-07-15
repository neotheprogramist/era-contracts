// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMailbox} from "contracts/state-transition/chain-interfaces/IMailbox.sol";
import {Bridgehub} from "contracts/bridgehub/Bridgehub.sol";
import {MockExecutorFacet} from "contracts/dev-contracts/test/MockExecutor.sol";
import {Forwarder} from "contracts/dev-contracts/Forwarder.sol";

contract MailboxTest is Test {

    struct L2TransactionRequestDirect {
        uint256 chainId;
        uint256 mintValue;
        address l2Contract;
        uint256 l2Value;
        bytes l2Calldata;
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        bytes[] factoryDeps;
        address refundRecipient;
    }

    IMailbox mailbox;
    MockExecutorFacet proxyAsMockExecutor;
    Bridgehub bridgehub;
    Forwarder forwarder;
    uint256 chainId = 9;

    function setup() public {
        bridgehub = new Bridgehub();
    }

    function test_acceptCorrectBytecode() public {
        // L2TransactionRequestDirect memory requestCallData = L2TransactionRequestDirect({
        //     chainId,
        //     l2Contract: to,
        //     mintValue: await overrides.value,
        //     l2Value,
        //     l2Calldata: calldata,
        //     l2GasLimit,
        //     l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
        //     factoryDeps,
        //     refundRecipient,
        // });

        // vm.expectRevert();
        // bridgehub.requestL2TransactionDirect(requestCallData);
    }

    function test_invalidProof() public {
        // const invalidProof = [...MERKLE_PROOF];
        // string memory invalidProof[0] = "0x72abee45b59e344af8a6e520241c4744aff26ed411f4c4b00f8af09adada43bb";

        // vm.expectRevert("Mailbox: finalizeEthWithdrawal only available for Era on mailbox")
        // mailbox.finalizeEthWithdrawal(BLOCK_NUMBER, MESSAGE_INDEX, TX_NUMBER_IN_BLOCK, MESSAGE, invalidProof)
    }
}