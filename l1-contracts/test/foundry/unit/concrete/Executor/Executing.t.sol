// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Test.sol";
import {Utils, L2_SYSTEM_CONTEXT_ADDRESS} from "../Utils/Utils.sol";

import {ExecutorTest} from "./_Executor_Shared.t.sol";

import {L2_BOOTLOADER_ADDRESS} from "contracts/common/L2ContractAddresses.sol";
import {COMMIT_TIMESTAMP_NOT_OLDER, REQUIRED_L2_GAS_PRICE_PER_PUBDATA} from "contracts/common/Config.sol";
import {IExecutor, SystemLogKey} from "contracts/state-transition/chain-interfaces/IExecutor.sol";

contract ExecutingTest is ExecutorTest {
    function setUp() public {
        vm.warp(COMMIT_TIMESTAMP_NOT_OLDER + 1);
        currentTimestamp = block.timestamp;

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        bytes memory l2Logs = Utils.encodePacked(correctL2Logs);

        newCommitBatchInfo.systemLogs = l2Logs;
        newCommitBatchInfo.timestamp = uint64(currentTimestamp);

        IExecutor.CommitBatchInfo[] memory commitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        commitBatchInfoArray[0] = newCommitBatchInfo;

        vm.prank(validator);
        vm.recordLogs();
        executor.commitBatches(genesisStoredBatchInfo, commitBatchInfoArray);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        newStoredBatchInfo = IExecutor.StoredBatchInfo({
            batchNumber: 1,
            batchHash: entries[0].topics[2],
            indexRepeatedStorageChanges: 0,
            numberOfLayer1Txs: 0,
            priorityOperationsHash: keccak256(""),
            l2LogsTreeRoot: 0,
            timestamp: currentTimestamp,
            commitment: entries[0].topics[3]
        });

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.prank(validator);
        executor.proveBatches(genesisStoredBatchInfo, storedBatchInfoArray, proofInput);
    }

    function _commitAndProveMultipleBatches(
        uint256 _count,
        uint256 _startBatchNumber
    ) internal returns (IExecutor.StoredBatchInfo[] memory storedBatchInfos) {
        uint256 timestamp = currentTimestamp + 1;

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](_count);
        IExecutor.StoredBatchInfo memory lastCommitted = newStoredBatchInfo;
        IExecutor.StoredBatchInfo memory lastProved = newStoredBatchInfo;

        for (uint256 i = 0; i < _count; i++) {
            uint256 batchTimestamp = timestamp + i;
            bytes[] memory correctL2Logs = Utils.createSystemLogs();

            correctL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils
                .constructL2Log(
                    true,
                    L2_SYSTEM_CONTEXT_ADDRESS,
                    uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
                    Utils.packBatchTimestampAndBlockTimestamp(batchTimestamp, batchTimestamp)
                );

            correctL2Logs[uint256(uint256(SystemLogKey.PREV_BATCH_HASH_KEY))] = Utils.constructL2Log(
                true,
                L2_SYSTEM_CONTEXT_ADDRESS,
                uint256(SystemLogKey.PREV_BATCH_HASH_KEY),
                lastCommitted.batchHash
            );

            bytes memory l2Logs = Utils.encodePacked(correctL2Logs);

            IExecutor.CommitBatchInfo memory commitBatch = newCommitBatchInfo;
            commitBatch.systemLogs = l2Logs;
            commitBatch.timestamp = uint64(batchTimestamp);
            commitBatch.batchNumber = uint64(_startBatchNumber + i);

            IExecutor.CommitBatchInfo[] memory commitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
            commitBatchInfoArray[0] = commitBatch;

            vm.recordLogs();
            vm.prank(validator);
            executor.commitBatches(lastCommitted, commitBatchInfoArray);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            lastCommitted = IExecutor.StoredBatchInfo({
                batchNumber: uint64(_startBatchNumber + i),
                batchHash: entries[0].topics[2],
                indexRepeatedStorageChanges: 0,
                numberOfLayer1Txs: 0,
                priorityOperationsHash: keccak256(""),
                l2LogsTreeRoot: 0,
                timestamp: batchTimestamp,
                commitment: entries[0].topics[3]
            });

            IExecutor.StoredBatchInfo[] memory toProve = new IExecutor.StoredBatchInfo[](1);
            toProve[0] = lastCommitted;

            vm.prank(validator);
            executor.proveBatches(lastProved, toProve, proofInput);

            storedBatchInfoArray[i] = lastCommitted;
            lastProved = lastCommitted;
        }

        return storedBatchInfoArray;
    }

    function test_RevertWhen_ExecutingBlockWithWrongBatchNumber() public {
        IExecutor.StoredBatchInfo memory wrongNewStoredBatchInfo = newStoredBatchInfo;
        wrongNewStoredBatchInfo.batchNumber = 10; // Correct is 1

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = wrongNewStoredBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("k"));
        executor.executeBatches(storedBatchInfoArray);
    }

    function test_RevertWhen_ExecutingBlockWithWrongData() public {
        IExecutor.StoredBatchInfo memory wrongNewStoredBatchInfo = newStoredBatchInfo;
        wrongNewStoredBatchInfo.timestamp = 0; // incorrect timestamp

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = wrongNewStoredBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("exe10"));
        executor.executeBatches(storedBatchInfoArray);
    }

    function test_RevertWhen_ExecutingRevertedBlockWithoutCommittingAndProvingAgain() public {
        vm.prank(validator);
        executor.revertBatches(0);

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("n"));
        executor.executeBatches(storedBatchInfoArray);
    }

    function test_RevertWhen_ExecutingUnavailablePriorityOperationHash() public {
        vm.prank(validator);
        executor.revertBatches(0);

        bytes32 arbitraryCanonicalTxHash = Utils.randomBytes32("arbitraryCanonicalTxHash");
        bytes32 chainedPriorityTxHash = keccak256(bytes.concat(keccak256(""), arbitraryCanonicalTxHash));

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );
        correctL2Logs[uint256(SystemLogKey.CHAINED_PRIORITY_TXN_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            uint256(SystemLogKey.CHAINED_PRIORITY_TXN_HASH_KEY),
            chainedPriorityTxHash
        );
        correctL2Logs[uint256(SystemLogKey.NUMBER_OF_LAYER_1_TXS_KEY)] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            uint256(SystemLogKey.NUMBER_OF_LAYER_1_TXS_KEY),
            bytes32(uint256(1))
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);
        correctNewCommitBatchInfo.priorityOperationsHash = chainedPriorityTxHash;
        correctNewCommitBatchInfo.numberOfLayer1Txs = 1;

        IExecutor.CommitBatchInfo[] memory correctNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctNewCommitBatchInfoArray[0] = correctNewCommitBatchInfo;

        vm.prank(validator);
        vm.recordLogs();
        executor.commitBatches(genesisStoredBatchInfo, correctNewCommitBatchInfoArray);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        IExecutor.StoredBatchInfo memory correctNewStoredBatchInfo = newStoredBatchInfo;
        correctNewStoredBatchInfo.batchHash = entries[0].topics[2];
        correctNewStoredBatchInfo.numberOfLayer1Txs = 1;
        correctNewStoredBatchInfo.priorityOperationsHash = chainedPriorityTxHash;
        correctNewStoredBatchInfo.commitment = entries[0].topics[3];

        IExecutor.StoredBatchInfo[] memory correctNewStoredBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        correctNewStoredBatchInfoArray[0] = correctNewStoredBatchInfo;

        vm.prank(validator);
        executor.proveBatches(genesisStoredBatchInfo, correctNewStoredBatchInfoArray, proofInput);

        vm.prank(validator);
        vm.expectRevert(bytes.concat("s"));
        executor.executeBatches(correctNewStoredBatchInfoArray);
    }

    function test_RevertWhen_ExecutingWithUnmatchedPriorityOperationHash() public {
        vm.prank(validator);
        executor.revertBatches(0);

        bytes32 arbitraryCanonicalTxHash = Utils.randomBytes32("arbitraryCanonicalTxHash");
        bytes32 chainedPriorityTxHash = keccak256(bytes.concat(keccak256(""), arbitraryCanonicalTxHash));

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );
        correctL2Logs[uint256(SystemLogKey.CHAINED_PRIORITY_TXN_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            uint256(SystemLogKey.CHAINED_PRIORITY_TXN_HASH_KEY),
            chainedPriorityTxHash
        );
        correctL2Logs[uint256(SystemLogKey.NUMBER_OF_LAYER_1_TXS_KEY)] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            uint256(SystemLogKey.NUMBER_OF_LAYER_1_TXS_KEY),
            bytes32(uint256(1))
        );
        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);
        correctNewCommitBatchInfo.priorityOperationsHash = chainedPriorityTxHash;
        correctNewCommitBatchInfo.numberOfLayer1Txs = 1;

        IExecutor.CommitBatchInfo[] memory correctNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctNewCommitBatchInfoArray[0] = correctNewCommitBatchInfo;

        vm.prank(validator);
        vm.recordLogs();
        executor.commitBatches(genesisStoredBatchInfo, correctNewCommitBatchInfoArray);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        IExecutor.StoredBatchInfo memory correctNewStoredBatchInfo = newStoredBatchInfo;
        correctNewStoredBatchInfo.batchHash = entries[0].topics[2];
        correctNewStoredBatchInfo.numberOfLayer1Txs = 1;
        correctNewStoredBatchInfo.priorityOperationsHash = chainedPriorityTxHash;
        correctNewStoredBatchInfo.commitment = entries[0].topics[3];

        IExecutor.StoredBatchInfo[] memory correctNewStoredBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        correctNewStoredBatchInfoArray[0] = correctNewStoredBatchInfo;

        vm.prank(validator);
        executor.proveBatches(genesisStoredBatchInfo, correctNewStoredBatchInfoArray, proofInput);

        bytes32 randomFactoryDeps0 = Utils.randomBytes32("randomFactoryDeps0");

        bytes[] memory factoryDeps = new bytes[](1);
        factoryDeps[0] = bytes.concat(randomFactoryDeps0);

        uint256 gasPrice = 1000000000;
        uint256 l2GasLimit = 1000000;
        uint256 baseCost = mailbox.l2TransactionBaseCost(gasPrice, l2GasLimit, REQUIRED_L2_GAS_PRICE_PER_PUBDATA);
        uint256 l2Value = 10 ether;
        uint256 totalCost = baseCost + l2Value;

        mailbox.requestL2Transaction{value: totalCost}({
            _contractL2: address(0),
            _l2Value: l2Value,
            _calldata: bytes(""),
            _l2GasLimit: l2GasLimit,
            _l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            _factoryDeps: factoryDeps,
            _refundRecipient: address(0)
        });

        vm.prank(validator);
        vm.expectRevert(bytes.concat("x"));
        executor.executeBatches(correctNewStoredBatchInfoArray);
    }

    function test_RevertWhen_CommittingBlockWithWrongPreviousBatchHash() public {
        // solhint-disable-next-line func-named-parameters
        bytes memory correctL2Logs = abi.encodePacked(
            bytes4(0x00000001),
            bytes4(0x00000000),
            L2_SYSTEM_CONTEXT_ADDRESS,
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp),
            bytes32("")
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = correctL2Logs;

        IExecutor.CommitBatchInfo[] memory correctNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctNewCommitBatchInfoArray[0] = correctNewCommitBatchInfo;

        bytes32 wrongPreviousBatchHash = Utils.randomBytes32("wrongPreviousBatchHash");

        IExecutor.StoredBatchInfo memory genesisBlock = genesisStoredBatchInfo;
        genesisBlock.batchHash = wrongPreviousBatchHash;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("i"));
        executor.commitBatches(genesisBlock, correctNewCommitBatchInfoArray);
    }

    function test_ShouldExecuteBatchesuccessfully() public {
        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        // solhint-disable-next-line func-named-parameters
        vm.expectEmit(true, true, true, true, address(executor));
        emit BlockExecution(
            newStoredBatchInfo.batchNumber,
            newStoredBatchInfo.batchHash,
            newStoredBatchInfo.commitment
        );

        vm.prank(validator);
        executor.executeBatches(storedBatchInfoArray);

        assertEq(getters.getTotalBlocksExecuted(), 1);
        assertEq(getters.l2LogsRootHash(newStoredBatchInfo.batchNumber), newStoredBatchInfo.l2LogsTreeRoot);
    }

    function test_shouldDeleteSystemUpgradeData(uint256 batchNumberBefore) public {
        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](4);
        IExecutor.StoredBatchInfo[] memory newbatches = _commitAndProveMultipleBatches(3, 2);
        storedBatchInfoArray[0] = newStoredBatchInfo;
        storedBatchInfoArray[1] = newbatches[0];
        storedBatchInfoArray[2] = newbatches[1];
        storedBatchInfoArray[3] = newbatches[2];

        batchNumberBefore = bound(batchNumberBefore, 1, newbatches[2].batchNumber);
        utils.util_setL2SystemContractsUpgradeBatchNumber(1);
        utils.util_setL2SystemContractsUpgradeTxHash(bytes32("upgrade hash"));

        vm.prank(validator);
        executor.executeBatches(storedBatchInfoArray);

        assertEq(getters.getTotalBlocksExecuted(), 4);
        assertEq(getters.getL2SystemContractsUpgradeBatchNumber(), 0);
        assertEq(getters.getL2SystemContractsUpgradeTxHash(), bytes32(0));
        assertEq(getters.l2LogsRootHash(newbatches[2].batchNumber), newbatches[2].l2LogsTreeRoot);
    }

    function test_shouldNotDeleteSystemUpgradeData(uint256 batchNumberAfter) public {
        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](4);
        IExecutor.StoredBatchInfo[] memory newbatches = _commitAndProveMultipleBatches(3, 2);
        storedBatchInfoArray[0] = newStoredBatchInfo;
        storedBatchInfoArray[1] = newbatches[0];
        storedBatchInfoArray[2] = newbatches[1];
        storedBatchInfoArray[3] = newbatches[2];

        batchNumberAfter = bound(batchNumberAfter, newbatches[2].batchNumber + 1, type(uint256).max);
        utils.util_setL2SystemContractsUpgradeBatchNumber(batchNumberAfter);
        utils.util_setL2SystemContractsUpgradeTxHash(bytes32("upgrade hash"));

        vm.prank(validator);
        executor.executeBatches(storedBatchInfoArray);

        assertEq(getters.getTotalBlocksExecuted(), 4);
        assertEq(getters.getL2SystemContractsUpgradeBatchNumber(), batchNumberAfter);
        assertEq(getters.getL2SystemContractsUpgradeTxHash(), bytes32("upgrade hash"));
        assertEq(getters.l2LogsRootHash(newbatches[2].batchNumber), newbatches[2].l2LogsTreeRoot);
    }

    function test_shouldBeCalledOnlyByValidator(address caller) public {
        vm.assume(caller != validator);

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.expectRevert("Hyperchain: not validator");
        vm.prank(caller);
        executor.executeBatches(storedBatchInfoArray);
    }
}
