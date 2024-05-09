// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2TransactionRequestDirect, L2TransactionRequestTwoBridgesOuter} from "contracts/bridgehub/IBridgehub.sol";
import {TestnetERC20Token} from "contracts/dev-contracts/TestnetERC20Token.sol";

import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";

import {L1ContractDeployer} from "./_SharedL1ContractDeployer.t.sol";
import {TokenDeployer} from "./_SharedTokenDeployer.t.sol";
import {HyperchainDeployer} from "./_SharedHyperchainDeployer.t.sol";
import {L2TxMocker} from "./_SharedL2TxMocker.t.sol";
import {Test} from "forge-std/Test.sol";
import {ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";

contract BaseIntegrationTests is L1ContractDeployer, HyperchainDeployer, TokenDeployer, L2TxMocker {
    uint constant TEST_USERS_COUNT = 10;

    address[] users;
    address public currentUser;
    uint256 public currentChainId;
    address public currentChainAddress;
    address public currentTokenAddress = ETH_TOKEN_ADDRESS;
    TestnetERC20Token currentToken;

    mapping(address user => mapping(address token => uint256 deposited)) public depositsUsers;
    mapping(address chain => mapping(address token => uint256 deposited)) public depositsBridge;
    mapping(address token => uint256 deposited) public tokenSumDeposit;

    // helper modifier to get some random user
    modifier useUser(uint256 userIndexSeed) {
        currentUser = users[bound(userIndexSeed, 0, users.length - 1)];
        vm.startPrank(currentUser);
        _;
        vm.stopPrank();
    }

    // helper modifier to use given hyperchain
    modifier useHyperchain(uint256 chainIndexSeed) {
        currentChainId = hyperchainIds[bound(chainIndexSeed, 0, hyperchainIds.length - 1)];
        currentChainAddress = getHyperchainAddress(currentChainId);
        _;
    }

    modifier useGivenToken(address tokenAddress) {
        currentToken = TestnetERC20Token(tokenAddress);
        currentTokenAddress = tokenAddress;
        _;
    }

    modifier useRandomToken(uint256 tokenIndexSeed) {
        currentTokenAddress = tokens[bound(tokenIndexSeed, 0, tokens.length - 1)];
        currentToken = TestnetERC20Token(currentTokenAddress);
        _;
    }

    // helper modifier to use given token
    modifier useBaseToken() {
        currentToken = TestnetERC20Token(getHyperchainBaseToken(currentChainId));
        currentTokenAddress = address(currentToken);
        _;
    }

    // generate MAX_USERS addresses and append it to testing adr
    function generateUserAddresses() internal {
        require(users.length == 0, "Addresses already generated");

        for (uint i = 0; i < TEST_USERS_COUNT; i++) {
            address newAddress = makeAddr(string(abi.encode("account", i)));
            users.push(newAddress);
        }
    }

    // function depositEthToNonEthChain(
    //     uint256 mintValue,
    //     uint256 l2Value
    // ) internal {
    //     uint256 gas = 0.001 ether;
    //     vm.txGasPrice(gas);
    //     vm.deal(currentUser, mintValue + 10 * gas);

    //     L2TransactionRequestDirect memory txRequest = createMockL2TransactionRequestDirect(
    //         currentChainId,
    //         mintValue,
    //         l2Value
    //     );

    //     bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));

    //     vm.mockCall(
    //         currentChainAddress,
    //         abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
    //         abi.encode(canonicalHash)
    //     );

    //     bytes32 resultantHash = bridgeHub.requestL2TransactionDirect(txRequest);
    //     assertEq(canonicalHash, resultantHash);

    //     depositsUsers[currentUser][ETH_TOKEN_ADDRESS] += mintValue;
    //     depositsBridge[currentChainAddress][ETH_TOKEN_ADDRESS] += mintValue;
    //     tokenSumDeposit[ETH_TOKEN_ADDRESS] += mintValue;
    // }

    function depositEthToEthChain(uint256 mintValue, uint256 l2Value) private {
        uint256 gas = 0.001 ether;
        vm.txGasPrice(gas);
        vm.deal(currentUser, mintValue + gas);

        L2TransactionRequestDirect memory txRequest = createMockL2TransactionRequestDirect(
            currentChainId,
            mintValue,
            l2Value
        );

        bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));

        vm.mockCall(
            currentChainAddress,
            abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
            abi.encode(canonicalHash)
        );

        bytes32 resultantHash = bridgeHub.requestL2TransactionDirect{value: mintValue}(txRequest);
        assertEq(canonicalHash, resultantHash);

        depositsUsers[currentUser][ETH_TOKEN_ADDRESS] += mintValue;
        depositsBridge[currentChainAddress][ETH_TOKEN_ADDRESS] += mintValue;
        tokenSumDeposit[ETH_TOKEN_ADDRESS] += mintValue;
    }

    // deposits base ERC20 token to the bridge
    // uses token provided as a input
    function depositBaseERC20Token(
        uint256 mintValue,
        uint256 l2Value,
        address tokenAddress
    ) private useGivenToken(tokenAddress) {
        uint256 gas = 0.05 ether;

        vm.txGasPrice(gas);
        vm.deal(currentUser, gas);

        currentToken.mint(currentUser, mintValue);
        assertEq(currentToken.balanceOf(currentUser), mintValue);
        currentToken.approve(address(sharedBridge), mintValue);

        L2TransactionRequestDirect memory txRequest = createMockL2TransactionRequestDirect(
            currentChainId,
            mintValue,
            l2Value
        );

        bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));

        vm.mockCall(
            currentChainAddress,
            abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
            abi.encode(canonicalHash)
        );

        bytes32 resultantHash = bridgeHub.requestL2TransactionDirect(txRequest);
        assertEq(canonicalHash, resultantHash);

        depositsUsers[currentUser][currentTokenAddress] += mintValue;
        depositsBridge[currentChainAddress][currentTokenAddress] += l2Value;
        tokenSumDeposit[currentTokenAddress] += mintValue;
    }

    function depositEthToEthBridgeSuccess(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 mintValue,
        uint256 l2Value
    ) public virtual useUser(userIndexSeed) useHyperchain(chainIndexSeed) {
        if (getHyperchainBaseToken(currentChainId) == ETH_TOKEN_ADDRESS) {
            depositEthToEthChain(mintValue, l2Value);
        } else {
            // idk
            //depositEthToNonEthChain(mintValue, l2Value);
        }
    }

    function depositEthToEthBridgeFails(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 mintValue,
        uint256 l2Value
    ) public virtual useUser(userIndexSeed) useHyperchain(chainIndexSeed) {
        if (getHyperchainBaseToken(currentChainId) == ETH_TOKEN_ADDRESS) {
            // idk
            //vm.expectRevert("Bridgehub: msg.value mismatch 1");
            //depositEthToNonEthChain(mintValue, l2Value);
        } else {
            vm.expectRevert("Bridgehub: non-eth bridge with msg.value");
            depositEthToEthChain(mintValue, l2Value);
        }
    }

    function depositERC20TokenToBridgeSuccess(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 tokenIndexSeed,
        uint256 mintValue,
        uint256 l2Value
    ) public virtual useUser(userIndexSeed) useHyperchain(chainIndexSeed) useRandomToken(tokenIndexSeed) {
        address token = getHyperchainBaseToken(currentChainId);

        if (currentTokenAddress == token) {
            depositBaseERC20Token(mintValue, l2Value, currentTokenAddress);
        } else {
            // 2 bridges deposit
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
    }
}

