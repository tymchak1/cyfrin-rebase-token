// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    error Vault__RedeemFailed();
    // mint and burn tokens(address in constructor)
    // deposit ETH -> mint
    // redeem to ETH -> burn
    // add rewards to vault

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows users to deposit ETH into the vault and get Rebase Tokens in return
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their Rebase Tokens for ETH
     * @param _amount The amount of Rebase Tokens to redeem for ETH
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRebaseToken() external view returns (address) {
        return address(i_rebaseToken);
    }
}
