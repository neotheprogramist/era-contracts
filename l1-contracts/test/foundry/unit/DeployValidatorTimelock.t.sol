pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {ValidatorTimelock} from "contracts/state-transition/ValidatorTimelock.sol";
import {DummyExecutor} from "contracts/dev-contracts/test/DummyExecutor.sol";
import {DummyStateTransitionManager} from "contracts/dev-contracts/test/DummyStateTransitionManager.sol";

contract ValidatorTest is Test {
    
    ValidatorTimelock validatorTimelock;
    DummyExecutor dummyExecutor;
    DummyStateTransitionManager dummyStateTransitionManager;

    uint256 chainId = 270;
    address owner;

    function setup() public {
        dummyExecutor = new DummyExecutor();
        dummyStateTransitionManager = new DummyStateTransitionManager();

        owner = msg.sender;
        validatorTimelock = new ValidatorTimelock(owner, 0, chainId); 
    }

    function test_checkDeployment() public {
        assertEq(validatorTimelock.owner(), owner);
    }
}