contract BoundedBaseIntegrationTests is BaseIntegrationTests {
    function depositEthSuccess(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 mintValue,
        uint256 l2Value
    ) public {
        uint64 MAX = 2 ** 64 - 1;
        // vm.assume(mintValue != 0);
        // vm.assume(mintValue < l2Value);

        uint256 mintValue = bound(mintValue, 0, MAX);
        uint256 l2Value = bound(l2Value, 0, mintValue);

        super.depositEthToEthBridgeSuccess(userIndexSeed, chainIndexSeed, mintValue, l2Value);
    }

    function depositEthFail(uint256 userIndexSeed, uint256 chainIndexSeed, uint256 mintValue, uint256 l2Value) public {
        uint64 MAX = 2 ** 64 - 1;
        // vm.assume(mintValue != 0);
        // vm.assume(mintValue < l2Value);

        uint256 mintValue = bound(mintValue, 0, MAX);
        uint256 l2Value = bound(l2Value, 0, mintValue);

        super.depositEthToEthBridgeFails(userIndexSeed, chainIndexSeed, mintValue, l2Value);
    }

    function depositERC20Success(
        uint256 userIndexSeed,
        uint256 chainIndexSeed,
        uint256 tokenIndexSeed,
        uint256 mintValue,
        uint256 l2Value
    ) external {
        uint64 MAX = 2 ** 64 - 1;
        // vm.assume(mintValue != 0);
        // vm.assume(mintValue < l2Value);

        uint256 mintValue = bound(mintValue, 0, MAX);
        uint256 l2Value = bound(l2Value, 0, mintValue);

        super.depositERC20TokenToBridgeSuccess(userIndexSeed, chainIndexSeed, tokenIndexSeed, mintValue, l2Value);
    }
}

