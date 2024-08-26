// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import "forge-std/console.sol";
import "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {AccessControlRestriction} from "contracts/governance/AccessControlRestriction.sol";
import {IChainAdmin} from "contracts/governance/IChainAdmin.sol";
import {ChainAdmin} from "contracts/governance/ChainAdmin.sol";
import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
import {AdminFacet} from "contracts/state-transition/chain-deps/facets/Admin.sol";
import {ExecutorFacet} from "contracts/state-transition/chain-deps/facets/Executor.sol";
import {UtilsFacet} from "foundry-test/unit/concrete/Utils/UtilsFacet.sol";
import {IAdmin} from "contracts/state-transition/chain-interfaces/IAdmin.sol";
import {Diamond} from "contracts/state-transition/libraries/Diamond.sol";
import {InitializeData, DiamondInit} from "contracts/state-transition/chain-deps/DiamondInit.sol";
import {DefaultUpgrade} from "contracts/upgrades/DefaultUpgrade.sol";
import {IDefaultUpgrade} from "contracts/upgrades/IDefaultUpgrade.sol";
import {ProposedUpgrade} from "contracts/upgrades/BaseZkSyncUpgrade.sol";
import {GenesisUpgrade} from "contracts/upgrades/GenesisUpgrade.sol";
import {StateTransitionManager} from "contracts/state-transition/StateTransitionManager.sol";
import {StateTransitionManagerInitializeData, ChainCreationParams} from "contracts/state-transition/IStateTransitionManager.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {InitializeDataNewChain} from "contracts/state-transition/chain-interfaces/IDiamondInit.sol";
import {TestnetVerifier} from "contracts/state-transition/TestnetVerifier.sol";
import {Call} from "contracts/governance/Common.sol";
import {NoCallsProvided, RestrictionWasAlreadyPresent, RestrictionWasNotPresent} from "contracts/common/L1ContractErrors.sol";
import {Utils} from "test/foundry/unit/concrete/Utils/Utils.sol";

