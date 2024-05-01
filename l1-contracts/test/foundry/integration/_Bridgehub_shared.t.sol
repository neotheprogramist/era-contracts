// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {StdStorage, stdStorage} from "forge-std/Test.sol";
import {Test} from "forge-std/Test.sol";

import {Diamond} from "contracts/state-transition/libraries/Diamond.sol";
import {DiamondInit} from "contracts/state-transition/chain-deps/DiamondInit.sol";
import {DiamondProxy} from "contracts/state-transition/chain-deps/DiamondProxy.sol";
import {IDiamondInit} from "contracts/state-transition/chain-interfaces/IDiamondInit.sol";
import {Bridgehub} from "contracts/bridgehub/Bridgehub.sol";
import {StateTransitionManager} from "contracts/state-transition/StateTransitionManager.sol";
import {L1SharedBridge} from "contracts/bridge/L1SharedBridge.sol";
import {IBridgehub, L2TransactionRequestDirect} from "contracts/bridgehub/IBridgehub.sol";
import {TestnetERC20Token} from "contracts/dev-contracts/TestnetERC20Token.sol";
import {Utils} from "foundry-test/unit/concrete/Utils/Utils.sol";
import {TestnetVerifier} from "contracts/state-transition/TestnetVerifier.sol";
import {InitializeDataNewChain} from "contracts/state-transition/chain-interfaces/IDiamondInit.sol";
import {UtilsFacet} from "foundry-test/unit/concrete/Utils/UtilsFacet.sol";
import {AdminFacet} from "contracts/state-transition/chain-deps/facets/Admin.sol";
import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";
import {ExecutorFacet} from "contracts/state-transition/chain-deps/facets/Executor.sol";
import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
import {GenesisUpgrade} from "contracts/upgrades/GenesisUpgrade.sol";
import {StateTransitionManagerInitializeData} from "contracts/state-transition/IStateTransitionManager.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA} from "contracts/common/Config.sol";
import {IZkSyncHyperchain} from "contracts/state-transition/chain-interfaces/IZkSyncHyperchain.sol";
import {ETH_TOKEN_ADDRESS, REQUIRED_L2_GAS_PRICE_PER_PUBDATA, MAX_NEW_FACTORY_DEPS} from "contracts/common/Config.sol";

