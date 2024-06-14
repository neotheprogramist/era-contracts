// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Test.sol";
import {Utils, L2_SYSTEM_CONTEXT_ADDRESS} from "../Utils/Utils.sol";

import {ExecutorTest} from "./_Executor_Shared.t.sol";

import {COMMIT_TIMESTAMP_NOT_OLDER, PUBLIC_INPUT_SHIFT} from "contracts/common/Config.sol";
import {IExecutor, SystemLogKey} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";

contract ProvingTest is ExecutorTest {
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

        newCommitBatchInfo.timestamp = uint64(currentTimestamp);
        newCommitBatchInfo.systemLogs = l2Logs;

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
    }

    function _commitMultipleBatches(
        uint256 _count,
        uint256 _startBatchNumber
    ) internal returns (IExecutor.StoredBatchInfo[] memory storedBatchInfos) {
        uint256 timestamp = currentTimestamp + 1;

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](_count);
        IExecutor.StoredBatchInfo memory lastCommited = newStoredBatchInfo;

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
                lastCommited.batchHash
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
            executor.commitBatches(lastCommited, commitBatchInfoArray);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            lastCommited = IExecutor.StoredBatchInfo({
                batchNumber: uint64(_startBatchNumber + i),
                batchHash: entries[0].topics[2],
                indexRepeatedStorageChanges: 0,
                numberOfLayer1Txs: 0,
                priorityOperationsHash: keccak256(""),
                l2LogsTreeRoot: 0,
                timestamp: batchTimestamp,
                commitment: entries[0].topics[3]
            });

            storedBatchInfoArray[i] = lastCommited;
        }

        return storedBatchInfoArray;
    }

    function test_RevertWhen_wrongCaller(address _caller) public {
        vm.assume(_caller != validator);

        vm.expectRevert("Hyperchain: not validator");
        executor.proveBatches(genesisStoredBatchInfo, new IExecutor.StoredBatchInfo[](0), proofInput);
    }

    function test_RevertWhen_ProvingWithWrongPreviousBlockData() public {
        IExecutor.StoredBatchInfo memory wrongPreviousStoredBatchInfo = genesisStoredBatchInfo;
        wrongPreviousStoredBatchInfo.batchNumber = 10; // Correct is 0

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("t1"));
        executor.proveBatches(wrongPreviousStoredBatchInfo, storedBatchInfoArray, proofInput);
    }

    function test_RevertWhen_ProvingWithWrongCommittedBlock() public {
        IExecutor.StoredBatchInfo memory wrongNewStoredBatchInfo = newStoredBatchInfo;
        wrongNewStoredBatchInfo.batchNumber = 10; // Correct is 1

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = wrongNewStoredBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("o1"));
        executor.proveBatches(genesisStoredBatchInfo, storedBatchInfoArray, proofInput);
    }

    function test_RevertWhen_ProvingRevertedBlockWithoutCommittingAgain() public {
        vm.prank(validator);
        executor.revertBatches(0);

        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("q"));
        executor.proveBatches(genesisStoredBatchInfo, storedBatchInfoArray, proofInput);
    }

    function test_RevertWhen_proveMultipleBatches() public {
        IExecutor.StoredBatchInfo[] memory storedBatchInfos = _commitMultipleBatches(2, 2);
        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](3);
        storedBatchInfoArray[0] = newStoredBatchInfo;
        storedBatchInfoArray[1] = storedBatchInfos[0];
        storedBatchInfoArray[2] = storedBatchInfos[1];

        vm.prank(validator);
        vm.expectRevert(bytes.concat("t4"));
        executor.proveBatches(genesisStoredBatchInfo, storedBatchInfoArray, proofInput);
    }

    function test_RevertWhen_verifyFailed() public {
        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.prank(validator);
        uint256[] memory proofPublicInput = new uint256[](1);
        proofPublicInput[0] =
            uint256(keccak256(abi.encodePacked(genesisStoredBatchInfo.commitment, newStoredBatchInfo.commitment))) >>
            PUBLIC_INPUT_SHIFT;

        vm.mockCall(
            testnetVerifierAddress,
            abi.encodeWithSelector(
                IVerifier.verify.selector,
                proofPublicInput,
                proofInput.serializedProof,
                proofInput.recursiveAggregationInput
            ),
            abi.encode(false)
        );
        vm.expectRevert(bytes.concat("p"));
        executor.proveBatches(genesisStoredBatchInfo, storedBatchInfoArray, proofInput);
    }

    function test_SuccessfulProve() public {
        IExecutor.StoredBatchInfo[] memory storedBatchInfoArray = new IExecutor.StoredBatchInfo[](1);
        storedBatchInfoArray[0] = newStoredBatchInfo;

        vm.prank(validator);
        vm.expectEmit(true, false, false, false, address(executor));
        emit BlocksVerification({previousLastVerifiedBatch: 0, currentLastVerifiedBatch: 1});

        executor.proveBatches(genesisStoredBatchInfo, storedBatchInfoArray, proofInput);
        assertEq(getters.getTotalBlocksVerified(), 1);
    }
}