contract ChainAdminTest is Test {
    ChainAdmin internal chainAdmin;
    AccessControlRestriction internal restriction;
    
    GettersFacet internal gettersFacet;
    AdminFacet internal adminFacet;
    ExecutorFacet internal executorFacet;

    StateTransitionManager internal stateTransitionManager;
    StateTransitionManager internal chainContractAddress;
    DiamondInit internal initializeDiamond;
    GenesisUpgrade internal genesisUpgradeContract;

    address internal bridgehub;
    address internal diamondInit;
    address internal newChainAddress;
    address internal owner;
    uint32 internal major;
    uint32 internal minor;
    uint32 internal patch;
    address internal constant governor = address(0x1010101);
    address internal constant admin = address(0x2020202);
    address internal constant baseToken = address(0x3030303);
    address internal constant sharedBridge = address(0x4040404);
    address internal constant validator = address(0x5050505);
    address internal newChainAdmin;
    uint256 internal chainId = block.chainid;
    address internal testnetVerifier = address(new TestnetVerifier());

    Diamond.FacetCut[] internal facetCuts;

    function setUp() public {
        owner = makeAddr("random address");
 
        restriction = new AccessControlRestriction(0, owner);
        address[] memory restrictions = new address[](1);
        restrictions[0] = address(restriction);

        chainAdmin = new ChainAdmin(restrictions);

        gettersFacet = new GettersFacet();
    }

    function test_getRestrictions() public {
        address[] memory restrictions = chainAdmin.getRestrictions();
        assertEq(restrictions[0], address(restriction));
    }

    function test_isRestrictionActive() public {
        bool isActive = chainAdmin.isRestrictionActive(address(restriction));
        assertEq(isActive, true);
    }

    function test_addRestriction() public {
        address[] memory restrictions = chainAdmin.getRestrictions();
        assertEq(restrictions.length, 1);

        vm.prank(address(chainAdmin));
        chainAdmin.addRestriction(owner);

        restrictions = chainAdmin.getRestrictions();
        assertEq(restrictions.length, 2);
    }

    function test_addRestrictionRevert() public {
        vm.startPrank(address(chainAdmin));
        chainAdmin.addRestriction(owner);

        vm.expectRevert(abi.encodeWithSelector(RestrictionWasAlreadyPresent.selector, owner));
        chainAdmin.addRestriction(owner);
    }

    function test_removeRestriction() public {
        address[] memory restrictions = chainAdmin.getRestrictions();
        vm.prank(address(chainAdmin));
        chainAdmin.addRestriction(address(owner));
        bool isActive = chainAdmin.isRestrictionActive(owner);

        assertEq(isActive, true);

        vm.prank(address(chainAdmin));
        chainAdmin.removeRestriction(owner);
        isActive = chainAdmin.isRestrictionActive(owner);

        assertEq(isActive, false);
    }

    function test_removeRestrictionRevert() public {
        address[] memory restrictions = chainAdmin.getRestrictions();
        vm.startPrank(address(chainAdmin));
        chainAdmin.addRestriction(owner);
        chainAdmin.removeRestriction(owner);
       
        vm.expectRevert(abi.encodeWithSelector(RestrictionWasNotPresent.selector, owner));
        chainAdmin.removeRestriction(owner);
    }

    function test_setUpgradeTimestamp() public {
        bridgehub = makeAddr("bridgehub");
        newChainAdmin = makeAddr("chainadmin");

        vm.startPrank(bridgehub);
        stateTransitionManager = new StateTransitionManager(bridgehub, type(uint256).max);
        diamondInit = address(new DiamondInit());
        genesisUpgradeContract = new GenesisUpgrade();

        facetCuts.push(
            Diamond.FacetCut({
                facet: address(new UtilsFacet()),
                action: Diamond.Action.Add,
                isFreezable: true,
                selectors: Utils.getUtilsFacetSelectors()
            })
        );
        facetCuts.push(
            Diamond.FacetCut({
                facet: address(new AdminFacet()),
                action: Diamond.Action.Add,
                isFreezable: true,
                selectors: Utils.getAdminSelectors()
            })
        );
        facetCuts.push(
            Diamond.FacetCut({
                facet: address(new ExecutorFacet()),
                action: Diamond.Action.Add,
                isFreezable: true,
                selectors: Utils.getExecutorSelectors()
            })
        );
        facetCuts.push(
            Diamond.FacetCut({
                facet: address(new GettersFacet()),
                action: Diamond.Action.Add,
                isFreezable: true,
                selectors: gettersSelectors()
            })
        );

        ChainCreationParams memory chainCreationParams = ChainCreationParams({
            genesisUpgrade: address(genesisUpgradeContract),
            genesisBatchHash: bytes32(uint256(0x01)),
            genesisIndexRepeatedStorageChanges: 0x01,
            genesisBatchCommitment: bytes32(uint256(0x01)),
            diamondCut: getDiamondCutData(address(diamondInit))
        });

        StateTransitionManagerInitializeData memory stmInitializeDataNoGovernor = StateTransitionManagerInitializeData({
            owner: address(0),
            validatorTimelock: validator,
            chainCreationParams: chainCreationParams,
            protocolVersion: 0
        });

        vm.expectRevert(bytes.concat("STM: owner zero"));
        new TransparentUpgradeableProxy(
            address(stateTransitionManager),
            admin,
            abi.encodeCall(StateTransitionManager.initialize, stmInitializeDataNoGovernor)
        );

        StateTransitionManagerInitializeData memory stmInitializeData = StateTransitionManagerInitializeData({
            owner: governor,
            validatorTimelock: validator,
            chainCreationParams: chainCreationParams,
            protocolVersion: 0
        });

        TransparentUpgradeableProxy transparentUpgradeableProxy = new TransparentUpgradeableProxy(
            address(stateTransitionManager),
            admin,
            abi.encodeCall(StateTransitionManager.initialize, stmInitializeData)
        );
        chainContractAddress = StateTransitionManager(address(transparentUpgradeableProxy));

        vm.stopPrank();
        vm.startPrank(governor);

        createNewChain(getDiamondCutData(address(diamondInit)));
        initializeDiamond = new DiamondInit();
        newChainAddress = chainContractAddress.getHyperchain(chainId);

        executorFacet = ExecutorFacet(address(newChainAddress));
        gettersFacet = GettersFacet(address(newChainAddress));
        adminFacet = AdminFacet(address(newChainAddress));

        vm.stopPrank();

        (major, minor, patch) = gettersFacet.getSemverProtocolVersion();
        uint256 protocolVersion = packSemver(major, minor, patch + 1);

        ProposedUpgrade memory proposedUpgrade = ProposedUpgrade({
            l2ProtocolUpgradeTx: Utils.makeEmptyL2CanonicalTransaction(),
            factoryDeps: new bytes[](1),
            bootloaderHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            defaultAccountHash: 0x0000000000000000000000000000000000000000000000000000000000000000,
            verifier: 0x0000000000000000000000000000000000000000,
            verifierParams: Utils.makeVerifierParams(),
            l1ContractsUpgradeCalldata: hex"",
            postUpgradeCalldata: hex"",
            upgradeTimestamp: 10,
            newProtocolVersion: protocolVersion
        });
        vm.prank(address(chainAdmin));
        chainAdmin.setUpgradeTimestamp(protocolVersion, 8);
        vm.warp(8);
        //bytes memory revertMsg = bytes("Upgrade is not ready yet");
        executeUpgrade(false, "", proposedUpgrade);
    }

    function test_multicallRevertNoCalls() public {
        Call[] memory calls = new Call[](0);

        vm.expectRevert(NoCallsProvided.selector);
        chainAdmin.multicall(calls, false);
    }

    function test_multicallRevertFailedCall() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(chainAdmin), value: 0, data: abi.encodeCall(gettersFacet.getAdmin, ())});

        vm.expectRevert();
        vm.startPrank(owner);
        chainAdmin.multicall(calls, true);
    }

    function test_multicall() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(gettersFacet), value: 0, data: abi.encodeCall(gettersFacet.getAdmin, ())});
        calls[1] = Call({target: address(gettersFacet), value: 0, data: abi.encodeCall(gettersFacet.getVerifier, ())});

        vm.startPrank(owner);
        chainAdmin.multicall(calls, true);
    }

    function executeUpgrade(
        bool shouldRevert,
        bytes memory revertMsg,
        ProposedUpgrade memory proposedUpgrade
    ) public {
        DefaultUpgrade defaultUpgrade = new DefaultUpgrade();

        Diamond.DiamondCutData memory newDiamondCutData = Diamond.DiamondCutData({
            facetCuts: new Diamond.FacetCut[](0),
            initAddress: address(defaultUpgrade),
            initCalldata: abi.encodeCall(IDefaultUpgrade.upgrade, (proposedUpgrade))
        });

        vm.startPrank(0x9c9f0C42Cb0d4280f51E2BD76687a6c5292aFA6C);
        if (shouldRevert) {
            vm.expectRevert(revertMsg);
        }
        IAdmin(newChainAddress).executeUpgrade(newDiamondCutData);
    }

    function gettersSelectors() public pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](29);
        selectors[0] = GettersFacet.getVerifier.selector;
        selectors[1] = GettersFacet.getAdmin.selector;
        selectors[2] = GettersFacet.getPendingAdmin.selector;
        selectors[3] = GettersFacet.getTotalBlocksCommitted.selector;
        selectors[4] = GettersFacet.getTotalBlocksVerified.selector;
        selectors[5] = GettersFacet.getTotalBlocksExecuted.selector;
        selectors[6] = GettersFacet.getTotalPriorityTxs.selector;
        selectors[7] = GettersFacet.getFirstUnprocessedPriorityTx.selector;
        selectors[8] = GettersFacet.getPriorityQueueSize.selector;
        selectors[9] = GettersFacet.priorityQueueFrontOperation.selector;
        selectors[10] = GettersFacet.isValidator.selector;
        selectors[11] = GettersFacet.l2LogsRootHash.selector;
        selectors[12] = GettersFacet.storedBatchHash.selector;
        selectors[13] = GettersFacet.getL2BootloaderBytecodeHash.selector;
        selectors[14] = GettersFacet.getL2DefaultAccountBytecodeHash.selector;
        selectors[15] = GettersFacet.getVerifierParams.selector;
        selectors[16] = GettersFacet.getL2SystemContractsUpgradeBatchNumber.selector;
        selectors[17] = GettersFacet.getPriorityTxMaxGasLimit.selector;
        selectors[18] = GettersFacet.isEthWithdrawalFinalized.selector;
        selectors[19] = GettersFacet.facets.selector;
        selectors[20] = GettersFacet.facetFunctionSelectors.selector;
        selectors[21] = GettersFacet.facetAddresses.selector;
        selectors[22] = GettersFacet.facetAddress.selector;
        selectors[23] = GettersFacet.getSemverProtocolVersion.selector;
        selectors[24] = GettersFacet.getProtocolVersion.selector;
        selectors[25] = GettersFacet.getTotalBatchesCommitted.selector;
        selectors[26] = GettersFacet.getTotalBatchesVerified.selector;
        selectors[27] = GettersFacet.getTotalBatchesExecuted.selector;
        selectors[28] = GettersFacet.getL2SystemContractsUpgradeTxHash.selector;
        return selectors;
    }

    function getDiamondCutData(address _diamondInit) internal returns (Diamond.DiamondCutData memory) {
        InitializeDataNewChain memory initializeData = Utils.makeInitializeDataForNewChain(testnetVerifier);

        bytes memory initCalldata = abi.encode(initializeData);

        return Diamond.DiamondCutData({facetCuts: facetCuts, initAddress: _diamondInit, initCalldata: initCalldata});
    }

    function packSemver(uint32 major, uint32 minor, uint32 patch) public returns (uint256) {
        uint256 SEMVER_MINOR_VERSION_MULTIPLIER = 4294967296;
        if (major != 0) {
            revert("Major version must be 0");
        }

        return minor * SEMVER_MINOR_VERSION_MULTIPLIER + patch;
    }

    function createNewChain(Diamond.DiamondCutData memory _diamondCut) internal {
        vm.stopPrank();
        vm.startPrank(bridgehub);

        chainContractAddress.createNewChain({
            _chainId: chainId,
            _baseToken: baseToken,
            _sharedBridge: sharedBridge,
            _admin: newChainAdmin,
            _diamondCut: abi.encode(_diamondCut)
        });
    }
}