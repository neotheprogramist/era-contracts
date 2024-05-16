// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {L2TransactionRequestDirect, L2TransactionRequestTwoBridgesOuter} from "contracts/bridgehub/IBridgehub.sol";
import {TestnetERC20Token} from "contracts/dev-contracts/TestnetERC20Token.sol";
import {TestnetERC721Token} from "contracts/dev-contracts/TestnetERC721Token.sol";

import {MailboxFacet} from "contracts/state-transition/chain-deps/facets/Mailbox.sol";

import {L1ContractDeployer} from "./_SharedL1ContractDeployer.t.sol";
import {TokenDeployer} from "./_SharedTokenDeployer.t.sol";
import {HyperchainDeployer} from "./_SharedHyperchainDeployer.t.sol";
import {L2TxMocker} from "./_SharedL2TxMocker.t.sol";

import {ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";
import {L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR} from "contracts/common/L2ContractAddresses.sol";
import {L2Message} from "contracts/common/Messaging.sol";
import {IMailbox} from "contracts/state-transition/chain-interfaces/IMailbox.sol";
import {IBridgehub} from "contracts/bridgehub/IBridgehub.sol";
import {L1Erc721Bridge} from "./L1Erc721Bridge/L1Erc721Bridge.sol";

import {IBridgehub} from "contracts/bridgehub/IBridgehub.sol";

import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA} from "contracts/common/Config.sol";