contract InvariantTester is Test {
    BoundedBaseIntegrationTests tests;

    function setUp() public {
        tests = new BoundedBaseIntegrationTests();
        tests.prepare();

        FuzzSelector memory selector = FuzzSelector({addr: address(tests), selectors: new bytes4[](2)});

        selector.selectors[0] = BoundedBaseIntegrationTests.depositEthSuccess.selector;
        selector.selectors[1] = BoundedBaseIntegrationTests.depositERC20Success.selector;

        targetContract(address(tests));
        targetSelector(selector);
    }

    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ETHbalanceStaysEqual() public {
        assertEq(tests.tokenSumDeposit(ETH_TOKEN_ADDRESS), tests.sharedBridgeProxyAddress().balance);
    }

    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_tokenbalanceStaysEqual() public {
        address tokenAddress = tests.currentTokenAddress();

        if (tokenAddress != ETH_TOKEN_ADDRESS) {
            TestnetERC20Token token = TestnetERC20Token(tokenAddress);
            assertEq(tests.tokenSumDeposit(tokenAddress), token.balanceOf(tests.sharedBridgeProxyAddress()));
        }
    }
}

// function fuzzyUserDepositsEthToBridge(
//     uint256 userIndexSeed,
//     uint256 chainIndexSeed,
//     uint256 mintValue,
//     uint256 l2Value
// ) public virtual useUser(userIndexSeed) useHyperchain(chainIndexSeed) {
//     vm.txGasPrice(0.05 ether);
//     vm.deal(currentUser, mintValue);

//     L2TransactionRequestDirect memory txRequest = createMockL2TransactionRequestDirect(
//         currentChainId,
//         mintValue,
//         l2Value
//     );

//     bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));

//     vm.mockCall(
//         currentChainAddress,
//         abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//         abi.encode(canonicalHash)
//     );

//     bytes32 resultantHash = bridgeHub.requestL2TransactionDirect{value: currentUser.balance}(txRequest);
//     assertEq(canonicalHash, resultantHash);
// }

// function test_fuzzyUserDepositsEthToBridge(
//     uint256 userIndexSeed,
//     uint256 chainIndexSeed,
//     uint256 mintValue,
//     uint256 l2Value
// ) public {
//     // vm.assume()
//     fuzzyUserDepositsEthToBridge(userIndexSeed, chainIndexSeed, mintValue, l2Value);
// }

// function test_hyperchainTokenDirectDeposit_Eth() public {
//     vm.txGasPrice(0.05 ether);
//     vm.deal(alice, 1 ether);
//     vm.deal(bob, 1 ether);

//     uint256 firstChainId = hyperchainIds[0];
//     uint256 secondChainId = hyperchainIds[1];

//     assertTrue(getHyperchainBaseToken(firstChainId) == ETH_TOKEN_ADDRESS);
//     assertTrue(getHyperchainBaseToken(secondChainId) == ETH_TOKEN_ADDRESS);

//     L2TransactionRequestDirect memory aliceRequest = createMockL2TransactionRequestDirect(
//         firstChainId,
//         1 ether,
//         0.1 ether
//     );
//     L2TransactionRequestDirect memory bobRequest = createMockL2TransactionRequestDirect(
//         secondChainId,
//         1 ether,
//         0.1 ether
//     );

