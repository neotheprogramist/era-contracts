// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {GettersFacetTest} from "./_Getters_Shared.t.sol";
import {FeeParams, PubdataPricingMode} from "contracts/state-transition/chain-deps/ZkSyncHyperchainStorage.sol";

contract GetPubdataPricingMode is GettersFacetTest {
    function test() public {
        PubdataPricingMode expected = PubdataPricingMode.Rollup;

        FeeParams memory params = FeeParams({
            pubdataPricingMode: expected,
            batchOverheadL1Gas: 1_000_000,
            maxPubdataPerBatch: 110_000,
            maxL2GasPerBatch: 80_000_000,
            priorityTxMaxPubdata: 99_000,
            minimalL2GasPrice: 250_000_000
        });
        gettersFacetWrapper.util_setFeeParams(params);

        PubdataPricingMode received = gettersFacet.getPubdataPricingMode();

        bool result = expected == received;

        assertTrue(result, "Pubdata is incorrect");
    }
}
