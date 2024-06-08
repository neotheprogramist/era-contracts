// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {AccountStoreFacetTest} from "./_AccountCodeStorage_Shared.t.sol";
import {AccountStoreFacetWrapper} from "./_AccountCodeStorage_Shared.t.sol";
import {Constants} from "system-contracts/test-forge/constants.sol";
import {ContractTransaction} from "@ethersproject/contracts";

contract ConstructingCodeHashTest is AccountCodeFacetTest {
    function test_successfullyStored() public {
        ContractTransaction expected = Constants.CONSTRUCTING_BYTECODE_HASH;

        accountCodeStorage.connect(deployerAccount).storeAccountConstructingCodeHash(
            Constants.RANDOM_ADDRESS,
            Constants.CONSTRUCTED_BYTECODE_HASH
        );
        ContractTransaction received = accountCodeStorage.getRawCodeHash(Constants.RANDOM_ADDRESS);

        assertEq(expected, received, "Invalid code hash");
    }

    function test_failedToSetWithConstructedBytecode() public {
        vm.expectRevert("InvalidCodeHash");

        accountCodeStorage.connect(deployerAccount).storeAccountConstructingCodeHash(
            Constants.RANDOM_ADDRESS,
            Constants.CONSTRUCTING_BYTECODE_HASH
        );
    }

    function test_nonDeployerFailedToCall() public {
        vm.expectRevert("Unauthorized");

        accountCodeStorage.storeAccountConstructingCodeHash(
            Constants.RANDOM_ADDRESS,
            Constants.CONSTRUCTED_BYTECODE_HASH
        );
    }
}