//     bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
//     address firstHyperChainAddress = getHyperchainAddress(firstChainId);
//     address secondHyperChainAddress = getHyperchainAddress(secondChainId);

//     vm.mockCall(
//         firstHyperChainAddress,
//         abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//         abi.encode(canonicalHash)
//     );

//     vm.mockCall(
//         secondHyperChainAddress,
//         abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//         abi.encode(canonicalHash)
//     );

//     vm.prank(alice);
//     bytes32 resultantHash = bridgeHub.requestL2TransactionDirect{value: alice.balance}(aliceRequest);
//     assertEq(canonicalHash, resultantHash);

//     vm.prank(bob);
//     bytes32 resultantHash2 = bridgeHub.requestL2TransactionDirect{value: bob.balance}(bobRequest);
//     assertEq(canonicalHash, resultantHash2);

//     assertEq(alice.balance, 0);
//     assertEq(bob.balance, 0);

//     assertEq(address(sharedBridge).balance, 2 ether);
//     assertEq(sharedBridge.chainBalance(firstChainId, ETH_TOKEN_ADDRESS), 1 ether);
//     assertEq(sharedBridge.chainBalance(secondChainId, ETH_TOKEN_ADDRESS), 1 ether);
// }

// function test_hyperchainTokenDirectDeposit_NonEth() public {
//     uint256 mockMintValue = 1 ether;

//     vm.txGasPrice(0.05 ether);
//     vm.deal(alice, 1 ether);
//     vm.deal(bob, 1 ether);

//     baseToken.mint(alice, mockMintValue);
//     baseToken.mint(bob, mockMintValue);

//     assertEq(baseToken.balanceOf(alice), mockMintValue);
//     assertEq(baseToken.balanceOf(bob), mockMintValue);

//     uint256 firstChainId = hyperchainIds[2];
//     uint256 secondChainId = hyperchainIds[3];

//     assertTrue(getHyperchainBaseToken(firstChainId) == address(baseToken));
//     assertTrue(getHyperchainBaseToken(secondChainId) == address(baseToken));

//     L2TransactionRequestDirect memory aliceRequest = createMockL2TransactionRequestDirect(
//         firstChainId,
//         1 ether,
//         0.1 ether
//     );
//     L2TransactionRequestDirect memory bobRequest = createMockL2TransactionRequestDirect(
//         secondChainId,
//         1 ether,
//         0.1 ether
//     );

//     bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
//     address firstHyperChainAddress = getHyperchainAddress(firstChainId);
//     address secondHyperChainAddress = getHyperchainAddress(secondChainId);

//     vm.startPrank(alice);
//     assertEq(baseToken.balanceOf(alice), mockMintValue);
//     baseToken.approve(address(sharedBridge), mockMintValue);
//     vm.stopPrank();

//     vm.startPrank(bob);
//     assertEq(baseToken.balanceOf(bob), mockMintValue);
//     baseToken.approve(address(sharedBridge), mockMintValue);
//     vm.stopPrank();

//     vm.mockCall(
//         firstHyperChainAddress,
//         abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//         abi.encode(canonicalHash)
//     );

//     vm.mockCall(
//         secondHyperChainAddress,
//         abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//         abi.encode(canonicalHash)
//     );

//     vm.prank(alice);
//     bytes32 resultantHash = bridgeHub.requestL2TransactionDirect(aliceRequest);
//     assertEq(canonicalHash, resultantHash);

//     vm.prank(bob);
//     bytes32 resultantHash2 = bridgeHub.requestL2TransactionDirect(bobRequest);
//     assertEq(canonicalHash, resultantHash2);

//     // check if the balances of alice and bob are 0
//     assertEq(baseToken.balanceOf(alice), 0);
//     assertEq(baseToken.balanceOf(bob), 0);

//     // check if the shared bridge has the correct balances
//     assertEq(baseToken.balanceOf(address(sharedBridge)), 2 ether);

//     // check if the shared bridge has the correct balances for each chain
//     assertEq(sharedBridge.chainBalance(firstChainId, address(baseToken)), mockMintValue);
//     assertEq(sharedBridge.chainBalance(secondChainId, address(baseToken)), mockMintValue);
// }

