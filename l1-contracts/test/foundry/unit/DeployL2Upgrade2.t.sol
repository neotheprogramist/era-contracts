// pragma solidity 0.8.24;

// import {Test} from "forge-std/Test.sol";

// import {Utils, DEFAULT_L2_LOGS_TREE_ROOT_HASH} from "test/foundry/unit/concrete/Utils/Utils.sol";
// import {Utils as Utils2} from "deploy-scripts/Utils.sol";
// import {console2 as console} from "forge-std/Script.sol";
// import {COMMIT_TIMESTAMP_NOT_OLDER, ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";
// import {DummyEraBaseTokenBridge} from "contracts/dev-contracts/test/DummyEraBaseTokenBridge.sol";
// import {DummyExecutor} from "contracts/dev-contracts/test/DummyExecutor.sol";
// import {DummyStateTransitionManager} from "contracts/dev-contracts/test/DummyStateTransitionManager.sol";
// import {DummyAdminFacet} from "contracts/dev-contracts/test/DummyAdminFacet.sol";
// import {IStateTransitionManager} from "contracts/state-transition/IStateTransitionManager.sol";
// import {DiamondInit} from "contracts/state-transition/chain-deps/DiamondInit.sol";
// import {DiamondProxy} from "contracts/state-transition/chain-deps/DiamondProxy.sol";
// import {VerifierParams, FeeParams, PubdataPricingMode} from "contracts/state-transition/chain-deps/ZkSyncHyperchainStorage.sol";
// import {ExecutorFacet} from "contracts/state-transition/chain-deps/facets/Executor.sol";
// import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
// import {AdminFacet} from "contracts/state-transition/chain-deps/facets/Admin.sol";
// import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";
// import {InitializeData} from "contracts/state-transition/chain-interfaces/IDiamondInit.sol";
// import {IExecutor} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
// import {IVerifier} from "contracts/state-transition/chain-interfaces/IVerifier.sol";
// import {Diamond} from "contracts/state-transition/libraries/Diamond.sol";
// import {TestnetVerifier} from "contracts/state-transition/TestnetVerifier.sol"; 
// import {ValidatorTimelock} from "contracts/state-transition/ValidatorTimelock.sol";

// contract L2UpgradeTest2 is Test {

//     struct CommitBatchInfoWithTimestamp {
//         uint64 batchNumber;
//         uint64 timestamp;
//     }

//     uint256 internal chainId = 1;
//     uint256 internal initialProtocolVersion = 0;
//     uint256 internal SEMVER_MINOR_VERSION_MULTIPLIER = 4294967296;
//     uint32 internal initialMajor;
//     uint32 internal initialMinor; 
//     uint32 internal initialPatch;
//     uint32 internal initialMinorProtocolVersion;

//     address internal chainAdmin;
//     address internal owner;
//     address internal validator;
//     address internal randomSigner;
//     address internal blobVersionedHashRetriever;
//     ValidatorTimelock internal validatorTimelock;
//     AdminFacet internal admin;
//     ExecutorFacet internal executor;
//     GettersFacet internal getters;
//     MailboxFacet internal mailbox;
//     DiamondProxy internal diamondProxy;
//     bytes32 internal newCommittedBlockBatchHash;
//     bytes32 internal newCommittedBlockCommitment;
//     uint64 internal timestamp;
//     IExecutor.CommitBatchInfo internal newCommitBatchInfo;
//     IExecutor.StoredBatchInfo internal newStoredBatchInfo;
//     DummyStateTransitionManager internal stateTransitionManager;
//     DummyStateTransitionManager internal dummyStateTransitionManager;
//     DummyExecutor internal dummyExecutor;
//     DummyAdminFacet internal dummyAdmin;

//     uint256 eraChainId;

//     IExecutor.StoredBatchInfo internal genesisBatchInfo;
//     IExecutor.ProofInput internal proofInput;

//     function genesisStoredBatchInfo() public returns (IExecutor.StoredBatchInfo memory) {
//         IExecutor.StoredBatchInfo[] memory genesisStoredBatch= new IExecutor.StoredBatchInfo[](1);
//         genesisStoredBatch[0] = IExecutor.StoredBatchInfo({
//             batchNumber: 0,
//             batchHash: 0x0000000000000000000000000000000000000000000000000000000000000001,
//             indexRepeatedStorageChanges: 1,
//             numberOfLayer1Txs: 0,
//             priorityOperationsHash: 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,
//             l2LogsTreeRoot: 0x0000000000000000000000000000000000000000000000000000000000000000,
//             timestamp: 0,
//             commitment: 0x0000000000000000000000000000000000000000000000000000000000000001
//           });
//         return genesisStoredBatch[0];
//     }

