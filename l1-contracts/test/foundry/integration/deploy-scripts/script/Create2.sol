contract Create2Factory {
    function deploy(bytes memory _bytecode, uint256 _salt) external returns (address contractAddress) {
        if (_bytecode.length == 0) {
            revert("Bytecode is not set");
        }

        address predictedAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(_bytecode)))))
        );

        assembly {
            contractAddress := create2(callvalue(), add(_bytecode, 0x20), mload(_bytecode), _salt)

            if iszero(extcodesize(contractAddress)) {
                revert(0, 0)
            }
        }

        require(contractAddress == predictedAddress, "Addresses missmatch");
    }
}
