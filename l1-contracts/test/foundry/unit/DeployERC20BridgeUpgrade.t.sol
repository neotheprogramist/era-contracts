pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {Utils} from "test/foundry/unit/concrete/Utils/Utils.sol";
import {L1ERC20Bridge} from "contracts/bridge/L1ERC20Bridge.sol";
import {IL1SharedBridge} from "contracts/bridge/interfaces/IL1SharedBridge.sol";
import {L1SharedBridge} from "contracts/bridge/L1SharedBridge.sol";
import {TestnetERC20Token} from "contracts/dev-contracts/TestnetERC20Token.sol";
import {FeeOnTransferToken} from "contracts/dev-contracts/FeeOnTransferToken.sol";
import {DummySharedBridge} from "contracts/dev-contracts/test/DummySharedBridge.sol";
import {ReenterL1ERC20Bridge} from "contracts/dev-contracts/test/ReenterL1ERC20Bridge.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IBridgehub} from "contracts/bridgehub/IBridgehub.sol";

contract ERC20BridgeTest is Test {

    L1ERC20Bridge internal bridge;
    DummySharedBridge internal dummySharedBridge;

    ReenterL1ERC20Bridge internal reenterL1ERC20Bridge;
    L1ERC20Bridge internal bridgeReenterItself;

    TransparentUpgradeableProxy internal bridgeProxy;
    TestnetERC20Token internal token;
    TestnetERC20Token internal feeOnTransferToken;
    L1SharedBridge sharedBridgeImpl;

    address internal l1WethAddress;
    address internal eraDiamondProxy;
    uint256 internal eraChainId;
    address internal bridgehubAddress;
    address internal owner;
    address internal admin;
    address internal randomSigner;
    address internal alice;
    bytes32 internal dummyL2DepositTxHash;

    function setUp() public {
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        randomSigner = makeAddr("randomSigner");
        dummyL2DepositTxHash = Utils.randomBytes32("dummyL2DepositTxHash");
        alice = makeAddr("alice");

        dummySharedBridge = new DummySharedBridge(dummyL2DepositTxHash);
        bridge = new L1ERC20Bridge(IL1SharedBridge(address(dummySharedBridge)));

        bridgehubAddress = makeAddr("bridgehub");
        l1WethAddress = makeAddr("weth");
        eraChainId = 9;
        eraDiamondProxy = makeAddr("eraDiamondProxy");

        sharedBridgeImpl = new L1SharedBridge({
            _l1WethAddress: l1WethAddress,
            _bridgehub: IBridgehub(bridgehubAddress),
            _eraChainId: eraChainId,
            _eraDiamondProxy: eraDiamondProxy
        });

        TransparentUpgradeableProxy sharedBridgeProxy = new TransparentUpgradeableProxy(
            address(sharedBridgeImpl),
            randomSigner,
            abi.encodeWithSelector(L1SharedBridge.initialize.selector, owner)
        );

        reenterL1ERC20Bridge = new ReenterL1ERC20Bridge();
        bridgeReenterItself = new L1ERC20Bridge(IL1SharedBridge(address(reenterL1ERC20Bridge)));
        reenterL1ERC20Bridge.setBridge(bridgeReenterItself);

        token = new TestnetERC20Token("TestnetERC20Token", "TET", 18);
        feeOnTransferToken = new FeeOnTransferToken("FeeOnTransferToken", "FOT", 18);
        token.mint(alice, type(uint256).max);
        feeOnTransferToken.mint(alice, type(uint256).max);
    }

    function test_nonExistedMethods() public {
        vm.startBroadcast();
        // ITransparentUpgradeableProxy.upgradeTo(address(bridge));
        vm.stopBroadcast();
    }
}