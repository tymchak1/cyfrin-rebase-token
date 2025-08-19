// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Anastasia Tymchak
 * @notice This is a cross-chain rebase token that incetvises users to deposit into a vault and gain interest in rewards
 * @notice  The interest rate in this smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositingERC20ERC20ERC20
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 newInterestRate, uint256 oldInterestRate);

    uint256 private constant PRECICION_FACTOR = 1e27;
    uint256 private s_interestRate = (5 * PRECICION_FACTOR) / 1e8;
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 timestamp) private s_userLastUpdatedTimestamp;

    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Sets the interest rate
     * @param _newInterestRate The new interest rate to set
     * @dev The intrest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
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
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burns tokens from the user when they withdraw from the vault
     * @param _from The address to burn tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
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

    /**
     * @notice Transfers tokens from the sender to the recipient
     * @param _recepient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return bool Returns true if the transfer was successful
     * @dev If the amount is set to max uint256, it transfers the entire balance of the sender
     * @dev If the recipient has no balance, it sets their interest rate to the sender's interest rate
     */
    function transfer(address _recepient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recepient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recepient) == 0) {
            s_userInterestRate[_recepient] = s_userInterestRate[msg.sender];
            // s_userInterestRate[_recepient] = s_interestRate;
            // s_userLastUpdatedTimestamp[_recepient] = block.timestamp;
        }
        return super.transfer(_recepient, _amount);
    }

    /**
     * @notice Transfers tokens from the sender to the recipient
     * @param _sender The address of the sender
     * @param _recepient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @dev If the amount is set to max uint256, it transfers the entire balance of the sender
     * @dev If the recipient has no balance, it sets their interest rate to the sender's interest rate
     */
    function transferFrom(address _sender, address _recepient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recepient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recepient) == 0) {
            s_userInterestRate[_recepient] = s_userInterestRate[msg.sender];
            // s_userInterestRate[_recepient] = s_interestRate;
            // s_userLastUpdatedTimestamp[_recepient] = block.timestamp;
        }
        return super.transferFrom(_sender, _recepient, _amount);
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
     * @return The current interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Returns the interest rate for a specific user
     * @param _user The address of the user
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Returns the principle balance of the user
     * @param _user The address of the user
     * @return The principle balance of the user
     */
    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
}
