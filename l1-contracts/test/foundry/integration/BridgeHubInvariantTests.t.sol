// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2TransactionRequestDirect, L2TransactionRequestTwoBridgesOuter} from "contracts/bridgehub/IBridgehub.sol";
import {TestnetERC20Token} from "contracts/dev-contracts/TestnetERC20Token.sol";
import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";
import {GettersFacet} from "contracts/state-transition/chain-deps/facets/Getters.sol";
import {IMailbox} from "contracts/state-transition/chain-interfaces/IMailbox.sol";
import {IExecutor} from "contracts/state-transition/chain-interfaces/IExecutor.sol";
import {IGetters} from "contracts/state-transition/chain-interfaces/IGetters.sol";

import {IStateTransitionManager} from "contracts/state-transition/IStateTransitionManager.sol";

import {L1ContractDeployer} from "./_SharedL1ContractDeployer.t.sol";
import {TokenDeployer} from "./_SharedTokenDeployer.t.sol";
import {HyperchainDeployer} from "./_SharedHyperchainDeployer.t.sol";
import {L2TxMocker} from "./_SharedL2TxMocker.t.sol";
import {Test} from "forge-std/Test.sol";
import {ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA, COMMIT_TIMESTAMP_NOT_OLDER, DEFAULT_L2_LOGS_TREE_ROOT_HASH, EMPTY_STRING_KECCAK} from "contracts/common/Config.sol";
import {Vm} from "forge-std/Vm.sol";
import {L2CanonicalTransaction} from "contracts/common/Messaging.sol";
import {IL2Bridge} from "contracts/bridge/interfaces/IL2Bridge.sol";
import {UnsafeBytes} from "contracts/common/libraries/UnsafeBytes.sol";

