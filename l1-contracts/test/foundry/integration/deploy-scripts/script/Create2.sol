// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract Create2Factory {
    function deploy(bytes memory _bytecode, bytes32 _salt) external returns (address contractAddress) {
        if (_bytecode.length == 0) {
            revert("Bytecode is not set");
        }
        uint256 salt = uint256(_salt);

        address predictedAddress = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), uint256(salt), keccak256(_bytecode))))
            )
        );

        assembly {
            contractAddress := create2(callvalue(), add(_bytecode, 0x20), mload(_bytecode), salt)

            if iszero(extcodesize(contractAddress)) {
                revert(0, 0)
            }
        }

        require(contractAddress == predictedAddress, "Addresses mismatch");
    }
}