contract BridgeHubIntegration is Test {
    using stdStorage for StdStorage;

    address diamondAddress;
    address stmAddress;
    address bridgeHubOwner;
    address admin;
    address validator;
    address bridgeHubAddress;
    address eraDiamondProxy;
    address l1WethAddress;
    address l2SharedBridge;

    Diamond.FacetCut[] facetCuts;
    TestnetVerifier testnetVerifier;
    L1SharedBridge sharedBridge;
    Bridgehub bridgeHub;
    TestnetERC20Token token;

    uint256 chainId;
    uint256 eraChainId;

    constructor() {
        bridgeHubOwner = makeAddr("bridgeHubOwner");
        eraDiamondProxy = makeAddr("eraDiamondProxy");
        admin = makeAddr("admin");
        l1WethAddress = makeAddr("weth");
        validator = makeAddr("validator");
        l2SharedBridge = makeAddr("l2sharedBridge");

        testnetVerifier = new TestnetVerifier();

        chainId = 1;
        eraChainId = 9;

        bridgeHub = new Bridgehub();
        bridgeHubAddress = address(bridgeHub);

        vm.prank(bridgeHub.owner());
        bridgeHub.transferOwnership(bridgeHubOwner);

        vm.prank(bridgeHubOwner);
        bridgeHub.acceptOwnership();

        vm.prank(bridgeHubOwner);
        bridgeHub.setPendingAdmin(admin);

        vm.prank(admin);
        bridgeHub.acceptAdmin();

        setFacetCuts();
        initializeStateTransitionManager();
        registerStateTransitionManager(stmAddress);

        token = new TestnetERC20Token("ERC20Base", "UWU", 18);
        registerNewToken(address(token));
        registerNewToken(ETH_TOKEN_ADDRESS);

        sharedBridge = new L1SharedBridge({
            _l1WethAddress: l1WethAddress,
            _bridgehub: IBridgehub(address(bridgeHub)),
            _eraChainId: eraChainId,
            _eraDiamondProxy: eraDiamondProxy
        });

        // skipped intializing upgradeable proxy for now
        vm.prank(sharedBridge.owner());
        sharedBridge.transferOwnership(bridgeHubOwner);

        vm.prank(bridgeHubOwner);
        sharedBridge.acceptOwnership();

        // mock l2 side of shared bridge
        vm.startPrank(bridgeHubOwner);
        sharedBridge.initializeChainGovernance(chainId, l2SharedBridge);
        sharedBridge.initializeChainGovernance(eraChainId, l2SharedBridge);
        vm.stopPrank();

        vm.prank(bridgeHubOwner);
        bridgeHub.setSharedBridge(address(sharedBridge));
    }

    function registerStateTransitionManager(address _stmAddress) internal {
        vm.prank(bridgeHubOwner);
        bridgeHub.addStateTransitionManager(_stmAddress);
    }

    function registerNewToken(address tokenAddress) internal {
        vm.prank(bridgeHubOwner);
        bridgeHub.addToken(tokenAddress);
    }

    function initializeNewChainParams(uint256 _chainId) private {
        address hyperChainAddress = bridgeHub.getHyperchain(_chainId);

        AdminFacet adminFacet = AdminFacet(hyperChainAddress);
        adminFacet.setTokenMultiplier(1, 1);
    }

    function initializeStateTransitionManager() private {
        StateTransitionManager stm = new StateTransitionManager(bridgeHubAddress, type(uint256).max);
        GenesisUpgrade genesisUpgradeContract = new GenesisUpgrade();
        DiamondInit diamondInit = new DiamondInit();
        diamondAddress = address(diamondInit);

        StateTransitionManagerInitializeData memory stmInitializeData = StateTransitionManagerInitializeData({
            owner: admin,
            validatorTimelock: validator,
            genesisUpgrade: address(genesisUpgradeContract),
            genesisBatchHash: bytes32(""),
            genesisIndexRepeatedStorageChanges: 0,
            genesisBatchCommitment: bytes32(""),
            diamondCut: getDiamondCutData(diamondAddress),
            protocolVersion: 0
        });

        vm.prank(bridgeHubAddress);
        TransparentUpgradeableProxy transparentUpgradeableProxy = new TransparentUpgradeableProxy(
            address(stm),
            admin,
            abi.encodeCall(StateTransitionManager.initialize, stmInitializeData)
        );

        stmAddress = address(transparentUpgradeableProxy);
    }

    function setFacetCuts() private {
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
                selectors: Utils.getGettersSelectors()
            })
        );

        facetCuts.push(
            Diamond.FacetCut({
                facet: address(new MailboxFacet(eraChainId)),
                action: Diamond.Action.Add,
                isFreezable: true,
                selectors: Utils.getMailboxSelectors()
            })
        );
    }

    function registerNewChain(uint256 _chainId, address _baseToken) internal returns (uint256 chainId) {
        Diamond.DiamondCutData memory diamondCutData = getDiamondCutData(diamondAddress);

        vm.prank(bridgeHubOwner);
        chainId = bridgeHub.createNewChain(
            _chainId,
            stmAddress,
            _baseToken,
            uint256(12),
            admin,
            abi.encode(diamondCutData)
        );
    }

    function getDiamondCutData(address _diamondInit) internal returns (Diamond.DiamondCutData memory) {
        InitializeDataNewChain memory initializeData = Utils.makeInitializeDataForNewChain(address(testnetVerifier));

        bytes memory initCalldata = abi.encode(initializeData);

        return Diamond.DiamondCutData({facetCuts: facetCuts, initAddress: _diamondInit, initCalldata: initCalldata});
    }

    function setSharedBridgeChainBalance(uint256 _chainId, address _token, uint256 _value) internal {
        stdstore
            .target(address(sharedBridge))
            .sig(sharedBridge.chainBalance.selector)
            .with_key(_chainId)
            .with_key(_token)
            .checked_write(_value);
    }
}

