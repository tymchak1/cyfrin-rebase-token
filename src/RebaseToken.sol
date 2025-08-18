// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author Anastasia Tymchak
 * @notice This is a cross-chain rebase token that incetvises users to deposit into a vault and gain interest in rewards
 * @notice  The interest rate in this smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositingERC20ERC20ERC20
 */
contract RebaseToken is ERC20 {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 newInterestRate, uint256 oldInterestRate);

    uint256 private s_interestRate = 5e10;
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 timestamp) private s_userLastUpdatedTimestamp;

    uint256 private constant PRECICION_FACTOR = 1e18;
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    /**
     * @notice Sets the interest rate
     * @param _newInterestRate The new interest rate to set
     * @dev The intrest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (s_interestRate < _newInterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mints new tokens to the user when they deposit into the vault
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }
    /**
     * @notice Burns tokens from the user when they withdraw from the vault
     * @param _from The address to burn tokens from
     * @param _amount The amount of tokens to burn
     */

    function burn(address _from, uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Returns the balance of the user, including the accrued interest
     * @param _user The address of the user
     * @return The balance of the user, including the accrued interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // _balances[_user] + earned tokens
        uint256 principleBalance = super.balanceOf(_user);
        // principleAmount(1 + (userinterestRate * timeElapsed))
        // 1 + (userinterestRate * timeElapsed) = linearInterest
        uint256 linearInterest = _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECICION_FACTOR;
        return (principleBalance * linearInterest);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints the accrued interest for the user since their last interaction with protocol
     * @param _user The user to mint the accured interest to
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // first calculating with old timestamp and after updating to current, so in next calculations it would be used
        s_userLastUpdatedTimestamp[_user];
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Calculates the accumulated interest for the user since their last update
     * @param _user The address of the user
     * @return linearInterest The accumulated interest for the user since their last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        // (principleAmount) + (principleAmount * userInterestRate * timeElapsed)
        //  1 + (userinterestRate * timeElapsed)
        linearInterest = (PRECICION_FACTOR + (s_userInterestRate[_user] + timeElapsed));
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Returns the interest rate for a specific user
     * @param _user The address of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
