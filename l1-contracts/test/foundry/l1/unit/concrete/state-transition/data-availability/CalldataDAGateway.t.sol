// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Utils} from "../../Utils/Utils.sol";
import {DummyCalldataDAGateway} from "contracts/dev-contracts/test/DummyCalldataDAGateway.sol";

contract CalldataDAGatewayTest is Test {
    DummyCalldataDAGateway internal dummyCalldata;
    uint256 constant BLOB_SIZE_BYTES = 126_976;

    function setUp() public {
        dummyCalldata = new DummyCalldataDAGateway();
    }

    function test_processCalldataDAPubdataTooSmall() public {
        uint256 blobsProvided = 2;
        bytes32 fullPubdataHash;
        uint256 maxBlobsSupported;
        bytes memory pubdataInput;

        vm.expectRevert("pubdata too small");
        dummyCalldata.processCalldataDA(blobsProvided, fullPubdataHash, maxBlobsSupported, pubdataInput);
    }

    function test_processCalldataDAInvalidPubdataLength() public {
        uint256 blobsProvided = 1;
        bytes32 fullPubdataHash;
        uint256 maxBlobsSupported;
        bytes memory pubdataInput = makeBytesArrayOfLength(BLOB_SIZE_BYTES + 33);

        vm.expectRevert(bytes("cz"));
        dummyCalldata.processCalldataDA(blobsProvided, fullPubdataHash, maxBlobsSupported, pubdataInput);
    }

    function test_processCalldataDAInvalidPubdataHash() public {
        uint256 blobsProvided = 1;
        uint256 maxBlobsSupported = 6;
        bytes memory pubdataInputWithoutBlobCommitment = "verifydonttrustzkistheendgamemagicmoonmath";
        bytes32 blobCommitment = Utils.randomBytes32("blobCommitment");
        bytes memory pubdataInput = abi.encodePacked(pubdataInputWithoutBlobCommitment, blobCommitment);
        bytes32 fullPubdataHash = keccak256(pubdataInput);

        vm.expectRevert(bytes("wp"));
        dummyCalldata.processCalldataDA(blobsProvided, fullPubdataHash, maxBlobsSupported, pubdataInput);
    }

    function test_processCalldataDA() public {
        uint256 blobsProvided = 1;
        uint256 maxBlobsSupported = 6;
        bytes memory pubdataInputWithoutBlobCommitment = "verifydonttrustzkistheendgamemagicmoonmath";
        bytes32 blobCommitment = Utils.randomBytes32("blobCommitment");
        bytes memory pubdataInput = abi.encodePacked(pubdataInputWithoutBlobCommitment, blobCommitment);
        bytes32 fullPubdataHash = keccak256(pubdataInputWithoutBlobCommitment);

        (bytes32[] memory blobCommitments, bytes memory pubdata) = dummyCalldata.processCalldataDA(
            blobsProvided,
            fullPubdataHash,
            maxBlobsSupported,
            pubdataInput
        );

        assertEq(blobCommitments.length, 6, "Invalid blob Commitment length");
        assertEq(blobCommitments[0], blobCommitment, "Invalid blob Commitment 1");
        assertEq(blobCommitments[1], bytes32(0), "Invalid blob Commitment 2");
        assertEq(blobCommitments[2], bytes32(0), "Invalid blob Commitment 3");
        assertEq(blobCommitments[3], bytes32(0), "Invalid blob Commitment 4");
        assertEq(blobCommitments[4], bytes32(0), "Invalid blob Commitment 5");
        assertEq(blobCommitments[5], bytes32(0), "Invalid blob Commitment 6");
        assertEq(pubdata, pubdataInputWithoutBlobCommitment, "Invalid pubdata");
    }

    function makeBytesArrayOfLength(uint256 len) internal returns (bytes calldata arr) {
        assembly {
            arr.length := len
        }
    }
}