contract BridgeHubInvariantTests is L1ContractDeployer, HyperchainDeployer, TokenDeployer, L2TxMocker {
    uint constant TEST_USERS_COUNT = 10;

    bytes32 constant NEW_PRIORITY_REQUEST_HASH =
        keccak256(
            "NewPriorityRequest(uint256,bytes32,uint64,(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256[4],bytes,bytes,uint256[],bytes,bytes),bytes[])"
        );

    struct NewPriorityRequest {
        uint256 txId;
        bytes32 txHash;
        uint64 expirationTimestamp;
        L2CanonicalTransaction transaction;
        bytes[] factoryDeps;
    }

    address[] users;
    address public currentUser;
    uint256 public currentChainId;
    address public currentChainAddress;
    address public currentTokenAddress = ETH_TOKEN_ADDRESS;
    TestnetERC20Token currentToken;

    // amounts deposited by the user, mapped by token
    mapping(address user => mapping(address token => uint256 deposited)) public depositsUsers;
    // amounts deposited into the bridge, mapped by hyperchain and token
    mapping(address chain => mapping(address token => uint256 deposited)) public depositsBridge;
    // sum of deposits into the bridge, mapped by token address
    mapping(address token => uint256 deposited) public tokenSumDeposit;
    // sum of l2values which were transfered to some mock contract, mapped by token address
    mapping(address token => uint256 deposited) public l2ValuesSum;
    // deposits into the hyperchains contract, mapped by token address
    mapping(address l2contract => mapping(address token => uint256 balance)) public contractDeposits;
    // sum of deposits into all the l2 contracts, mapped by token
    mapping(address token => uint256 deposited) public contractDepositsSum;

    // gets random user from users array, sets currentUser
    modifier useUser(uint256 userIndexSeed) {
        currentUser = users[bound(userIndexSeed, 0, users.length - 1)];
        vm.startPrank(currentUser);
        _;
        vm.stopPrank();
    }

    // gets random hyperchain from hyperchain ids, sets currentChainId and currentChainAddress
    modifier useHyperchain(uint256 chainIndexSeed) {
        currentChainId = hyperchainIds[bound(chainIndexSeed, 0, hyperchainIds.length - 1)];
        currentChainAddress = getHyperchainAddress(currentChainId);
        _;
    }

    // use token specified by address
    modifier useGivenToken(address tokenAddress) {
        currentToken = TestnetERC20Token(tokenAddress);
        currentTokenAddress = tokenAddress;
        _;
    }

    // use random token from tokens array
    modifier useRandomToken(uint256 tokenIndexSeed) {
        currentTokenAddress = tokens[bound(tokenIndexSeed, 0, tokens.length - 1)];
        currentToken = TestnetERC20Token(currentTokenAddress);
        _;
    }

    // use base token as main token
    // watch out, will fail if used with etherum
    modifier useBaseToken() {
        currentToken = TestnetERC20Token(getHyperchainBaseToken(currentChainId));
        currentTokenAddress = address(currentToken);
        _;
    }

    // use erc20 token by getting randomly token and keep iterating,
    // while the token is ETH
    modifier useERC20Token(uint256 tokenIndexSeed) {
        currentTokenAddress = tokens[bound(tokenIndexSeed, 0, tokens.length - 1)];

        while (currentTokenAddress == ETH_TOKEN_ADDRESS) {
            tokenIndexSeed += 1;
            currentTokenAddress = tokens[bound(tokenIndexSeed, 0, tokens.length - 1)];
        }

        currentToken = TestnetERC20Token(currentTokenAddress);

        _;
    }

    // generate MAX_USERS addresses and append it to users array
    function generateUserAddresses() internal {
        require(users.length == 0, "Addresses already generated");

        for (uint i = 0; i < TEST_USERS_COUNT; i++) {
            address newAddress = makeAddr(string(abi.encode("account", i)));
            users.push(newAddress);
        }
    }

    function commitBatchInfo(uint256 _chainId) internal {
        //vm.warp(COMMIT_TIMESTAMP_NOT_OLDER + 1 + 1);

        GettersFacet hyperchainGetters = GettersFacet(getHyperchainAddress(_chainId));

        IExecutor.StoredBatchInfo memory batchZero;

        batchZero.batchNumber = 0;
        batchZero.timestamp = 0;
        batchZero.numberOfLayer1Txs = 0;
        batchZero.priorityOperationsHash = EMPTY_STRING_KECCAK;
        batchZero.l2LogsTreeRoot = DEFAULT_L2_LOGS_TREE_ROOT_HASH;

        // maybe replace it with something else
        batchZero.batchHash = vm.parseBytes32("0x0000000000000000000000000000000000000000000000000000000000000000"); //genesis root hash
        batchZero.indexRepeatedStorageChanges = uint64(0);
        batchZero.commitment = vm.parseBytes32("0x0000000000000000000000000000000000000000000000000000000000000000");

        bytes32 hashedZeroBatch = keccak256(abi.encode(batchZero));
        assertEq(hyperchainGetters.storedBatchHash(0), hashedZeroBatch);

        // TODO: consider creating blocks and then batches
    }

    // use mailbox interface to return exact amount to use as a gas,
    // prevents from failing if mintValue < l2Value + required gas
    function getMinRequiredGasPriceForChain(
        uint256 _chainId,
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) public view returns (uint256) {
        MailboxFacet chainMailBox = MailboxFacet(getHyperchainAddress(_chainId));

        return chainMailBox.l2TransactionBaseCost(_gasPrice, _l2GasLimit, _l2GasPerPubdataByteLimit);
    }

    // decodes data encoded with encodeCall, this is just to decode information received from logs
    // to deposit into mock l2 contract
    function getDecodedDepositL2Calldata(
        bytes memory callData
    ) internal view returns (address l1Sender, address l2Receiver, address l1Token, uint256 amount, bytes memory b) {
        // UnsafeBytes approach doesn't work, because abi is not deterministic
        bytes memory slicedData = new bytes(callData.length - 4);

        for (uint i = 4; i < callData.length; i++) {
            slicedData[i - 4] = callData[i];
        }

        (l1Sender, l2Receiver, l1Token, amount, b) = abi.decode(
            slicedData,
            (address, address, address, uint256, bytes)
        );
    }

    // handle event emited from logs and decodes it properly
    function handleRequestByMockL2Contract(NewPriorityRequest memory request) internal {
        address payable contractAddress = payable(address(uint160(uint256(request.transaction.to))));
        address someMockAddress = makeAddr("mocked");

        address tokenAddress;
        address receiver;
        uint256 toSend;
        address l1Sender;

        uint256 requestLength = request.transaction.data.length;
        bytes memory temp;

        if (requestLength > 96) {
            (l1Sender, receiver, tokenAddress, toSend, temp) = getDecodedDepositL2Calldata(request.transaction.data);
        } else {
            (tokenAddress, toSend, receiver) = abi.decode(request.transaction.data, (address, uint256, address));
        }

        assertEq(contractAddress, receiver);

        uint256 balanceAfter = 0;

        if (tokenAddress == ETH_TOKEN_ADDRESS) {
            vm.deal(someMockAddress, toSend);

            vm.startPrank(someMockAddress);
            bool sent = contractAddress.send(toSend);
            vm.stopPrank();
            assertEq(sent, true);

            balanceAfter = contractAddress.balance;
        } else {
            TestnetERC20Token token = TestnetERC20Token(tokenAddress);
            token.mint(someMockAddress, toSend);

            vm.startPrank(someMockAddress);
            token.approve(someMockAddress, toSend);
            bool sent = token.transferFrom(someMockAddress, contractAddress, toSend);
            vm.stopPrank();
            assertEq(sent, true);

            balanceAfter = token.balanceOf(contractAddress);
        }

        contractDeposits[contractAddress][tokenAddress] += toSend;
        contractDepositsSum[tokenAddress] += toSend;
        assertEq(balanceAfter, contractDeposits[contractAddress][tokenAddress]);
    }

    // gets event from logs
    function getNewPriorityQueueFromLogs(Vm.Log[] memory logs) internal returns (NewPriorityRequest memory request) {
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (log.topics[0] == NEW_PRIORITY_REQUEST_HASH) {
                (
                    request.txId,
                    request.txHash,
                    request.expirationTimestamp,
                    request.transaction,
                    request.factoryDeps
                ) = abi.decode(log.data, (uint256, bytes32, uint64, L2CanonicalTransaction, bytes[]));
            }
        }
    }

    // deposits ERC20 token to the hyperchain where base token is ETH
    // this funtion use requestL2TransactionTwoBridges function from shared bridge.
    // tokenAddress should be any ERC20 token, excluding ETH
    function depositERC20ToEthChain(uint256 l2Value, address tokenAddress) private useGivenToken(tokenAddress) {
        uint256 gasPrice = 10000000;
        vm.txGasPrice(gasPrice);

        uint256 l2GasLimit = 1000000;
        uint256 minRequiredGas = getMinRequiredGasPriceForChain(
            currentChainId,
            gasPrice,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );

        uint256 mintValue = minRequiredGas;
        vm.deal(currentUser, mintValue);

        currentToken.mint(currentUser, l2Value);
        assertEq(currentToken.balanceOf(currentUser), l2Value);
        currentToken.approve(address(sharedBridge), l2Value);

        bytes memory secondBridgeCallData = abi.encode(currentTokenAddress, l2Value, chainContracts[currentChainId]);
        L2TransactionRequestTwoBridgesOuter memory requestTx = createMockL2TransactionRequestTwoBridgesSecond(
            currentChainId,
            mintValue,
            0,
            address(sharedBridge),
            0, // L2 VALUE WHICH IS ALWAYS 0
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            secondBridgeCallData
        );

        vm.recordLogs();
        bytes32 resultantHash = bridgeHub.requestL2TransactionTwoBridges{value: mintValue}(requestTx);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        NewPriorityRequest memory request = getNewPriorityQueueFromLogs(logs);
        assertNotEq(request.txHash, 0);
        handleRequestByMockL2Contract(request);
        depositsUsers[currentUser][ETH_TOKEN_ADDRESS] += mintValue;
        depositsBridge[currentChainAddress][ETH_TOKEN_ADDRESS] += mintValue;
        tokenSumDeposit[ETH_TOKEN_ADDRESS] += mintValue;

        depositsUsers[currentUser][currentTokenAddress] += l2Value;
        depositsBridge[currentChainAddress][currentTokenAddress] += l2Value;
        tokenSumDeposit[currentTokenAddress] += l2Value;
        l2ValuesSum[currentTokenAddress] += l2Value;
    }

    // deposits ETH token to chain where base token is some ERC20
    // modifier prevents you from using some other token as base
    function depositEthToERC20Chain(uint256 l2Value) private useBaseToken {
        uint256 gasPrice = 10000000;
        vm.txGasPrice(gasPrice);

        uint256 l2GasLimit = 1000000; // reverts with 8
        uint256 minRequiredGas = getMinRequiredGasPriceForChain(
            currentChainId,
            gasPrice,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );

        vm.deal(currentUser, l2Value);
        uint256 mintValue = minRequiredGas;
        currentToken.mint(currentUser, mintValue);
        assertEq(currentToken.balanceOf(currentUser), mintValue);
        currentToken.approve(address(sharedBridge), mintValue);

        bytes memory secondBridgeCallData = abi.encode(ETH_TOKEN_ADDRESS, uint256(0), chainContracts[currentChainId]);
        L2TransactionRequestTwoBridgesOuter memory requestTx = createMockL2TransactionRequestTwoBridgesSecond(
            currentChainId,
            mintValue,
            l2Value,
            address(sharedBridge),
            0, // L2 VALUE WHICH IS ALWAYS 0
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            secondBridgeCallData
        );

        vm.recordLogs();

        bytes32 resultantHash = bridgeHub.requestL2TransactionTwoBridges{value: l2Value}(requestTx);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        NewPriorityRequest memory request = getNewPriorityQueueFromLogs(logs);
        assertNotEq(request.txHash, 0);

        handleRequestByMockL2Contract(request);
        depositsUsers[currentUser][ETH_TOKEN_ADDRESS] += l2Value;
        depositsBridge[currentChainAddress][ETH_TOKEN_ADDRESS] += l2Value;
        tokenSumDeposit[ETH_TOKEN_ADDRESS] += l2Value;
        l2ValuesSum[ETH_TOKEN_ADDRESS] += l2Value;

        depositsUsers[currentUser][currentTokenAddress] += mintValue;
        depositsBridge[currentChainAddress][currentTokenAddress] += mintValue;
        tokenSumDeposit[currentTokenAddress] += mintValue;
    }

    // deposits ERC20 to token with base being also ERC20
    // there are no modifiers so watch out, baseTokenAddress should be base of hyperchain
    // currentToken should be different from base
    function depositERC20ToERC20Chain(uint256 l2Value, address baseTokenAddress) private {
        uint256 gasPrice = 10000000;
        vm.txGasPrice(gasPrice);

        uint256 l2GasLimit = 1000000; // reverts with 8
        uint256 minRequiredGas = getMinRequiredGasPriceForChain(
            currentChainId,
            gasPrice,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );

        uint256 mintValue = minRequiredGas;

        TestnetERC20Token baseToken = TestnetERC20Token(baseTokenAddress);
        baseToken.mint(currentUser, mintValue);
        assertEq(baseToken.balanceOf(currentUser), mintValue);
        baseToken.approve(address(sharedBridge), mintValue);

        currentToken.mint(currentUser, l2Value);
        assertEq(currentToken.balanceOf(currentUser), l2Value);
        currentToken.approve(address(sharedBridge), l2Value);

        bytes memory secondBridgeCallData = abi.encode(currentTokenAddress, l2Value, chainContracts[currentChainId]);
        L2TransactionRequestTwoBridgesOuter memory requestTx = createMockL2TransactionRequestTwoBridgesSecond(
            currentChainId,
            mintValue,
            0,
            address(sharedBridge),
            0, // L2 VALUE WHICH IS ALWAYS 0
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            secondBridgeCallData
        );

        vm.recordLogs();
        bytes32 resultantHash = bridgeHub.requestL2TransactionTwoBridges(requestTx);

        // get request
        Vm.Log[] memory logs = vm.getRecordedLogs();
        NewPriorityRequest memory request = getNewPriorityQueueFromLogs(logs);
        assertNotEq(request.txHash, 0);

        handleRequestByMockL2Contract(request);

        depositsUsers[currentUser][baseTokenAddress] += mintValue;
        depositsBridge[currentChainAddress][baseTokenAddress] += mintValue;
        tokenSumDeposit[baseTokenAddress] += mintValue;

        depositsUsers[currentUser][currentTokenAddress] += l2Value;
        depositsBridge[currentChainAddress][currentTokenAddress] += l2Value;
        tokenSumDeposit[currentTokenAddress] += l2Value;
        l2ValuesSum[currentTokenAddress] += l2Value;
    }

    // deposits ETH to hyperchain where base is ETH
    function depositEthBase(uint256 l2Value) private {
        uint256 gasPrice = 10000000;
        vm.txGasPrice(gasPrice);

        uint256 l2GasLimit = 1000000; // reverts with 8
        uint256 minRequiredGas = getMinRequiredGasPriceForChain(
            currentChainId,
            gasPrice,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );

        uint256 mintValue = l2Value + minRequiredGas;
        vm.deal(currentUser, mintValue);

        bytes memory callData = abi.encode(currentTokenAddress, l2Value, chainContracts[currentChainId]);
        L2TransactionRequestDirect memory txRequest = createL2TransitionRequestDirectSecond(
            currentChainId,
            mintValue,
            l2Value,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            ETH_TOKEN_ADDRESS,
            callData
        );

        vm.recordLogs();
        bytes32 resultantHash = bridgeHub.requestL2TransactionDirect{value: mintValue}(txRequest);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        NewPriorityRequest memory request = getNewPriorityQueueFromLogs(logs);
        assertNotEq(request.txHash, 0);

        handleRequestByMockL2Contract(request);

        depositsUsers[currentUser][ETH_TOKEN_ADDRESS] += mintValue;
        depositsBridge[currentChainAddress][ETH_TOKEN_ADDRESS] += mintValue;
        tokenSumDeposit[ETH_TOKEN_ADDRESS] += mintValue;
        l2ValuesSum[ETH_TOKEN_ADDRESS] += l2Value;
    }

    // deposits base ERC20 token to the bridge
    function depositERC20Base(uint256 l2Value) private useBaseToken {
        uint256 gasPrice = 10000000;
        vm.txGasPrice(gasPrice);
        vm.deal(currentUser, gasPrice);

        uint256 l2GasLimit = 1000000;
        uint256 minRequiredGas = getMinRequiredGasPriceForChain(
            currentChainId,
            gasPrice,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );

        uint256 mintValue = l2Value + minRequiredGas;
        currentToken.mint(currentUser, mintValue);
        assertEq(currentToken.balanceOf(currentUser), mintValue);
        currentToken.approve(address(sharedBridge), mintValue);

        bytes memory callData = abi.encode(currentTokenAddress, l2Value, chainContracts[currentChainId]);
        L2TransactionRequestDirect memory txRequest = createL2TransitionRequestDirectSecond(
            currentChainId,
            mintValue,
            l2Value,
            l2GasLimit,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            currentTokenAddress,
            callData
        );

        vm.recordLogs();
        bytes32 resultantHash = bridgeHub.requestL2TransactionDirect(txRequest);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        NewPriorityRequest memory request = getNewPriorityQueueFromLogs(logs);
        assertNotEq(request.txHash, 0);

        handleRequestByMockL2Contract(request);

        depositsUsers[currentUser][currentTokenAddress] += mintValue;
        depositsBridge[currentChainAddress][currentTokenAddress] += mintValue;
        tokenSumDeposit[currentTokenAddress] += mintValue;
        l2ValuesSum[currentTokenAddress] += l2Value;
    }

    function depositEthToBridgeSuccess(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 l2Value
    ) public virtual useUser(userIndexSeed) useHyperchain(chainIndexSeed) useBaseToken {
        if (currentTokenAddress == ETH_TOKEN_ADDRESS) {
            depositEthBase(l2Value);
        } else {
            depositEthToERC20Chain(l2Value);
        }
    }

    function depositERC20ToBridgeSuccess(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 tokenIndexSeed,
        uint256 l2Value
    ) public virtual useUser(userIndexSeed) useHyperchain(chainIndexSeed) useERC20Token(tokenIndexSeed) {
        address chainBaseToken = getHyperchainBaseToken(currentChainId);

        if (chainBaseToken == ETH_TOKEN_ADDRESS) {
            depositERC20ToEthChain(l2Value, currentTokenAddress);
        } else {
            if (currentTokenAddress == chainBaseToken) {
                depositERC20Base(l2Value);
            } else {
                depositERC20ToERC20Chain(l2Value, chainBaseToken);
            }
        }
    }

    function prepare() public {
        generateUserAddresses();

        deployL1Contracts();
        deployTokens();
        registerNewTokens(tokens);

        addNewHyperchainToDeploy("hyperchain1", ETH_TOKEN_ADDRESS);
        addNewHyperchainToDeploy("hyperchain2", ETH_TOKEN_ADDRESS);
        addNewHyperchainToDeploy("hyperchain3", tokens[0]);
        addNewHyperchainToDeploy("hyperchain4", tokens[0]);
        deployHyperchains();

        for (uint256 i = 0; i < hyperchainIds.length; i++) {
            address contractAddress = makeAddr(string(abi.encode("contract", i)));
            addL2ChainContract(hyperchainIds[i], contractAddress);

            registerL2SharedBridge(hyperchainIds[i], contractAddress);
        }
    }
}