contract BaseIntegrationTests is L1ContractDeployer, HyperchainDeployer, TokenDeployer, L2TxMocker {
    address alice;
    address bob;

    TestnetERC20Token baseToken;

    L1Erc721Bridge erc721Bridge;

    function setUp() public {
        deployL1Contracts();
        deployTokens();

        registerNewTokens(tokens);

        addNewHyperchainToDeploy("hyperchain1", ETH_TOKEN_ADDRESS);
        addNewHyperchainToDeploy("hyperchain2", ETH_TOKEN_ADDRESS);
        addNewHyperchainToDeploy("hyperchain3", tokens[0]);
        addNewHyperchainToDeploy("hyperchain4", tokens[0]);
        deployHyperchains();

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        baseToken = TestnetERC20Token(tokens[0]);

        ////////////////////////// ERC721 Bridge //////////////////////////

        erc721Bridge = new L1Erc721Bridge({
            _l1WethAddress: tokens[1],
            _bridgehub: IBridgehub(bridgehubProxyAddress),
            _eraChainId: 9,
            _eraDiamondProxy: diamondProxyAddress
        });

        vm.prank(erc721Bridge.owner());
        erc721Bridge.transferOwnership(bridgehubOwnerAddress);

        vm.prank(bridgehubOwnerAddress);
        erc721Bridge.acceptOwnership();

        uint256 firstChainId = hyperchainIds[0];
        vm.prank(bridgehubOwnerAddress);
        erc721Bridge.initializeChainGovernance(firstChainId, mockL2SharedBridge);
    }

    function test_hyperchainTokenDirectDeposit_Eth() public {
        vm.txGasPrice(0.05 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        uint256 firstChainId = hyperchainIds[0];
        uint256 secondChainId = hyperchainIds[1];

        assertTrue(getHyperchainBaseToken(firstChainId) == ETH_TOKEN_ADDRESS);
        assertTrue(getHyperchainBaseToken(secondChainId) == ETH_TOKEN_ADDRESS);

        L2TransactionRequestDirect memory aliceRequest = createMockL2TransactionRequestDirect(
            firstChainId,
            1 ether,
            0.1 ether
        );
        L2TransactionRequestDirect memory bobRequest = createMockL2TransactionRequestDirect(
            secondChainId,
            1 ether,
            0.1 ether
        );

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
        uint256 mockMintValue = 1 ether;

        vm.txGasPrice(0.05 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        baseToken.mint(alice, mockMintValue);
        baseToken.mint(bob, mockMintValue);

        assertEq(baseToken.balanceOf(alice), mockMintValue);
        assertEq(baseToken.balanceOf(bob), mockMintValue);

        uint256 firstChainId = hyperchainIds[2];
        uint256 secondChainId = hyperchainIds[3];

        assertTrue(getHyperchainBaseToken(firstChainId) == address(baseToken));
        assertTrue(getHyperchainBaseToken(secondChainId) == address(baseToken));

        L2TransactionRequestDirect memory aliceRequest = createMockL2TransactionRequestDirect(
            firstChainId,
            1 ether,
            0.1 ether
        );
        L2TransactionRequestDirect memory bobRequest = createMockL2TransactionRequestDirect(
            secondChainId,
            1 ether,
            0.1 ether
        );

        bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
        address firstHyperChainAddress = getHyperchainAddress(firstChainId);
        address secondHyperChainAddress = getHyperchainAddress(secondChainId);

        vm.startPrank(alice);
        assertEq(baseToken.balanceOf(alice), mockMintValue);
        baseToken.approve(address(sharedBridge), mockMintValue);
        vm.stopPrank();

        vm.startPrank(bob);
        assertEq(baseToken.balanceOf(bob), mockMintValue);
        baseToken.approve(address(sharedBridge), mockMintValue);
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
        assertEq(baseToken.balanceOf(alice), 0);
        assertEq(baseToken.balanceOf(bob), 0);

        // check if the shared bridge has the correct balances
        assertEq(baseToken.balanceOf(address(sharedBridge)), 2 ether);

        // check if the shared bridge has the correct balances for each chain
        assertEq(sharedBridge.chainBalance(firstChainId, address(baseToken)), mockMintValue);
        assertEq(sharedBridge.chainBalance(secondChainId, address(baseToken)), mockMintValue);
    }

    function test_hyperchainDepositNonBaseWithBaseETH() public {
        uint256 aliceDepositAmount = 1 ether;
        uint256 bobDepositAmount = 1.5 ether;

        uint256 mintValue = 2 ether;
        uint256 l2Value = 10000;
        address l2Receiver = makeAddr("receiver");
        address tokenAddress = address(baseToken);

        uint256 firstChainId = hyperchainIds[0];
        uint256 secondChainId = hyperchainIds[1];

        address firstHyperChainAddress = getHyperchainAddress(firstChainId);
        address secondHyperChainAddress = getHyperchainAddress(secondChainId);

        assertTrue(getHyperchainBaseToken(firstChainId) == ETH_TOKEN_ADDRESS);
        assertTrue(getHyperchainBaseToken(secondChainId) == ETH_TOKEN_ADDRESS);

        registerL2SharedBridge(firstChainId, mockL2SharedBridge);
        registerL2SharedBridge(secondChainId, mockL2SharedBridge);

        vm.txGasPrice(0.05 ether);
        vm.deal(alice, mintValue);
        vm.deal(bob, mintValue);

        assertEq(alice.balance, mintValue);
        assertEq(bob.balance, mintValue);

        baseToken.mint(alice, aliceDepositAmount);
        baseToken.mint(bob, bobDepositAmount);

        assertEq(baseToken.balanceOf(alice), aliceDepositAmount);
        assertEq(baseToken.balanceOf(bob), bobDepositAmount);

        vm.prank(alice);
        baseToken.approve(address(sharedBridge), aliceDepositAmount);

        vm.prank(bob);
        baseToken.approve(address(sharedBridge), bobDepositAmount);

        bytes32 canonicalHash = keccak256(abi.encode("CANONICAL_TX_HASH"));
        {
            bytes memory aliceSecondBridgeCalldata = abi.encode(tokenAddress, aliceDepositAmount, l2Receiver);
            L2TransactionRequestTwoBridgesOuter memory aliceRequest = createMockL2TransactionRequestTwoBridges({
                _chainId: firstChainId,
                _mintValue: mintValue,
                _secondBridgeValue: 0,
                _l2Value: l2Value,
                _secondBridgeAddress: address(sharedBridge),
                _secondBridgeCalldata: aliceSecondBridgeCalldata
            });

            vm.mockCall(
                firstHyperChainAddress,
                abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
                abi.encode(canonicalHash)
            );

            vm.prank(alice);
            bytes32 resultantHash = bridgeHub.requestL2TransactionTwoBridges{value: mintValue}(aliceRequest);
            assertEq(canonicalHash, resultantHash);
        }

        {
            bytes memory bobSecondBridgeCalldata = abi.encode(tokenAddress, bobDepositAmount, l2Receiver);
            L2TransactionRequestTwoBridgesOuter memory bobRequest = createMockL2TransactionRequestTwoBridges({
                _chainId: secondChainId,
                _mintValue: mintValue,
                _secondBridgeValue: 0,
                _l2Value: l2Value,
                _secondBridgeAddress: address(sharedBridge),
                _secondBridgeCalldata: bobSecondBridgeCalldata
            });

            vm.mockCall(
                secondHyperChainAddress,
                abi.encodeWithSelector(MailboxFacet.bridgehubRequestL2Transaction.selector),
                abi.encode(canonicalHash)
            );

            vm.prank(bob);
            bytes32 resultantHash2 = bridgeHub.requestL2TransactionTwoBridges{value: mintValue}(bobRequest);
            assertEq(canonicalHash, resultantHash2);
        }

        assertEq(alice.balance, 0);
        assertEq(bob.balance, 0);
        assertEq(address(sharedBridge).balance, 2 * mintValue);
        assertEq(sharedBridge.chainBalance(firstChainId, ETH_TOKEN_ADDRESS), mintValue);
        assertEq(sharedBridge.chainBalance(secondChainId, ETH_TOKEN_ADDRESS), mintValue);
        assertEq(sharedBridge.chainBalance(firstChainId, tokenAddress), aliceDepositAmount);
        assertEq(sharedBridge.chainBalance(secondChainId, tokenAddress), bobDepositAmount);
        assertEq(baseToken.balanceOf(address(sharedBridge)), aliceDepositAmount + bobDepositAmount);
    }

    function test_hyperchainFinalizeWithdrawal() public {
        uint256 amountToWithdraw = 1 ether;
        _setSharedBridgeChainBalance(10, ETH_TOKEN_ADDRESS, amountToWithdraw);

        uint256 l2BatchNumber = uint256(uint160(makeAddr("l2BatchNumber")));
        uint256 l2MessageIndex = uint256(uint160(makeAddr("l2MessageIndex")));
        uint16 l2TxNumberInBatch = uint16(uint160(makeAddr("l2TxNumberInBatch")));
        bytes32[] memory merkleProof = new bytes32[](1);
        uint256 chainId = 10;

        vm.deal(address(sharedBridge), amountToWithdraw);

        bytes memory message = abi.encodePacked(IMailbox.finalizeEthWithdrawal.selector, alice, amountToWithdraw);
        L2Message memory l2ToL1Message = L2Message({
            txNumberInBatch: l2TxNumberInBatch,
            sender: L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR,
            data: message
        });

        vm.mockCall(
            bridgehubProxyAddress,
            // solhint-disable-next-line func-named-parameters
            abi.encodeWithSelector(
                IBridgehub.proveL2MessageInclusion.selector,
                chainId,
                l2BatchNumber,
                l2MessageIndex,
                l2ToL1Message,
                merkleProof
            ),
            abi.encode(true)
        );

        sharedBridge.finalizeWithdrawal({
            _chainId: chainId,
            _l2BatchNumber: l2BatchNumber,
            _l2MessageIndex: l2MessageIndex,
            _l2TxNumberInBatch: l2TxNumberInBatch,
            _message: message,
            _merkleProof: merkleProof
        });

        assertEq(alice.balance, amountToWithdraw);
        assertEq(address(sharedBridge).balance, 0);
    }

    function test_hyperchainDepositErc721Token() public {
        TestnetERC721Token erc721Token = new TestnetERC721Token("TestnetERC721Token", "TET");
        uint256 hyperchainId = hyperchainIds[0];

        uint256 gasPrice = 10000000;
        uint256 l2GasLimit = 1000000;
        vm.txGasPrice(gasPrice);

        uint256 mintValue = 0.1 ether;
        uint256 l2Value = 10000;
        address l2Receiver = makeAddr("receiver");

        address hyperchainAddress = getHyperchainAddress(hyperchainId);

        assertTrue(getHyperchainBaseToken(hyperchainId) == ETH_TOKEN_ADDRESS);

        // mint gas for user
        vm.deal(alice, gasPrice + mintValue);
        assertEq(alice.balance, gasPrice + mintValue);

        // mint erc721 token for user
        erc721Token.mint(alice, 1);

        // check if the user has the erc721 token
        assertEq(erc721Token.balanceOf(alice), 1);
        assertEq(erc721Token.balanceOf(address(erc721Bridge)), 0);

        // approve the erc721 token to the erc721 bridge
        vm.prank(alice);
        erc721Token.approve(address(erc721Bridge), 1);

        {
            bytes memory secondBridgeCallData = abi.encode(address(erc721Token), 1, l2Receiver);
            L2TransactionRequestTwoBridgesOuter memory aliceRequest = createL2TransactionRequestTwoBridges({
                _chainId: hyperchainId,
                _mintValue: mintValue,
                _secondBridgeValue: 0,
                _secondBridgeAddress: address(erc721Bridge),
                _l2Value: 0,
                _l2GasLimit: l2GasLimit,
                _l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
                _secondBridgeCalldata: secondBridgeCallData
            });

            vm.prank(alice);
            bytes32 resultantHash = bridgeHub.requestL2TransactionTwoBridges{value: mintValue}(aliceRequest);
        }

        assertEq(erc721Token.balanceOf(alice), 0);
        assertEq(erc721Token.balanceOf(address(erc721Bridge)), 1);
    }
}
