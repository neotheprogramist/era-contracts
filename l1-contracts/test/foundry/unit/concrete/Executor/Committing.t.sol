// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Test.sol";
import {Utils, L2_BOOTLOADER_ADDRESS, L2_SYSTEM_CONTEXT_ADDRESS, DEFAULT_L2_LOGS_TREE_ROOT_HASH} from "../Utils/Utils.sol";
import {ExecutorTest} from "./_Executor_Shared.t.sol";
import {VerifierParams, FeeParams, PubdataPricingMode} from "contracts/state-transition/chain-deps/ZkSyncHyperchainStorage.sol";
import {IExecutor, MAX_NUMBER_OF_BLOBS, PubdataSource, BLOB_SIZE_BYTES} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
import {SystemLogKey} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
import {POINT_EVALUATION_PRECOMPILE_ADDR} from "contracts/common/Config.sol";
import {L2_PUBDATA_CHUNK_PUBLISHER_ADDR, L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR} from "contracts/common/L2ContractAddresses.sol";
import {IStateTransitionManager} from "contracts/state-transition/IStateTransitionManager.sol";

contract CommittingTest is ExecutorTest {
    function test_revertWhen_wrongCaller(address randomCaller) public {
        if (randomCaller != validator) {
            IExecutor.CommitBatchInfo[] memory newCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
            newCommitBatchInfoArray[0] = newCommitBatchInfo;

            vm.prank(randomCaller);
            vm.expectRevert("Hyperchain: not validator");
            executor.commitBatches(genesisStoredBatchInfo, newCommitBatchInfoArray);
        }
    }

    function test_RevertWhen_wrongProtocolVersion() public {
        IExecutor.CommitBatchInfo[] memory newCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        newCommitBatchInfoArray[0] = newCommitBatchInfo;

        vm.mockCall(
            stmAddress,
            abi.encodeWithSelector(IStateTransitionManager.protocolVersionIsActive.selector),
            abi.encode(bool(false))
        );

        vm.prank(validator);
        vm.expectRevert("Executor facet: wrong protocol version");
        executor.commitBatches(genesisStoredBatchInfo, newCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithWrongLastCommittedBatchData() public {
        IExecutor.CommitBatchInfo[] memory newCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        newCommitBatchInfoArray[0] = newCommitBatchInfo;

        IExecutor.StoredBatchInfo memory wrongGenesisStoredBatchInfo = genesisStoredBatchInfo;
        wrongGenesisStoredBatchInfo.timestamp = 1000;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("i"));
        executor.commitBatches(wrongGenesisStoredBatchInfo, newCommitBatchInfoArray);
    }

    function test_RevertWhen_wrongPubdataSource(uint8 pubdataSource) public {
        vm.assume(pubdataSource != uint8(PubdataSource.Blob) && pubdataSource != uint8(PubdataSource.Calldata));

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.batchNumber = 1;
        wrongNewCommitBatchInfo.pubdataCommitments[0] = bytes1(pubdataSource);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("us"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithWrongOrderOfBatches() public {
        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.batchNumber = 2; // wrong batch number

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("f"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithWrongNewBatchTimestamp() public {
        bytes32 wrongNewBatchTimestamp = Utils.randomBytes32("wrongNewBatchTimestamp");
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();

        wrongL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            wrongNewBatchTimestamp
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("tb"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithTooSmallNewBatchTimestamp() public {
        uint256 wrongNewBatchTimestamp = 1;
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(1, 1)
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);
        wrongNewCommitBatchInfo.timestamp = uint64(wrongNewBatchTimestamp);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("h1"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_previousTimestampWrong() public {
        IExecutor.StoredBatchInfo memory someStoredBatchInfo = IExecutor.StoredBatchInfo({
            batchNumber: 1,
            batchHash: bytes32(""),
            indexRepeatedStorageChanges: 0,
            numberOfLayer1Txs: 0,
            priorityOperationsHash: keccak256(""),
            l2LogsTreeRoot: DEFAULT_L2_LOGS_TREE_ROOT_HASH,
            timestamp: 101,
            commitment: bytes32("")
        });

        bytes32 _storedBatchHash = keccak256(abi.encode(someStoredBatchInfo));
        utils.util_setStoredBatchHashes(1, _storedBatchHash);
        utils.util_setTotalBatchesCommitted(1);

        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(100, 100)
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);
        wrongNewCommitBatchInfo.timestamp = uint64(100);
        wrongNewCommitBatchInfo.batchNumber = 2;

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("h3"));
        executor.commitBatches(someStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingTooBigLastL2BatchTimestamp() public {
        uint64 wrongNewBatchTimestamp = 0xffffffff;
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(wrongNewBatchTimestamp, wrongNewBatchTimestamp)
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);
        wrongNewCommitBatchInfo.timestamp = wrongNewBatchTimestamp;

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("h2"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_validiumDataWrongCommitmentsLength() public {
        FeeParams memory feeParams = defaultFeeParams();
        feeParams.pubdataPricingMode = PubdataPricingMode.Validium;
        utils.util_setFeeParams(feeParams);

        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);
        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("EF: v0l"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_tooLongPubdataCommitment() public {
        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.batchNumber = 1;
        bytes memory pubdataCommitment = new bytes(BLOB_SIZE_BYTES + 1);
        wrongNewCommitBatchInfo.pubdataCommitments = pubdataCommitment;
        wrongNewCommitBatchInfo.pubdataCommitments[0] = bytes1(uint8(PubdataSource.Calldata));

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("cz"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function hashSlice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes32) {
        bytes memory slice = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            slice[i - start] = data[i];
        }
        return keccak256(slice);
    }

    function test_RevertWhen_pubdataHashAndCommitmentMissmatch() public {
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        bytes memory pubdataCommitment = new bytes(64);
        bytes32 pubdataCommitmentHash = hashSlice(pubdataCommitment, 1, pubdataCommitment.length - 32);
        wrongL2Logs[uint256(uint256(SystemLogKey.TOTAL_L2_TO_L1_PUBDATA_KEY))] = Utils.constructL2Log(
            true,
            L2_TO_L1_MESSENGER_SYSTEM_CONTRACT_ADDR,
            uint256(SystemLogKey.TOTAL_L2_TO_L1_PUBDATA_KEY),
            bytes32("")
        );
        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.batchNumber = 1;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);
        wrongNewCommitBatchInfo.pubdataCommitments = pubdataCommitment;
        wrongNewCommitBatchInfo.pubdataCommitments[0] = bytes1(uint8(PubdataSource.Calldata));

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("wp"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithWrongPreviousBatchHash() public {
        bytes32 wrongPreviousBatchHash = Utils.randomBytes32("wrongPreviousBatchHash");
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.PREV_BATCH_HASH_KEY))] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PREV_BATCH_HASH_KEY),
            wrongPreviousBatchHash
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("l"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithoutProcessingSystemContextLog() public {
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        delete wrongL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))];

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("b7"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithProcessingSystemContextLogTwice() public {
        bytes[] memory l2Logs = Utils.createSystemLogs();

        bytes memory wrongL2Logs = abi.encodePacked(
            Utils.encodePacked(l2Logs),
            // solhint-disable-next-line func-named-parameters
            Utils.constructL2Log(
                true,
                L2_SYSTEM_CONTEXT_ADDRESS,
                uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
                bytes32("")
            )
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = wrongL2Logs;

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("kp"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_UnexpectedL2ToL1Log() public {
        address unexpectedAddress = address(0);
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY))] = Utils.constructL2Log(
            true,
            unexpectedAddress,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            bytes32("")
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("sc"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithWrongCanonicalTxHash() public {
        bytes32 wrongChainedPriorityHash = Utils.randomBytes32("canonicalTxHash");
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.CHAINED_PRIORITY_TXN_HASH_KEY))] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            uint256(SystemLogKey.CHAINED_PRIORITY_TXN_HASH_KEY),
            wrongChainedPriorityHash
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("t"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithWrongNumberOfLayer1txs() public {
        bytes[] memory wrongL2Logs = Utils.createSystemLogs();
        wrongL2Logs[uint256(uint256(SystemLogKey.NUMBER_OF_LAYER_1_TXS_KEY))] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            uint256(SystemLogKey.NUMBER_OF_LAYER_1_TXS_KEY),
            bytes32(bytes1(0x01))
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(wrongL2Logs);
        wrongNewCommitBatchInfo.numberOfLayer1Txs = 2;

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("ta"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_CommittingWithUnknownSystemLogKey() public {
        bytes[] memory l2Logs = Utils.createSystemLogs();
        bytes memory wrongL2Logs = abi.encodePacked(
            Utils.encodePacked(l2Logs),
            // solhint-disable-next-line func-named-parameters
            abi.encodePacked(bytes2(0x0001), bytes2(0x0000), L2_SYSTEM_CONTEXT_ADDRESS, uint256(119), bytes32(""))
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = abi.encodePacked(bytes4(0x00000008), wrongL2Logs);

        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes.concat("ul"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function _getCommitInfoWithLogs(bytes[] memory logs) internal returns (IExecutor.CommitBatchInfo[] memory) {
        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(logs);
        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        return wrongNewCommitBatchInfoArray;
    }

    function test_RevertWhen_SystemLogIsFromIncorrectAddress() public {
        bytes32[15] memory values = [
            bytes32(""),
            bytes32(0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            keccak256(""),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            bytes32(""),
            bytes32("")
        ];

        bytes[15] memory errors = [
            bytes.concat("lm"),
            bytes.concat("ln"),
            bytes.concat("lb"),
            bytes.concat("sc"),
            bytes.concat("sv"),
            bytes.concat("bl"),
            bytes.concat("bk"),
            bytes.concat("pc"),
            bytes.concat("pc"),
            bytes.concat("pc"),
            bytes.concat("pc"),
            bytes.concat("pc"),
            bytes.concat("pc"),
            bytes.concat("bu"),
            bytes.concat("ul")
        ];

        address wrongAddress = makeAddr("randomAddress");

        for (uint256 i = 0; i < values.length; i++) {
            bytes[] memory wrongL2Logs = Utils.createSystemLogsWithUpgradeTransaction(bytes32(""));
            bytes[] memory tooManyLogs = new bytes[](15);

            for (uint256 i = 0; i < wrongL2Logs.length; i++) {
                tooManyLogs[i] = wrongL2Logs[i];
            }

            tooManyLogs[i] = Utils.constructL2Log(true, wrongAddress, i, values[i]);

            IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
            wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(tooManyLogs);
            IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
            wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

            vm.prank(validator);
            vm.expectRevert(errors[i]);
            executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
        }

        bytes[] memory logsWithWrongHash = Utils.createSystemLogsWithUpgradeTransaction(bytes32(""));
        logsWithWrongHash[logsWithWrongHash.length - 1] = Utils.constructL2Log(
            true,
            L2_BOOTLOADER_ADDRESS,
            logsWithWrongHash.length - 1,
            bytes32("1")
        );

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(logsWithWrongHash);
        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("ut"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_systemLogsBadLength() public {
        utils.util_setL2SystemContractsUpgradeTxHash(bytes32("not default"));
        bytes[] memory logs = Utils.createSystemLogsWithUpgradeTransaction(bytes32("not default"));
        delete logs[0];

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(logs);
        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("b8"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_RevertWhen_SystemLogIsMissing() public {
        bytes[] memory logs = Utils.createSystemLogs();
        delete logs[0];

        IExecutor.CommitBatchInfo memory wrongNewCommitBatchInfo = newCommitBatchInfo;
        wrongNewCommitBatchInfo.systemLogs = Utils.encodePacked(logs);
        IExecutor.CommitBatchInfo[] memory wrongNewCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        wrongNewCommitBatchInfoArray[0] = wrongNewCommitBatchInfo;

        vm.prank(validator);
        vm.expectRevert(bytes.concat("b7"));
        executor.commitBatches(genesisStoredBatchInfo, wrongNewCommitBatchInfoArray);
    }

    function test_successfullyCommitBatchWithSystemUpgrade() public {
        // upgrade batch number must be zero to proceed
        utils.util_setL2SystemContractsUpgradeBatchNumber(0);
        // upgrade tx hash must be non zero to proceed
        utils.util_setL2SystemContractsUpgradeTxHash(bytes32("not default"));

        // first new batch logs must contain upgrade transaction
        // ugrade batch number will be batch number of this batch
        bytes[] memory upgradeLogs = Utils.createSystemLogsWithUpgradeTransaction(bytes32("not default"));
        uint64 upgradeBatchNumber = 1;

        upgradeLogs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );
        upgradeLogs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563
        );

        IExecutor.CommitBatchInfo memory upgradeBatch = newCommitBatchInfo;
        upgradeBatch.batchNumber = upgradeBatchNumber;
        upgradeBatch.systemLogs = Utils.encodePacked(upgradeLogs);
        upgradeBatch.pubdataCommitments = abi.encodePacked(
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
            bytes32(uint256(0xbeef))
        );

        bytes32[] memory blobHashes = new bytes32[](MAX_NUMBER_OF_BLOBS);
        blobHashes[0] = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

        bytes32[] memory blobCommitments = new bytes32[](MAX_NUMBER_OF_BLOBS);
        blobCommitments[0] = bytes32(uint256(0xbeef));

        bytes32 expectedBatchCommitment = Utils.createBatchCommitment(
            upgradeBatch,
            bytes32(""),
            blobCommitments,
            blobHashes
        );

        IExecutor.CommitBatchInfo[] memory batchInfoArray = new IExecutor.CommitBatchInfo[](1);
        batchInfoArray[0] = upgradeBatch;

        vm.prank(validator);
        // solhint-disable-next-line func-named-parameters
        vm.expectEmit(true, true, true, true, address(executor));
        emit BlockCommit(1, upgradeBatch.newStateRoot, expectedBatchCommitment);
        executor.commitBatches(genesisStoredBatchInfo, batchInfoArray);

        assertEq(getters.getTotalBatchesCommitted(), 1);
        assertEq(getters.getL2SystemContractsUpgradeBatchNumber(), upgradeBatchNumber);
        assertEq(getters.getL2SystemContractsUpgradeTxHash(), bytes32("not default"));

        IExecutor.StoredBatchInfo memory lastBatch = IExecutor.StoredBatchInfo({
            batchNumber: 1,
            batchHash: Utils.randomBytes32("newStateRoot"),
            indexRepeatedStorageChanges: 0,
            numberOfLayer1Txs: 0,
            priorityOperationsHash: keccak256(""),
            l2LogsTreeRoot: DEFAULT_L2_LOGS_TREE_ROOT_HASH,
            timestamp: currentTimestamp,
            commitment: expectedBatchCommitment
        });

        assertEq(utils.util_getStoredBatchHashes(1), keccak256(abi.encode(lastBatch)));

        batchInfoArray[0].batchNumber += 1;

        // this proves that upgrade batch number is not zero in second call
        // and it doesn't go through branch with upgrade
        vm.expectRevert(bytes.concat("ut"));
        vm.prank(validator);
        executor.commitBatches(lastBatch, batchInfoArray);
    }

    function test_SuccessfullyCommitBatch() public {
        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );
        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);
        correctNewCommitBatchInfo.pubdataCommitments = abi.encodePacked(
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
            bytes32(uint256(0xbeef))
        );

        bytes32[] memory blobHashes = new bytes32[](MAX_NUMBER_OF_BLOBS);
        blobHashes[0] = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

        bytes32[] memory blobCommitments = new bytes32[](MAX_NUMBER_OF_BLOBS);
        blobCommitments[0] = bytes32(uint256(0xbeef));

        bytes32 expectedBatchCommitment = Utils.createBatchCommitment(
            correctNewCommitBatchInfo,
            bytes32(""),
            blobCommitments,
            blobHashes
        );

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;

        vm.prank(validator);
        // solhint-disable-next-line func-named-parameters
        vm.expectEmit(true, true, true, true, address(executor));
        emit BlockCommit(1, correctNewCommitBatchInfo.newStateRoot, expectedBatchCommitment);

        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);
        assertEq(getters.getTotalBatchesCommitted(), 1);
    }

    function test_SuccessfullyCommitBatchWithOneBlob() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(1)), abi.encode(bytes32(0)));

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\xf3\x9a\x86\x9f\x62\xe7\x5c\xf5\xf0\xbf\x91\x46\x88\xa6\xb2\x89\xca\xf2\x04\x94\x35\xd8\xe6\x8c\x5c\x5e\x6d\x05\xe4\x49\x13\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);
        vm.expectEmit(true, false, false, false, address(executor));
        emit BlockCommit(1, bytes32(0), bytes32(0));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);

        uint256 totalBatchesCommitted = getters.getTotalBatchesCommitted();
        assertEq(totalBatchesCommitted, 1);

        vm.clearMockedCalls();
    }

    function test_SuccessfullyCommitBatchWithTwoBlob() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;
        bytes32 versionedHash2 = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(1)), abi.encode(versionedHash2));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(2)), abi.encode(bytes32(0)));

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\xf3\x9a\x86\x9f\x62\xe7\x5c\xf5\xf0\xbf\x91\x46\x88\xa6\xb2\x89\xca\xf2\x04\x94\x35\xd8\xe6\x8c\x5c\x5e\x6d\x05\xe4\x49\x13\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\x29\x0d\xec\xd9\x54\x8b\x62\xa8\xd6\x03\x45\xa9\x88\x38\x6f\xc8\x4b\xa6\xbc\x95\x48\x40\x08\xf6\x36\x2f\x93\x16\x0e\xf3\xe5\x63\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_TWO_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_TWO_HASH_KEY),
            versionedHash2
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);
        // solhint-disable-next-line func-named-parameters
        vm.expectEmit(true, false, false, false, address(executor));
        emit BlockCommit(1, bytes32(0), bytes32(0));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);

        assertEq(getters.getTotalBatchesCommitted(), 1);
        vm.clearMockedCalls();
    }

    function test_RevertWhen_CommittingBatchMoreThanOneBatch() public {
        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](2);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[1] = correctNewCommitBatchInfo;

        vm.prank(validator);

        vm.expectRevert(bytes("e4"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);
    }

    function test_RevertWhen_EmptyPubdataCommitments() public {
        bytes memory pubdataCommitment = "\x01";

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("pl"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);
    }

    function test_RevertWhen_PartialPubdataCommitment() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57";

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("bs"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);
    }

    function test_RevertWhen_TooManyPubdataCommitments() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("bd"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);
    }

    function test_RevertWhen_NotEnoughPubdataCommitments() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;
        bytes32 versionedHash2 = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(1)), abi.encode(versionedHash2));

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\xf3\x9a\x86\x9f\x62\xe7\x5c\xf5\xf0\xbf\x91\x46\x88\xa6\xb2\x89\xca\xf2\x04\x94\x35\xd8\xe6\x8c\x5c\x5e\x6d\x05\xe4\x49\x13\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("lh"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);

        vm.clearMockedCalls();
    }

    function test_RevertWhen_BlobDoesNotExist() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(bytes32(0)));

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("vh"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);

        vm.clearMockedCalls();
    }

    function test_RevertWhen_SecondBlobSentWithoutCommitmentData() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(1)), abi.encode(versionedHash1));

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\xf3\x9a\x86\x9f\x62\xe7\x5c\xf5\xf0\xbf\x91\x46\x88\xa6\xb2\x89\xca\xf2\x04\x94\x35\xd8\xe6\x8c\x5c\x5e\x6d\x05\xe4\x49\x13\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("lh"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);

        vm.clearMockedCalls();
    }

    function test_RevertWhen_SecondBlobLinearHashZeroWithCommitment() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;
        bytes32 versionedHash2 = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(1)), abi.encode(versionedHash2));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(2)), abi.encode(bytes32(0)));

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\xf3\x9a\x86\x9f\x62\xe7\x5c\xf5\xf0\xbf\x91\x46\x88\xa6\xb2\x89\xca\xf2\x04\x94\x35\xd8\xe6\x8c\x5c\x5e\x6d\x05\xe4\x49\x13\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\x29\x0d\xec\xd9\x54\x8b\x62\xa8\xd6\x03\x45\xa9\x88\x38\x6f\xc8\x4b\xa6\xbc\x95\x48\x40\x08\xf6\x36\x2f\x93\x16\x0e\xf3\xe5\x63\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_TWO_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_TWO_HASH_KEY),
            bytes32(0)
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("bh"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);
    }

    function test_RevertWhen_SecondBlobLinearHashNotZeroWithEmptyCommitment() public {
        bytes
            memory pubdataCommitment = "\x01\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2";
        bytes32 versionedHash1 = 0xf39a869f62e75cf5f0bf914688a6b289caf2049435d8e68c5c5e6d05e44913f3;

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(0)), abi.encode(versionedHash1));

        vm.mockCall(blobVersionedHashRetriever, abi.encode(uint256(1)), abi.encode(bytes32(0)));

        vm.mockCall(
            POINT_EVALUATION_PRECOMPILE_ADDR,
            "\xf3\x9a\x86\x9f\x62\xe7\x5c\xf5\xf0\xbf\x91\x46\x88\xa6\xb2\x89\xca\xf2\x04\x94\x35\xd8\xe6\x8c\x5c\x5e\x6d\x05\xe4\x49\x13\xf3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf4\x3d\x53\x8d\x91\xd4\x77\xb0\xf8\xf7\x7e\x19\x52\x48\x7f\x00\xb8\xdf\x41\xda\x90\x5c\x08\x75\xc5\xc9\x9b\xa1\x92\x26\x84\x0d\x0d\x0a\x25\x26\xee\x22\xc7\x96\x60\x65\x7c\xbe\x01\x95\x33\x5b\x44\x69\xbd\x92\x94\x6f\x7f\x74\xae\xc5\xce\xef\x31\xf4\x32\x53\xd4\x08\x96\x72\x65\xfa\x85\x5a\xc8\xa0\x0a\x19\x52\x93\x6e\x0f\xe9\x97\x01\xc0\xa4\x32\xa1\x32\x2c\x45\x67\x24\xf7\xad\xd8\xa5\xb4\x7a\x51\xda\x52\x17\x06\x06\x95\x34\x61\xab\xd7\x5b\x91\x49\xc7\xc7\x91\xf4\x07\xfd\xbc\xf8\x39\x53\x2c\xb1\x08\xe8\xa5\x00\x64\x40\xcf\x21\xbf\x68\x87\x20\x5a\xcf\x44\x3b\x66\x3a\x57\xf2",
            "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x73\xed\xa7\x53\x29\x9d\x7d\x48\x33\x39\xd8\x08\x09\xa1\xd8\x05\x53\xbd\xa4\x02\xff\xfe\x5b\xfe\xff\xff\xff\xff\x00\x00\x00\x01"
        );

        bytes[] memory correctL2Logs = Utils.createSystemLogs();
        correctL2Logs[uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY)] = Utils.constructL2Log(
            true,
            L2_SYSTEM_CONTEXT_ADDRESS,
            uint256(SystemLogKey.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY),
            Utils.packBatchTimestampAndBlockTimestamp(currentTimestamp, currentTimestamp)
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_ONE_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_ONE_HASH_KEY),
            versionedHash1
        );

        correctL2Logs[uint256(SystemLogKey.BLOB_TWO_HASH_KEY)] = Utils.constructL2Log(
            true,
            L2_PUBDATA_CHUNK_PUBLISHER_ADDR,
            uint256(SystemLogKey.BLOB_TWO_HASH_KEY),
            versionedHash1
        );

        IExecutor.CommitBatchInfo memory correctNewCommitBatchInfo = newCommitBatchInfo;
        correctNewCommitBatchInfo.systemLogs = Utils.encodePacked(correctL2Logs);

        IExecutor.CommitBatchInfo[] memory correctCommitBatchInfoArray = new IExecutor.CommitBatchInfo[](1);
        correctCommitBatchInfoArray[0] = correctNewCommitBatchInfo;
        correctCommitBatchInfoArray[0].pubdataCommitments = pubdataCommitment;

        vm.prank(validator);

        vm.expectRevert(bytes("bh"));
        executor.commitBatches(genesisStoredBatchInfo, correctCommitBatchInfoArray);

        vm.clearMockedCalls();
    }
}
