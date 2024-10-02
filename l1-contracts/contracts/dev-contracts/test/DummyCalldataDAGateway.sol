// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {CalldataDAGateway} from "../../state-transition/data-availability/CalldataDAGateway.sol";

contract DummyCalldataDAGateway is CalldataDAGateway {
    function processCalldataDA( 
        uint256 _blobsProvided,
        bytes32 _fullPubdataHash,
        uint256 _maxBlobsSupported,
        bytes calldata _pubdataInput
    ) external returns (bytes32[] memory blobCommitments, bytes calldata _pubdata) {
        return CalldataDAGateway._processCalldataDA(_blobsProvided, _fullPubdataHash, _maxBlobsSupported, _pubdataInput);
    }
}