contract HyperchainFactory is BridgeHubIntegration {
    uint256 minHyperchainId = 10;
    uint256[] hyperchainIds;

    function spawnHyperchain() public {
        hyperchainIds.push(registerNewChain(minHyperchainId + hyperchainIds.length, ETH_TOKEN_ADDRESS));
    }

    function spawnHyperchain(address _token) public {
        hyperchainIds.push(registerNewChain(minHyperchainId + hyperchainIds.length, _token));
    }

    function spawnMultipleHyperchains(uint256 _numHyperchains) public {
        for (uint i = 0; i < _numHyperchains; i++) {
            spawnHyperchain();
        }
    }

    function spawnMultipleHyperchainsWithToken(uint256 _numHyperchains, address _token) public {
        for (uint i = 0; i < _numHyperchains; i++) {
            spawnHyperchain(_token);
        }
    }

    function getHyperchainAddress(uint256 _chainId) public view returns (address) {
        return bridgeHub.getHyperchain(_chainId);
    }

    function getHyperchainBaseToken(uint256 _chainId) public view returns (address) {
        return bridgeHub.baseToken(_chainId);
    }

    function clearSharedBridgeBalances() public {
        for (uint i = 0; i < hyperchainIds.length; i++) {
            setSharedBridgeChainBalance(hyperchainIds[i], ETH_TOKEN_ADDRESS, 0);
            setSharedBridgeChainBalance(hyperchainIds[i], address(token), 0);
        }
    }

    function test_creationOfHyperchains() public {
        for (uint i = minHyperchainId; i < hyperchainIds.length; i++) {
            address newHyperchain = getHyperchainAddress(i);
            assert(newHyperchain != address(0));
        }
    }
}

contract L2TxMocker is Test {
    address mockRefundRecipient;
    address mockL2Contract;

    uint256 mockL2Value = 1000;
    uint256 mockL2GasLimit = 10000000;
    uint256 mockL2GasPerPubdataByteLimit = REQUIRED_L2_GAS_PRICE_PER_PUBDATA;

    bytes mockL2Calldata;
    bytes[] mockFactoryDeps;

    constructor() {
        mockRefundRecipient = makeAddr("refundrecipient");
        mockL2Contract = makeAddr("mockl2contract");

        mockL2Calldata = "";
        mockFactoryDeps = new bytes[](1);
        mockFactoryDeps[0] = "11111111111111111111111111111111";
    }

    function createMockL2TransactionRequestDirect(
        uint256 chainId,
        uint256 mintValue
    ) internal returns (L2TransactionRequestDirect memory) {
        L2TransactionRequestDirect memory l2TxnReqDirect;

        l2TxnReqDirect.chainId = chainId;
        l2TxnReqDirect.mintValue = mintValue;
        l2TxnReqDirect.l2Contract = mockL2Contract;
        l2TxnReqDirect.l2Value = mockL2Value;
        l2TxnReqDirect.l2Calldata = mockL2Calldata;
        l2TxnReqDirect.l2GasLimit = mockL2GasLimit;
        l2TxnReqDirect.l2GasPerPubdataByteLimit = REQUIRED_L2_GAS_PRICE_PER_PUBDATA;
        l2TxnReqDirect.factoryDeps = mockFactoryDeps;
        l2TxnReqDirect.refundRecipient = mockRefundRecipient;

        return l2TxnReqDirect;
    }
}