contract BoundedBridgeHubInvariantTests is BridgeHubInvariantTests {
    function depositEthSuccess(uint256 userIndexSeed, uint256 chainIndexSeed, uint256 l2Value) public {
        uint64 MAX = 2 ** 64 - 1;
        uint256 l2Value = bound(l2Value, 0.1 ether, MAX);

        super.depositEthToBridgeSuccess(userIndexSeed, chainIndexSeed, l2Value);
    }

    function depositERC20Success(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 tokenIndexSeed,
        uint256 l2Value
    ) public {
        uint64 MAX = 2 ** 64 - 1;
        uint256 l2Value = bound(l2Value, 0.1 ether, MAX);

        super.depositERC20ToBridgeSuccess(userIndexSeed, chainIndexSeed, tokenIndexSeed, l2Value);
    }
}

contract InvariantTesterHyperchains is Test {
    BoundedBridgeHubInvariantTests tests;

    function setUp() public {
        tests = new BoundedBridgeHubInvariantTests();
        tests.prepare();

        FuzzSelector memory selector = FuzzSelector({addr: address(tests), selectors: new bytes4[](2)});

        selector.selectors[0] = BoundedBridgeHubInvariantTests.depositEthSuccess.selector;
        selector.selectors[1] = BoundedBridgeHubInvariantTests.depositERC20Success.selector;

        targetContract(address(tests));
        targetSelector(selector);
    }

    // check wether eth sum of deposits shadowed between tests and updated on each deposit
    // equals balance of L1Shared bridge
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_ETHSumEqualsBalance() public {
        assertEq(tests.tokenSumDeposit(ETH_TOKEN_ADDRESS), tests.sharedBridgeProxyAddress().balance);
    }

    // check wether current token sum of deposits shadowed between tests and updated on each deposit
    // equals balance of L1Shared bridge
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_currentTokenSumEqualsBalance() public {
        address currentTokenAddress = tests.currentTokenAddress();
        if (currentTokenAddress != ETH_TOKEN_ADDRESS) {
            TestnetERC20Token token = TestnetERC20Token(currentTokenAddress);
            assertEq(
                tests.tokenSumDeposit(tests.currentTokenAddress()),
                token.balanceOf(tests.sharedBridgeProxyAddress())
            );
        }
    }

    // check if sum of ETH part which is send to L2 contract, registered by this test suite
    // is equals actual sum of balances of l2 contracts (which are mocked, but read events from logs)
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ETHbalaceOnContractsDeposited() public {
        uint256 sum = 0;

        for (uint256 i = 0; i < 5; i++) {
            address l2Contract = tests.chainContracts(tests.hyperchainIds(i));
            uint256 balance = l2Contract.balance;

            assertEq(tests.contractDeposits(l2Contract, ETH_TOKEN_ADDRESS), balance);
            sum += balance;
        }

        assertEq(tests.l2ValuesSum(ETH_TOKEN_ADDRESS), sum);
        assertEq(tests.contractDepositsSum(ETH_TOKEN_ADDRESS), sum);
    }

    // check if sum of currentToken part which is send to L2 contract, registered by this test suite
    // is equals actual sum of balances of l2 contracts (which are mocked, but read events from logs)
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_currentTokenBalaceOnContractsEqualsDeposited() public {
        address currentTokenAddress = tests.currentTokenAddress();
        uint256 sum = 0;

        if (currentTokenAddress == ETH_TOKEN_ADDRESS) {
            return;
        }

        for (uint256 i = 0; i < 5; i++) {
            TestnetERC20Token token = TestnetERC20Token(currentTokenAddress);
            address l2Contract = tests.chainContracts(tests.hyperchainIds(i));
            uint256 balance = token.balanceOf(l2Contract);
            assertEq(tests.contractDeposits(l2Contract, currentTokenAddress), balance);
            sum += balance;
        }

        assertEq(tests.contractDepositsSum(currentTokenAddress), sum);
        assertEq(tests.l2ValuesSum(currentTokenAddress), sum);
    }
}

