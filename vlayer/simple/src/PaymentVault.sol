// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract PaymentVault {
    address public owner;
    IERC20 public immutable token;
    uint256 public totalDeposits;
    uint256 public nextServiceId;

    struct Service {
        uint256 subscriptionPrice;
        address receiver;
        bool isActive;
    }

    mapping(uint256 => Service) public services; // serviceId => Service
    mapping(uint256 => mapping(address => uint256)) public deposits; // serviceId => user => amount
    mapping(uint256 => mapping(address => uint256)) public lastPaymentTimestamp; // serviceId => user => timestamp
    mapping(uint256 => uint256) public serviceTotalDeposits; // serviceId => total deposits

    event ServiceRegistered(uint256 indexed serviceId, address indexed receiver, uint256 price);
    event ServicePriceChanged(uint256 indexed serviceId, uint256 oldPrice, uint256 newPrice);
    event ServiceDeactivated(uint256 indexed serviceId);
    event Deposited(uint256 indexed serviceId, address indexed depositor, uint256 amount);
    event Withdrawn(uint256 indexed serviceId, address indexed receiver, uint256 amount);

    uint256 constant SUBSCRIPTION_PERIOD = 30 days;

    constructor(address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyServiceReceiver(uint256 serviceId) {
        require(msg.sender == services[serviceId].receiver, "Only service receiver");
        _;
    }

    function registerService(address receiver, uint256 price) external onlyOwner returns (uint256) {
        uint256 serviceId = nextServiceId++;
        services[serviceId] = Service({
            subscriptionPrice: price,
            receiver: receiver,
            isActive: true
        });
        emit ServiceRegistered(serviceId, receiver, price);
        return serviceId;
    }

    function setSubscriptionPrice(uint256 serviceId, uint256 newPrice) external onlyServiceReceiver(serviceId) {
        require(services[serviceId].isActive, "Service not active");
        uint256 oldPrice = services[serviceId].subscriptionPrice;
        services[serviceId].subscriptionPrice = newPrice;
        emit ServicePriceChanged(serviceId, oldPrice, newPrice);
    }

    function deactivateService(uint256 serviceId) external onlyOwner {
        require(services[serviceId].isActive, "Service not active");
        services[serviceId].isActive = false;
        emit ServiceDeactivated(serviceId);
    }

    function subscribe(uint256 serviceId) external {
        require(services[serviceId].isActive, "Service not active");
        uint256 price = services[serviceId].subscriptionPrice;
        
        require(token.transferFrom(msg.sender, address(this), price), "Transfer failed");
        
        deposits[serviceId][msg.sender] += price;
        serviceTotalDeposits[serviceId] += price;
        totalDeposits += price;
        lastPaymentTimestamp[serviceId][msg.sender] = block.timestamp;
        
        emit Deposited(serviceId, msg.sender, price);
    }

    function withdraw(uint256 serviceId, uint256 amount) external onlyServiceReceiver(serviceId) {
        require(amount <= serviceTotalDeposits[serviceId], "Insufficient balance");
        require(token.transfer(services[serviceId].receiver, amount), "Transfer failed");
        
        serviceTotalDeposits[serviceId] -= amount;
        totalDeposits -= amount;
        
        emit Withdrawn(serviceId, services[serviceId].receiver, amount);
    }

    function isSubscriptionActive(uint256 serviceId, address subscriber) public view returns (bool) {
        if (!services[serviceId].isActive) return false;
        if (deposits[serviceId][subscriber] == 0) return false;
        return block.timestamp <= lastPaymentTimestamp[serviceId][subscriber] + SUBSCRIPTION_PERIOD;
    }
}