//     function buildCommitBatchInfo(
//         IExecutor.StoredBatchInfo memory prevInfo,
//         CommitBatchInfoWithTimestamp memory info 
//       ) public returns (IExecutor.CommitBatchInfo memory) {
//         uint64 batchTimestamp = info.timestamp; 
//         bytes memory systemLogs = "0x000100000000000000000000000000000000000000008008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000080080000000000000000000000000000000000000000000000000000000000000001290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e5630001000000000000000000000000000000000000000080080000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000800b0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000669a1c64000000000000000000000000669a1c6400010000000000000000000000000000000000000000800b00000000000000000000000000000000000000000000000000000000000000047d7451a10cde81e6f7933605ded0d6d9b402287f48333d748a6730a0a0336c230001000000000000000000000000000000000000000080010000000000000000000000000000000000000000000000000000000000000005c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a47000010000000000000000000000000000000000000000800100000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000080110000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000801100000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000b0000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000";
     
//         IExecutor.CommitBatchInfo[] memory commitBuild = new IExecutor.CommitBatchInfo[](1);
//         commitBuild[0] = IExecutor.CommitBatchInfo({
//             batchNumber: info.batchNumber,
//             timestamp: batchTimestamp,
//             indexRepeatedStorageChanges: 0,
//             newStateRoot: Utils.randomBytes32(""),
//             numberOfLayer1Txs: 0,
//             priorityOperationsHash: 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,
//             systemLogs: systemLogs,
//             pubdataCommitments: "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
//             bootloaderHeapInitialContentsHash: Utils.randomBytes32(""),
//             eventsQueueStateHash: Utils.randomBytes32("")
//         });
//         return commitBuild[0];
//     }

//     function buildCommitBatchInfoWithUpgrade(
//         IExecutor.StoredBatchInfo memory prevInfo,
//         CommitBatchInfoWithTimestamp memory info, 
//         bytes32 upgradeTxHash 
//       ) public returns (IExecutor.CommitBatchInfo memory)  {
//         uint64 batchTimestamp = info.timestamp;
//         bytes memory systemLogs = "0x000100000000000000000000000000000000000000008008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000080080000000000000000000000000000000000000000000000000000000000000001290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e5630001000000000000000000000000000000000000000080080000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000800b0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000669a1c64000000000000000000000000669a1c6400010000000000000000000000000000000000000000800b00000000000000000000000000000000000000000000000000000000000000047d7451a10cde81e6f7933605ded0d6d9b402287f48333d748a6730a0a0336c230001000000000000000000000000000000000000000080010000000000000000000000000000000000000000000000000000000000000005c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a47000010000000000000000000000000000000000000000800100000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000080110000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000801100000000000000000000000000000000000000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000b0000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000008011000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000"; 
      
//         IExecutor.CommitBatchInfo[] memory commitBuildUpgrade = new IExecutor.CommitBatchInfo[](1);
//         commitBuildUpgrade[0] = IExecutor.CommitBatchInfo({
//             batchNumber: info.batchNumber,
//             timestamp: batchTimestamp,
//             indexRepeatedStorageChanges: 1,
//             newStateRoot: Utils.randomBytes32(""),
//             numberOfLayer1Txs: 0,
//             priorityOperationsHash: 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,
//             systemLogs: systemLogs,
//             pubdataCommitments: "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
//             bootloaderHeapInitialContentsHash: Utils.randomBytes32(""),
//             eventsQueueStateHash: Utils.randomBytes32("")
//         });
//         return commitBuildUpgrade[0];
//     }

//     function packSemver(uint256 major, uint256 minor, uint256 patch) public returns (uint256) {
//         if (major != 0) {
//           revert("Major version must be 0");
//         }
      
//         return minor * SEMVER_MINOR_VERSION_MULTIPLIER + patch;
//     }

//     function defaultFeeParams() private pure returns (FeeParams memory feeParams) {
//         feeParams = FeeParams({
//             pubdataPricingMode: PubdataPricingMode.Rollup,
//             batchOverheadL1Gas: 1_000_000,
//             maxPubdataPerBatch: 110_000,
//             maxL2GasPerBatch: 80_000_000,
//             priorityTxMaxPubdata: 99_000,
//             minimalL2GasPrice: 250_000_000
//         });
//     }

//     function setUp() public {
//         owner = makeAddr("owner");
//         blobVersionedHashRetriever = makeAddr("blobVersionedHashRetriever");
//         validator = makeAddr("validator");
//         timestamp = 1721375844;
//         eraChainId = 9;

