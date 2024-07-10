// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {_DeployL1Script} from "../../../deploy-scripts/_DeployL1.s.sol";
import {DeployL1Script} from "../../../deploy-scripts/DeployL1.s.sol";
import {Bridgehub} from "../../../contracts/bridgehub/Bridgehub.sol";
import {L1SharedBridge} from "../../../contracts/bridge/L1SharedBridge.sol";
import {RegisterHyperchainScript} from "../../../deploy-scripts/RegisterHyperchain.s.sol";
import {StateTransitionManager} from "../../../contracts/state-transition/StateTransitionManager.sol";
import {IStateTransitionManager} from "../../../contracts/state-transition/IStateTransitionManager.sol";
import {console2 as console} from "forge-std/Script.sol";

contract DeployL1Test is Test {
    using stdStorage for StdStorage;
    using stdToml for string;

    struct StateTransitionDeployedAddresses {
        address stateTransitionProxy;
        address stateTransitionImplementation;
        address verifier;
        address adminFacet;
        address mailboxFacet;
        address executorFacet;
        address gettersFacet;
        address diamondInit;
        address genesisUpgrade;
        address defaultUpgrade;
        address diamondProxy;
    }

    StateTransitionDeployedAddresses addr;
    address bridgehubProxyAddress;
    address bridgehubOwnerAddress;
    Bridgehub bridgeHub;

    StateTransitionManager public stateTransitionManager;

    function _acceptOwnership() private {
        vm.startPrank(bridgeHub.pendingOwner());
        bridgeHub.acceptOwnership();
        vm.stopPrank();
    }

    function setUp() public {
        _DeployL1Script l1Script = new _DeployL1Script();
        l1Script._run();

        bridgehubProxyAddress = l1Script._getBridgehubProxyAddress();
        bridgeHub = Bridgehub(bridgehubProxyAddress);
        _acceptOwnership();

        vm.warp(100);
        RegisterHyperchainScript registerHyperchain = new RegisterHyperchainScript();
        registerHyperchain.run();

        stateTransitionManager = StateTransitionManager(registerHyperchain.getStateTransitionProxy());

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script-out/output-deploy-l1.toml");
        string memory toml = vm.readFile(path);
        string memory key = "$.deployed_addresses.state_transition";

        addr.stateTransitionProxy = toml.readAddress(string.concat(key, ".state_transition_proxy_addr"));
        addr.stateTransitionImplementation = toml.readAddress(
            string.concat(key, ".state_transition_implementation_addr")
        );
        addr.verifier = toml.readAddress(string.concat(key, ".verifier_addr"));
        addr.adminFacet = toml.readAddress(string.concat(key, ".admin_facet_addr"));
        addr.mailboxFacet = toml.readAddress(string.concat(key, ".mailbox_facet_addr"));
        addr.executorFacet = toml.readAddress(string.concat(key, ".executor_facet_addr"));
        addr.gettersFacet = toml.readAddress(string.concat(key, ".getters_facet_addr"));
        addr.diamondInit = toml.readAddress(string.concat(key, ".diamond_init_addr"));
        addr.genesisUpgrade = toml.readAddress(string.concat(key, ".genesis_upgrade_addr"));
        addr.defaultUpgrade = toml.readAddress(string.concat(key, ".default_upgrade_addr"));

        path = string.concat(root, "/script-out/output-register-hyperchain.toml");
        toml = vm.readFile(path);

        addr.diamondProxy = toml.readAddress(string.concat("$.diamond_proxy_addr"));
    }

    function test_checkStateTransitionMenagerAddress() public {
        address stateTransitionAddress1 = addr.stateTransitionProxy;
        address stateTransitionAddress2 = bridgeHub.stateTransitionManager(9);
        assertEq(stateTransitionAddress1, stateTransitionAddress2);
    }

    function test_checkStateTransitionHyperChainAddress() public {
        address stateTransitionAddress1 = addr.diamondProxy;
        address stateTransitionAddress2 = stateTransitionManager.getHyperchain(9);
        assertEq(stateTransitionAddress1, stateTransitionAddress2);
    }

    function test_checkBridgeHubHyperchainAddress() public {
        address stateTransitionAddress1 = addr.diamondProxy;
        address stateTransitionAddress3 = bridgeHub.getHyperchain(9);
        assertEq(stateTransitionAddress1, stateTransitionAddress3);
    }
}