// function test_hyperchainDepositNonBaseWithBaseETH() public {
//     uint256 aliceDepositAmount = 1 ether;
//     uint256 bobDepositAmount = 1.5 ether;

//     uint256 mintValue = 2 ether;
//     uint256 l2Value = 10000;
//     address l2Receiver = makeAddr("receiver");
//     address tokenAddress = address(baseToken);

//     uint256 firstChainId = hyperchainIds[0];
//     uint256 secondChainId = hyperchainIds[1];

//     address firstHyperChainAddress = getHyperchainAddress(firstChainId);
//     address secondHyperChainAddress = getHyperchainAddress(secondChainId);

//     assertTrue(getHyperchainBaseToken(firstChainId) == ETH_TOKEN_ADDRESS);
//     assertTrue(getHyperchainBaseToken(secondChainId) == ETH_TOKEN_ADDRESS);

//     registerL2SharedBridge(firstChainId, mockL2SharedBridge);
//     registerL2SharedBridge(secondChainId, mockL2SharedBridge);

//     vm.txGasPrice(0.05 ether);
//     vm.deal(alice, mintValue);
//     vm.deal(bob, mintValue);

//     assertEq(alice.balance, mintValue);
//     assertEq(bob.balance, mintValue);

//     baseToken.mint(alice, aliceDepositAmount);
//     baseToken.mint(bob, bobDepositAmount);

//     assertEq(baseToken.balanceOf(alice), aliceDepositAmount);
//     assertEq(baseToken.balanceOf(bob), bobDepositAmount);

//     vm.prank(alice);
//     baseToken.approve(address(sharedBridge), aliceDepositAmount);

//     vm.prank(bob);
//     baseToken.approve(address(sharedBridge), bobDepositAmount);

//     bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
//     {
//         bytes memory aliceSecondBridgeCalldata = abi.encode(tokenAddress, aliceDepositAmount, l2Receiver);
//         L2TransactionRequestTwoBridgesOuter memory aliceRequest = createMockL2TransactionRequestTwoBridges(
//             firstChainId,
//             mintValue,
//             0,
//             l2Value,
//             address(sharedBridge),
//             aliceSecondBridgeCalldata
//         );

//         vm.mockCall(
//             firstHyperChainAddress,
//             abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//             abi.encode(canonicalHash)
//         );

//         vm.prank(alice);
//         bytes32 resultantHash = bridgeHub.requestL2TransactionTwoBridges{value: mintValue}(aliceRequest);
//         assertEq(canonicalHash, resultantHash);
//     }

//     {
//         bytes memory bobSecondBridgeCalldata = abi.encode(tokenAddress, bobDepositAmount, l2Receiver);
//         L2TransactionRequestTwoBridgesOuter memory bobRequest = createMockL2TransactionRequestTwoBridges(
//             secondChainId,
//             mintValue,
//             0,
//             l2Value,
//             address(sharedBridge),
//             bobSecondBridgeCalldata
//         );

//         vm.mockCall(
//             secondHyperChainAddress,
//             abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
//             abi.encode(canonicalHash)
//         );

//         vm.prank(bob);
//         bytes32 resultantHash2 = bridgeHub.requestL2TransactionTwoBridges{value: mintValue}(bobRequest);
//         assertEq(canonicalHash, resultantHash2);
//     }

//     assertEq(alice.balance, 0);
//     assertEq(bob.balance, 0);
//     assertEq(address(sharedBridge).balance, 2 * mintValue);
//     assertEq(sharedBridge.chainBalance(firstChainId, ETH_TOKEN_ADDRESS), mintValue);
//     assertEq(sharedBridge.chainBalance(secondChainId, ETH_TOKEN_ADDRESS), mintValue);
//     assertEq(sharedBridge.chainBalance(firstChainId, tokenAddress), aliceDepositAmount);
//     assertEq(sharedBridge.chainBalance(secondChainId, tokenAddress), bobDepositAmount);
//     assertEq(baseToken.balanceOf(address(sharedBridge)), aliceDepositAmount + bobDepositAmount);
// }
//}