//         dummyAdmin = new DummyAdminFacet();
//         executor = new ExecutorFacet();
//         admin = new AdminFacet();
//         getters = new GettersFacet();
//         mailbox = new MailboxFacet(eraChainId);
//         stateTransitionManager = new DummyStateTransitionManager();
//         TestnetVerifier testnetVerifier = new TestnetVerifier();

//         vm.mockCall(
//             address(stateTransitionManager),
//             abi.encodeWithSelector(IStateTransitionManager.protocolVersionIsActive.selector),
//             abi.encode(bool(true))
//         );

//         (initialMajor, initialMinor, initialPatch) = getters.getSemverProtocolVersion();
//         initialProtocolVersion = packSemver(initialMajor, initialMinor, initialPatch);
//         initialMinorProtocolVersion = initialMinor;

//         DiamondInit diamondInit = new DiamondInit();
//         bytes8 dummyHash = 0x1234567890123456;

//         InitializeData memory params = InitializeData({
//             // TODO REVIEW
//             chainId: eraChainId,
//             bridgehub: makeAddr("bridgehub"),
//             stateTransitionManager: address(stateTransitionManager),
//             protocolVersion: 0,
//             admin: owner,
//             validatorTimelock: validator,
//             baseToken: ETH_TOKEN_ADDRESS,
//             baseTokenBridge: address(new DummyEraBaseTokenBridge()),
//             storedBatchZero: keccak256(abi.encode(genesisBatchInfo)),
//             verifier: IVerifier(testnetVerifier), // verifier
//             verifierParams: VerifierParams({
//                 recursionNodeLevelVkHash: 0,
//                 recursionLeafLevelVkHash: 0,
//                 recursionCircuitsSetVksHash: 0
//             }),
//             l2BootloaderBytecodeHash: dummyHash,
//             l2DefaultAccountBytecodeHash: dummyHash,
//             priorityTxMaxGasLimit: 1000000,
//             feeParams: defaultFeeParams(),
//             blobVersionedHashRetriever: blobVersionedHashRetriever
//         });

//         bytes memory diamondInitData = abi.encodeWithSelector(diamondInit.initialize.selector, params);

//         Diamond.FacetCut[] memory facetCuts = new Diamond.FacetCut[](4);
//         facetCuts[0] = Diamond.FacetCut({
//             facet: address(admin),
//             action: Diamond.Action.Add,
//             isFreezable: true,
//             selectors: Utils2.getAllSelectors(address(admin).code)
//         });
//         facetCuts[1] = Diamond.FacetCut({
//             facet: address(executor),
//             action: Diamond.Action.Add,
//             isFreezable: true,
//             selectors: Utils2.getAllSelectors(address(executor).code)
//         });
//         facetCuts[2] = Diamond.FacetCut({
//             facet: address(getters),
//             action: Diamond.Action.Add,
//             isFreezable: false,
//             selectors: Utils2.getAllSelectors(address(getters).code)
//         });
//         facetCuts[3] = Diamond.FacetCut({
//             facet: address(mailbox),
//             action: Diamond.Action.Add,
//             isFreezable: true,
//             selectors: Utils2.getAllSelectors(address(mailbox).code)
//         });

//         Diamond.DiamondCutData memory diamondCutData = Diamond.DiamondCutData({
//             facetCuts: facetCuts,
//             initAddress: address(diamondInit),
//             initCalldata: diamondInitData
//         });

//         chainId = block.chainid;
//         diamondProxy = new DiamondProxy(chainId, diamondCutData);
//         validatorTimelock = new ValidatorTimelock(owner, 0, chainId);

//         executor = ExecutorFacet(address(diamondProxy));
//         getters = GettersFacet(address(diamondProxy));
//         mailbox = MailboxFacet(address(diamondProxy));
//         admin = AdminFacet(address(diamondProxy));

//         bytes32 upgradeTxHash = getters.getL2SystemContractsUpgradeTxHash();
//         IExecutor.CommitBatchInfo[] memory batch1InfoChainIdUpgrade = new IExecutor.CommitBatchInfo[](1);
//         batch1InfoChainIdUpgrade[0] = buildCommitBatchInfoWithUpgrade(
//             genesisStoredBatchInfo(),
//             CommitBatchInfoWithTimestamp ({
//               batchNumber: 1,
//               timestamp: timestamp
//             }),
//             upgradeTxHash
//         );
//         vm.prank(validator);
//         executor.commitBatches(genesisStoredBatchInfo(), batch1InfoChainIdUpgrade);     
//     }

//     function test_test() public {

//     }
// }