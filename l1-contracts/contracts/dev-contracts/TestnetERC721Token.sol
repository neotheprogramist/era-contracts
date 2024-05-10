// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestnetERC721Token is ERC721 {
    // add this to be excluded from coverage report
    function test() internal virtual {}

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function mint(address _to, uint256 _tokenId) public returns (bool) {
        _mint(_to, _tokenId);
        return true;
    }
}
