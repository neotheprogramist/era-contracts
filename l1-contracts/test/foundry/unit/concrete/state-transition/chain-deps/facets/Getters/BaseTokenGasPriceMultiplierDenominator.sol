// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {GettersFacetTest} from "./_Getters_Shared.t.sol";

contract BaseTokenGasPriceMultiplierDenominator is GettersFacetTest {
    function test() public {
        uint128 expected = 123;
        gettersFacetWrapper.util_setGasDenominator(expected);

        uint128 received = gettersFacet.baseTokenGasPriceMultiplierDenominator();

        assertEq(expected, received, "Denominator is incorrect");
    }
}
