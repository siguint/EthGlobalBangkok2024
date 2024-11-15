// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract PaymentVault {
    address public owner;
    IERC20 public immutable token;
    uint256 public totalDeposits;
    uint256 public immutable subscriptionPrice;

    mapping(address => uint256) public deposits;

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(uint256 amount);

    constructor(address _token, uint256 _subscriptionPrice) {
        owner = msg.sender;
        token = IERC20(_token);
        subscriptionPrice = _subscriptionPrice;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can withdraw");
        _;
    }

    function deposit() external {
        require(token.transferFrom(msg.sender, address(this), subscriptionPrice), "Transfer failed");
        
        deposits[msg.sender] += subscriptionPrice;
        totalDeposits += subscriptionPrice;
        
        emit Deposited(msg.sender, subscriptionPrice);
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= totalDeposits, "Insufficient balance");
        require(token.transfer(owner, amount), "Transfer failed");
        
        totalDeposits -= amount;
        
        emit Withdrawn(amount);
    }
}
