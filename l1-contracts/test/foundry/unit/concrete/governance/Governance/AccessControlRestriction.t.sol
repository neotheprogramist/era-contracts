// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {GovernanceTest} from "./_Governance_Shared.t.sol";
import {IChainAdmin} from "contracts/governance/IChainAdmin.sol";
import {ChainAdmin} from "contracts/governance/ChainAdmin.sol";
import {AccessControlRestriction} from "contracts/governance/AccessControlRestriction.sol";
import {AccessControl} from "node_modules/@openzeppelin/contracts/access/AccessControl.sol";

contract AccessRestrictionTest is GovernanceTest {
    AccessControlRestriction internal restriction;
    ChainAdmin internal chainAdmin;

    function getChainAdminSelectors() public pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = IChainAdmin.getRestrictions.selector;
        selectors[1] = IChainAdmin.isRestrictionActive.selector;
        selectors[2] = IChainAdmin.addRestriction.selector;
        selectors[3] = IChainAdmin.removeRestriction.selector;
 
        return selectors;
    }

    function setUp() public {
        //Deploy access control restriction
        restriction = new AccessControlRestriction(0, msg.sender);
        address[] memory restrictions = new address[](1);
        restrictions[0] = address(restriction);
        
        //deploy chain admin
        chainAdmin = new ChainAdmin(restrictions);
    }

    function test_setRequiredRoleForCallRevert() public {
        bytes4[] memory chainAdminSelectors = getChainAdminSelectors();
        restriction.setRequiredRoleForCall(address(chainAdmin), chainAdminSelectors[0], 1);

        vm.expectRevert(
            "AccessControl: account ",
            Strings.toHexString(msg.sender),
            " is missing role ",
            Strings.toHexString(1, 32)
        );
        chainAdmin.call(
            abi.encodeWithSelector(chainAdminSelectors[0], address(chainAdmin))
        );
    }

    function test_setRequiredRoleForCall() public {
        bytes4[] memory chainAdminSelectors = getChainAdminSelectors();
        restriction.setRequiredRoleForCall(address(chainAdmin), chainAdminSelectors[0], 1);

        AccessControl.grantRole(1, msg.sender);
        chainAdmin.call(
            abi.encodeWithSelector(chainAdminSelectors[0], address(chainAdmin))
        );
    }

    function test_setRequiredRoleForFallback() public {

        restriction.setRequiredRoleForFallback();
    }

    function test_validateCall() public {

        restriction.validateCall();
    }
}