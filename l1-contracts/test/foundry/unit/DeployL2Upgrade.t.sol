pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {Utils, DEFAULT_L2_LOGS_TREE_ROOT_HASH} from "test/foundry/unit/concrete/Utils/Utils.sol";
import {Utils as Utils2} from "deploy-scripts/Utils.sol";
import {COMMIT_TIMESTAMP_NOT_OLDER, ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";
import {DummyEraBaseTokenBridge} from "contracts/dev-contracts/test/DummyEraBaseTokenBridge.sol";
import {DummyExecutor} from "contracts/dev-contracts/test/DummyExecutor.sol";
import {DummyStateTransitionManager} from "contracts/dev-contracts/test/DummyStateTransitionManager.sol";
import {IStateTransitionManager} from "contracts/state-transition/IStateTransitionManager.sol";
import {DiamondInit} from "contracts/state-transition/chain-deps/DiamondInit.sol";
import {DiamondProxy} from "contracts/state-transition/chain-deps/DiamondProxy.sol";
import {VerifierParams, FeeParams, PubdataPricingMode} from "contracts/state-transition/chain-deps/ZkSyncHyperchainStorage.sol";
import {ExecutorFacet} from "contracts/state-transition/chain-deps/facets/Executor.sol";
import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
import {AdminFacet} from "contracts/state-transition/chain-deps/facets/Admin.sol";
import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";
import {InitializeData} from "contracts/state-transition/chain-interfaces/IDiamondInit.sol";
import {IExecutor} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
import {Diamond} from "contracts/state-transition/libraries/Diamond.sol";
import {TestnetVerifier} from "contracts/state-transition/TestnetVerifier.sol"; 
import {ValidatorTimelock} from "contracts/state-transition/ValidatorTimelock.sol";

contract L2UpgradeTest is Test {

    struct CommitBatchInfoWithTimestamp {
        IExecutor.CommitBatchInfo batchInfo;
        uint256 timestamp;
    }

    uint256 internal chainId = 1;
    uint256 internal initialProtocolVersion = 0;
    uint256 internal SEMVER_MINOR_VERSION_MULTIPLIER = 4294967296;
    uint32 internal initialMajor;
    uint32 internal initialMinor; 
    uint32 internal initialPatch;

    address internal chainAdmin;
    address internal owner;
    address internal validator;
    address internal randomSigner;
    address internal blobVersionedHashRetriever;
    ValidatorTimelock internal validatorTimelock;
    AdminFacet internal admin;
    ExecutorFacet internal executor;
    GettersFacet internal getters;
    MailboxFacet internal mailbox;
    DiamondProxy internal diamondProxy;
    bytes32 internal newCommittedBlockBatchHash;
    bytes32 internal newCommittedBlockCommitment;
    uint256 internal currentTimestamp;
    IExecutor.CommitBatchInfo internal newCommitBatchInfo;
    IExecutor.StoredBatchInfo internal newStoredBatchInfo;
    DummyStateTransitionManager internal stateTransitionManager;
    DummyStateTransitionManager internal dummyStateTransitionManager;
    DummyExecutor internal dummyExecutor;

    uint256 eraChainId;

    IExecutor.StoredBatchInfo internal genesisStoredBatchInfo;
    IExecutor.ProofInput internal proofInput;

    function defaultFeeParams() private pure returns (FeeParams memory feeParams) {
        feeParams = FeeParams({
            pubdataPricingMode: PubdataPricingMode.Rollup,
            batchOverheadL1Gas: 1_000_000,
            maxPubdataPerBatch: 110_000,
            maxL2GasPerBatch: 80_000_000,
            priorityTxMaxPubdata: 99_000,
            minimalL2GasPrice: 250_000_000
        });
    }

    function packSemver(uint256 major, uint256 minor, uint256 patch) public returns (uint256) {
        if (major != 0) {
          revert("Major version must be 0");
        }
      
        return minor * SEMVER_MINOR_VERSION_MULTIPLIER + patch;
    }

    function getMockCommitBatchInfo(uint64 batchNumber) public returns (IExecutor.CommitBatchInfo[] memory) {
        bytes memory l2Logs = Utils.encodePacked(Utils.createSystemLogs());
        IExecutor.CommitBatchInfo[] memory commitBatches = new IExecutor.CommitBatchInfo[](1);
        commitBatches[0] = IExecutor.CommitBatchInfo({
            batchNumber: batchNumber,
            timestamp: 0,
            indexRepeatedStorageChanges: 0,
            newStateRoot: Utils.randomBytes32("newStateRoot"),
            numberOfLayer1Txs: 0,
            priorityOperationsHash: keccak256(""),
            bootloaderHeapInitialContentsHash: Utils.randomBytes32("bootloaderHeapInitialContentsHash"),
            eventsQueueStateHash: Utils.randomBytes32("eventsQueueStateHash"),
            systemLogs: l2Logs,
            pubdataCommitments: bytes("")
        });

        return commitBatches;
    }

    function getMockStoredBatchInfo(
    ) public returns (IExecutor.StoredBatchInfo[] memory) {
        IExecutor.StoredBatchInfo[] memory storedBatches = new IExecutor.StoredBatchInfo[](1);
        storedBatches[0] = IExecutor.StoredBatchInfo({
            batchNumber: 0,
            batchHash: "0x0000000000000000000000000000000000000000000000000000000000000001",
            indexRepeatedStorageChanges: 1,
            numberOfLayer1Txs: 0,
            priorityOperationsHash: keccak256(""),
            l2LogsTreeRoot: DEFAULT_L2_LOGS_TREE_ROOT_HASH,
            timestamp: 0,
            commitment:0x0000000000000000000000000000000000000000000000000000000000000001
        });
        return storedBatches;
    }

    function buildCommitBatchInfoWithUpgrade(
        IExecutor.StoredBatchInfo prevInfo,
        CommitBatchInfoWithTimestamp info,
        string upgradeTxHash
      ) public returns (CommitBatchInfo) {
        uint256 timestamp = info.timestamp;
        const systemLogs = createSystemLogsWithUpgrade(
          info.batchInfo.priorityOperationsHash,
          info.batchInfo.numberOfLayer1Txs,
          upgradeTxHash,
          bytes32(prevInfo.batchHash)
        );
        systemLogs[SYSTEM_LOG_KEYS.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY] = constructL2Log(
          true,
          L2_SYSTEM_CONTEXT_ADDRESS,
          SYSTEM_LOG_KEYS.PACKED_BATCH_AND_L2_BLOCK_TIMESTAMP_KEY,
          packBatchTimestampAndBatchTimestamp(timestamp, timestamp)
        );
    }
    
    function setUp() public {
        owner = makeAddr("owner");
        validator = makeAddr("validator");
        randomSigner = makeAddr("randomSigner");
        blobVersionedHashRetriever = makeAddr("blobVersionedHashRetriever");

        eraChainId = 9;

        executor = new ExecutorFacet();
        admin = new AdminFacet();
        getters = new GettersFacet();
        mailbox = new MailboxFacet(eraChainId);

        stateTransitionManager = new DummyStateTransitionManager();
        vm.mockCall(
            address(stateTransitionManager),
            abi.encodeWithSelector(IStateTransitionManager.protocolVersionIsActive.selector),
            abi.encode(bool(true))
        );

        (initialMajor, initialMinor, initialPatch) = getters.getSemverProtocolVersion();
        initialProtocolVersion = packSemver(initialMajor, initialMinor, initialPatch);

        DiamondInit diamondInit = new DiamondInit();

        bytes8 dummyHash = 0x1234567890123456;

        TestnetVerifier testnetVerifier = new TestnetVerifier();

        InitializeData memory params = InitializeData({
            // TODO REVIEW
            chainId: eraChainId,
            bridgehub: makeAddr("bridgehub"),
            stateTransitionManager: address(stateTransitionManager),
            protocolVersion: 0,
            admin: owner,
            validatorTimelock: validator,
            baseToken: ETH_TOKEN_ADDRESS,
            baseTokenBridge: address(new DummyEraBaseTokenBridge()),
            storedBatchZero: keccak256(abi.encode(genesisStoredBatchInfo)),
            verifier: IVerifier(testnetVerifier), // verifier
            verifierParams: VerifierParams({
                recursionNodeLevelVkHash: 0,
                recursionLeafLevelVkHash: 0,
                recursionCircuitsSetVksHash: 0
            }),
            l2BootloaderBytecodeHash: dummyHash,
            l2DefaultAccountBytecodeHash: dummyHash,
            priorityTxMaxGasLimit: 1000000,
            feeParams: defaultFeeParams(),
            blobVersionedHashRetriever: blobVersionedHashRetriever
        });

        bytes memory diamondInitData = abi.encodeWithSelector(diamondInit.initialize.selector, params);

        Diamond.FacetCut[] memory facetCuts = new Diamond.FacetCut[](4);
        facetCuts[0] = Diamond.FacetCut({
            facet: address(admin),
            action: Diamond.Action.Add,
            isFreezable: true,
            selectors: Utils2.getAllSelectors(address(admin).code)
        });
        facetCuts[1] = Diamond.FacetCut({
            facet: address(executor),
            action: Diamond.Action.Add,
            isFreezable: true,
            selectors: Utils2.getAllSelectors(address(executor).code)
        });
        facetCuts[2] = Diamond.FacetCut({
            facet: address(getters),
            action: Diamond.Action.Add,
            isFreezable: false,
            selectors: Utils2.getAllSelectors(address(getters).code)
        });
        facetCuts[3] = Diamond.FacetCut({
            facet: address(mailbox),
            action: Diamond.Action.Add,
            isFreezable: true,
            selectors: Utils2.getAllSelectors(address(mailbox).code)
        });

        Diamond.DiamondCutData memory diamondCutData = Diamond.DiamondCutData({
            facetCuts: facetCuts,
            initAddress: address(diamondInit),
            initCalldata: diamondInitData
        });

        chainId = block.chainid;
        diamondProxy = new DiamondProxy(chainId, diamondCutData);
        validatorTimelock = new ValidatorTimelock(owner, 0, chainId);

        executor = ExecutorFacet(address(diamondProxy));
        getters = GettersFacet(address(diamondProxy));
        mailbox = MailboxFacet(address(diamondProxy));
        admin = AdminFacet(address(diamondProxy));

        // Initiate the token multiplier to enable L1 -> L2 transactions.
        vm.prank(address(stateTransitionManager));
        admin.setTokenMultiplier(1, 1);

        uint32 upgradeTxHash = getters.getL2SystemContractsUpgradeTxHash();
        IExecutor.CommitBatchInfo batch1InfoChainIdUpgrade = await buildCommitBatchInfoWithUpgrade(
        genesisStoredBatchInfo(),
        {
            batchNumber: 1,
            priorityOperationsHash: EMPTY_STRING_KECCAK,
            numberOfLayer1Txs: "0x0000000000000000000000000000000000000000000000000000000000000000",
        },
        upgradeTxHash
        );

        const commitReceipt = await (
            await proxyExecutor.commitBatches(genesisStoredBatchInfo(), [batch1InfoChainIdUpgrade])
        ).wait();
        const commitment = commitReceipt.events[0].args.commitment;
        storedBatch1InfoChainIdUpgrade = getBatchStoredInfo(batch1InfoChainIdUpgrade, commitment);
        await makeExecutedEqualCommitted(proxyExecutor, genesisStoredBatchInfo(), [storedBatch1InfoChainIdUpgrade], []);

        uint256[] memory recursiveAggregationInput;
        uint256[] memory serializedProof;
        proofInput = IExecutor.ProofInput(recursiveAggregationInput, serializedProof);

        vm.startBroadcast(owner);
        dummyExecutor = new DummyExecutor();
        vm.stopBroadcast();

        vm.startBroadcast(owner);
        dummyStateTransitionManager = new DummyStateTransitionManager();
        vm.stopBroadcast();

        validatorTimelock = new ValidatorTimelock(owner, 0, chainId);

        vm.startBroadcast(owner);
        validatorTimelock.setStateTransitionManager(dummyStateTransitionManager);
        vm.stopBroadcast();

        dummyStateTransitionManager.setHyperchain(chainId, address(dummyExecutor));

        chainAdmin = dummyStateTransitionManager.getChainAdmin(chainId);
    }

    function test_notAllBatchesAreProcessed() public {
        IExecutor.StoredBatchInfo[] memory storedBatch = getMockStoredBatchInfo(0, 0);

        vm.startBroadcast(chainAdmin);
        validatorTimelock.addValidator(chainId, validator);
        vm.stopBroadcast();
    
        vm.startBroadcast(validator);
        executor.commitBatches(storedBatch[0], getMockCommitBatchInfo(0));
        vm.stopBroadcast();
        // const commitment = commitReceipt.events[0].args.commitment;
    
        assertEq(getters.getProtocolVersion(), initialProtocolVersion);
        assertEq(getters.getL2SystemContractsUpgradeTxHash(), bytes32(""));
        // assertEq(proxyGetters.getProtocolVersion()).to.equal(addToProtocolVersion(initialProtocolVersion, 1, 0));
    }
}