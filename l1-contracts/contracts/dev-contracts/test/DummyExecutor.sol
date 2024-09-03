// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IExecutor} from "../../state-transition/chain-interfaces/IExecutor.sol";
import {PriorityOpsBatchInfo} from "../../state-transition/libraries/PriorityTree.sol";
import {DummyExecutorShouldRevertOnCommitBatches, DummyExecutorInvalidLastCommittedBatchNumber, DummyExecutorInvalidBatchNumber, DummyExecutorShouldRevertOnProveBatches, DummyExecutorInvalidPreviousBatchNumber, DummyExecutorCanProveOnlyOneBatch, DummyExecutorCannotProveBatchOutOfOrder, DummyExecutorProveMoreBatchesThanWereCommitted, DummyExecutorShouldRevertOnExecuteBatches, DummyExecutorCannotExecuteBatchesMoreThanCommittedAndProvenCurrently, DummyExecutorTheLastCommittedBatchIsLessThanNewLastBatch} from "../L1DevContractsErrors.sol";

/// @title DummyExecutor
/// @notice A test smart contract implementing the IExecutor interface to simulate Executor behavior for testing purposes.
contract DummyExecutor is IExecutor {
    // add this to be excluded from coverage report
    function test() internal virtual {}

    address owner;

    // Flags to control if the contract should revert during commit, prove, and execute batch operations
    bool shouldRevertOnCommitBatches;
    bool shouldRevertOnProveBatches;
    bool shouldRevertOnExecuteBatches;

    // Counters to track the total number of committed, verified, and executed batches
    uint256 public getTotalBatchesCommitted;
    uint256 public getTotalBatchesVerified;
    uint256 public getTotalBatchesExecuted;
    string public constant override getName = "DummyExecutor";

    /// @notice Constructor sets the contract owner to the message sender
    constructor() {
        owner = msg.sender;
    }

    /// @notice Modifier that only allows the owner to call certain functions
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    function getAdmin() external view returns (address) {
        return owner;
    }

    /// @notice Removing txs from the priority queue
    function removePriorityQueueFront(uint256 _index) external {}

    /// @notice Allows the owner to set whether the contract should revert during commit blocks operation
    function setShouldRevertOnCommitBatches(bool _shouldRevert) external onlyOwner {
        shouldRevertOnCommitBatches = _shouldRevert;
    }

    /// @notice Allows the owner to set whether the contract should revert during prove batches operation
    function setShouldRevertOnProveBatches(bool _shouldRevert) external onlyOwner {
        shouldRevertOnProveBatches = _shouldRevert;
    }

    /// @notice Allows the owner to set whether the contract should revert during execute batches operation
    function setShouldRevertOnExecuteBatches(bool _shouldRevert) external onlyOwner {
        shouldRevertOnExecuteBatches = _shouldRevert;
    }

    function commitBatchesSharedBridge(
        uint256,
        StoredBatchInfo calldata _lastCommittedBatchData,
        CommitBatchInfo[] calldata _newBatchesData
    ) external {
        if (shouldRevertOnCommitBatches) {
            revert DummyExecutorShouldRevertOnCommitBatches();
        }
        if (_lastCommittedBatchData.batchNumber != getTotalBatchesCommitted) {
            revert DummyExecutorInvalidLastCommittedBatchNumber();
        }

        uint256 batchesLength = _newBatchesData.length;
        for (uint256 i = 0; i < batchesLength; ++i) {
            if (getTotalBatchesCommitted + i + 1 != _newBatchesData[i].batchNumber) {
                revert DummyExecutorInvalidBatchNumber();
            }
        }

        getTotalBatchesCommitted += batchesLength;
    }

    function proveBatchesSharedBridge(
        uint256,
        StoredBatchInfo calldata _prevBatch,
        StoredBatchInfo[] calldata _committedBatches,
        ProofInput calldata _proof
    ) external {
        if (shouldRevertOnProveBatches) {
            revert DummyExecutorShouldRevertOnProveBatches();
        }
        if (_prevBatch.batchNumber != getTotalBatchesVerified) {
            revert DummyExecutorInvalidPreviousBatchNumber();
        }

        if (_committedBatches.length != 1) {
            revert DummyExecutorCanProveOnlyOneBatch();
        }
        if (_committedBatches[0].batchNumber != _prevBatch.batchNumber + 1) {
            revert DummyExecutorCannotProveBatchOutOfOrder();
        }

        getTotalBatchesVerified += 1;
        if (getTotalBatchesVerified > getTotalBatchesCommitted) {
            revert DummyExecutorProveMoreBatchesThanWereCommitted();
        }
    }

    function executeBatches(StoredBatchInfo[] calldata _batchesData) public {
        if (shouldRevertOnExecuteBatches) {
            revert DummyExecutorShouldRevertOnExecuteBatches();
        }
        uint256 nBatches = _batchesData.length;
        for (uint256 i = 0; i < nBatches; ++i) {
            if (_batchesData[i].batchNumber != getTotalBatchesExecuted + i + 1) {
                revert DummyExecutorInvalidBatchNumber();
            }
        }
        getTotalBatchesExecuted += nBatches;
        if (getTotalBatchesExecuted > getTotalBatchesVerified) {
            revert DummyExecutorCannotExecuteBatchesMoreThanCommittedAndProvenCurrently();
        }
    }

    function executeBatchesSharedBridge(uint256, StoredBatchInfo[] calldata _batchesData) external {
        executeBatches(_batchesData);
    }

    function executeBatchesSharedBridge(
        uint256,
        StoredBatchInfo[] calldata _batchesData,
        PriorityOpsBatchInfo[] calldata
    ) external {
        executeBatches(_batchesData);
    }

    function revertBatchesSharedBridge(uint256, uint256 _newLastBatch) external {
        if (getTotalBatchesCommitted < _newLastBatch) {
            revert DummyExecutorTheLastCommittedBatchIsLessThanNewLastBatch();
        }
        uint256 newTotalBatchesCommitted = _maxU256(_newLastBatch, getTotalBatchesExecuted);

        if (newTotalBatchesCommitted < getTotalBatchesVerified) {
            getTotalBatchesVerified = newTotalBatchesCommitted;
        }
        getTotalBatchesCommitted = newTotalBatchesCommitted;
    }

    /// @notice Returns larger of two values
    function _maxU256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? b : a;
    }
}