contract IntegrationTests is BridgeHubIntegration, HyperchainFactory, L2TxMocker {
    address alice;
    address bob;

    function setUp() public {
        spawnMultipleHyperchains(2);
        spawnMultipleHyperchainsWithToken(2, address(token));

        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    function test_hyperchainTokenDirectDeposit_Eth() public {
        clearSharedBridgeBalances();

        vm.txGasPrice(0.05 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        uint256 firstChainId = hyperchainIds[0];
        uint256 secondChainId = hyperchainIds[1];

        assertTrue(getHyperchainBaseToken(firstChainId) == ETH_TOKEN_ADDRESS);
        assertTrue(getHyperchainBaseToken(secondChainId) == ETH_TOKEN_ADDRESS);

        L2TransactionRequestDirect memory aliceRequest = createMockL2TransactionRequestDirect(firstChainId, 1 ether);
        L2TransactionRequestDirect memory bobRequest = createMockL2TransactionRequestDirect(secondChainId, 1 ether);

        bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
        address firstHyperChainAddress = getHyperchainAddress(firstChainId);
        address secondHyperChainAddress = getHyperchainAddress(secondChainId);

        vm.mockCall(
            firstHyperChainAddress,
            abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
            abi.encode(canonicalHash)
        );

        vm.mockCall(
            secondHyperChainAddress,
            abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
            abi.encode(canonicalHash)
        );

        vm.prank(alice);
        bytes32 resultantHash = bridgeHub.requestL2TransactionDirect{value: alice.balance}(aliceRequest);
        assertEq(canonicalHash, resultantHash);

        vm.prank(bob);
        bytes32 resultantHash2 = bridgeHub.requestL2TransactionDirect{value: bob.balance}(bobRequest);
        assertEq(canonicalHash, resultantHash2);

        assertEq(alice.balance, 0);
        assertEq(bob.balance, 0);

        assertEq(address(sharedBridge).balance, 2 ether);
        assertEq(sharedBridge.chainBalance(firstChainId, ETH_TOKEN_ADDRESS), 1 ether);
        assertEq(sharedBridge.chainBalance(secondChainId, ETH_TOKEN_ADDRESS), 1 ether);
    }

    function test_hyperchainTokenDirectDeposit_NonEth() public {
        clearSharedBridgeBalances();

        uint256 mockMintValue = 1 ether;

        vm.txGasPrice(0.05 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        token.mint(alice, mockMintValue);
        token.mint(bob, mockMintValue);

        assertEq(token.balanceOf(alice), mockMintValue);
        assertEq(token.balanceOf(bob), mockMintValue);

        uint256 firstChainId = hyperchainIds[2];
        uint256 secondChainId = hyperchainIds[3];

        assertTrue(getHyperchainBaseToken(firstChainId) == address(token));
        assertTrue(getHyperchainBaseToken(secondChainId) == address(token));

        L2TransactionRequestDirect memory aliceRequest = createMockL2TransactionRequestDirect(firstChainId, 1 ether);
        L2TransactionRequestDirect memory bobRequest = createMockL2TransactionRequestDirect(secondChainId, 1 ether);

        bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
        address firstHyperChainAddress = getHyperchainAddress(firstChainId);
        address secondHyperChainAddress = getHyperchainAddress(secondChainId);

        vm.startPrank(alice);
        assertEq(token.balanceOf(alice), mockMintValue);
        token.approve(address(sharedBridge), mockMintValue);
        vm.stopPrank();

        vm.startPrank(bob);
        assertEq(token.balanceOf(bob), mockMintValue);
        token.approve(address(sharedBridge), mockMintValue);
        vm.stopPrank();

        vm.mockCall(
            firstHyperChainAddress,
            abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
            abi.encode(canonicalHash)
        );

        vm.mockCall(
            secondHyperChainAddress,
            abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
            abi.encode(canonicalHash)
        );

        vm.prank(alice);
        bytes32 resultantHash = bridgeHub.requestL2TransactionDirect(aliceRequest);
        assertEq(canonicalHash, resultantHash);

        vm.prank(bob);
        bytes32 resultantHash2 = bridgeHub.requestL2TransactionDirect(bobRequest);
        assertEq(canonicalHash, resultantHash2);

        // check if the balances of alice and bob are 0
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);

        // check if the shared bridge has the correct balances
        assertEq(token.balanceOf(address(sharedBridge)), 2 ether);

        // check if the shared bridge has the correct balances for each chain
        assertEq(sharedBridge.chainBalance(firstChainId, address(token)), mockMintValue);
        assertEq(sharedBridge.chainBalance(secondChainId, address(token)), mockMintValue);
    }
}
