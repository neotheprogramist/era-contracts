// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

library Utils {
    bytes32 constant EMPTY_PREPUBLISHED_COMMITMENT = 0x0000000000000000000000000000000000000000000000000000000000000000;

    function randomBytes32(bytes memory seed) public view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, seed));
    }

    function getDefaultBlobCommitment() public pure returns (bytes memory) {
        bytes16 blobOpeningPoint = 0x7142c5851421a2dc03dde0aabdb0ffdb;
        bytes32 blobClaimedValue = 0x1e5eea3bbb85517461c1d1c7b84c7c2cec050662a5e81a71d5d7e2766eaff2f0;
        bytes
            memory commitment = hex"ad5a32c9486ad7ab553916b36b742ed89daffd4538d95f4fc8a6c5c07d11f4102e34b3c579d9b4eb6c295a78e484d3bf";
        bytes
            memory blobProof = hex"b7565b1cf204d9f35cec98a582b8a15a1adff6d21f3a3a6eb6af5a91f0a385c069b34feb70bea141038dc7faca5ed364";

        return abi.encodePacked(blobOpeningPoint, blobClaimedValue, commitment, blobProof);
    }

    function makeBytesArrayOfLength(uint256 len) internal returns (bytes calldata arr) {
        assembly {
            arr.length := len
        }
    }
}
