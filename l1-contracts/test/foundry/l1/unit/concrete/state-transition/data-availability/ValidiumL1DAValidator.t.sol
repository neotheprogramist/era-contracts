// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Utils} from "../../Utils/Utils.sol";
import {L1DAValidatorOutput} from "contracts/state-transition/chain-interfaces/IL1DAValidator.sol";
import {ValidiumL1DAValidator} from "contracts/state-transition/data-availability/ValidiumL1DAValidator.sol";

contract ValidiumL1DAValidatorTest is Test {
    ValidiumL1DAValidator internal validium;

    function setUp() public {
        validium = new ValidiumL1DAValidator();
    }

    function test_checkDAWrongInputLength() public {
        bytes memory operatorDAInput;
        uint256 maxBlobsSupported = 2;
        vm.expectRevert("ValL1DA wrong input length");
        validium.checkDA(0, 0, 0, operatorDAInput, maxBlobsSupported);
    }

    function test_checkDA(bytes32 operatorDAInput) public {
        bytes memory input = abi.encode(operatorDAInput);
        uint256 maxBlobsSupported = 2;
        L1DAValidatorOutput memory output = validium.checkDA(0, 0, 0, input, maxBlobsSupported);
        assertEq(operatorDAInput, output.stateDiffHash, "Incorrect state diff hash");
        assertEq(maxBlobsSupported, output.blobsLinearHashes.length, "Incorrect blobs linear hashes length");
        assertEq(maxBlobsSupported, output.blobsOpeningCommitments.length, "Incorrect blobs opening commitments length");
    }
}