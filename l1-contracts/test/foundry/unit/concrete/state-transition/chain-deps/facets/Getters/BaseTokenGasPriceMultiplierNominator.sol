// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {GettersFacetTest} from "./_Getters_Shared.t.sol";

contract BaseTokenGasPriceMultiplierNominator is GettersFacetTest {
    function test() public {
        uint128 expected = 123;
        gettersFacetWrapper.util_setGasNominator(expected);

        uint128 received = gettersFacet.baseTokenGasPriceMultiplierNominator();

        assertEq(expected, received, "Nominator is incorrect");
    }
}
