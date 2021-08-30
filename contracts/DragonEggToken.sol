// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./libs/ERC20.sol";

// The wee Dragon Egg token.
contract DragonEggToken is ERC20('Dragon Egg', 'DREGG') {

    constructor() {
        _mint(address(0x306e5F7FAe63a86b3E2D88F94cCa8D7614684D91), uint256(1000000000000000000000));
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}