// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "fhevm/lib/TFHE.sol";
import "./ConfidentialERC20.sol";

contract PaymentVault {
    address public owner;
    ConfidentialERC20 public immutable token;
    euint64 public totalDeposits;
    uint256 public nextServiceId;

    struct Service {
        euint64 subscriptionPrice;
        address receiver;
        bool isActive;
        euint64 donations; // Track encrypted donations for each service
    }

    mapping(uint256 => Service) public services; // serviceId => Service
    mapping(uint256 => mapping(eaddress => euint64)) private deposits; // serviceId => user => amount
    mapping(uint256 => mapping(eaddress => uint256)) private lastPaymentTimestamp; // serviceId => user => timestamp
    mapping(uint256 => euint64) private serviceTotalDeposits; // serviceId => total deposits

    event ServiceRegistered(uint256 indexed serviceId, address indexed receiver);
    event ServicePriceChanged(uint256 indexed serviceId);
    event ServiceDeactivated(uint256 indexed serviceId);
    event Deposited(uint256 indexed serviceId, eaddress indexed depositor);
    event Withdrawn(uint256 indexed serviceId, address indexed receiver);
    event Donated(uint256 indexed serviceId, eaddress indexed donor);

    uint256 constant SUBSCRIPTION_PERIOD = 30 days;

    constructor(address _token) {
        owner = msg.sender;
        token = ConfidentialERC20(_token);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyServiceReceiver(uint256 serviceId) {
        require(msg.sender == services[serviceId].receiver, "Only service receiver");
        _;
    }

    function registerService(address receiver, einput encryptedPrice, bytes calldata priceProof) external onlyOwner returns (uint256) {
        uint256 serviceId = nextServiceId++;
        services[serviceId] = Service({
            subscriptionPrice: TFHE.asEuint64(encryptedPrice, priceProof),
            receiver: receiver,
            isActive: true,
            donations: TFHE.asEuint64(0)
        });
        emit ServiceRegistered(serviceId, receiver);
        return serviceId;
    }

    function setSubscriptionPrice(uint256 serviceId, einput encryptedNewPrice, bytes calldata priceProof) external onlyServiceReceiver(serviceId) {
        require(services[serviceId].isActive, "Service not active");
        services[serviceId].subscriptionPrice = TFHE.asEuint64(encryptedNewPrice, priceProof);
        emit ServicePriceChanged(serviceId);
    }

    function deactivateService(uint256 serviceId) external onlyOwner {
        require(services[serviceId].isActive, "Service not active");
        services[serviceId].isActive = false;
        emit ServiceDeactivated(serviceId);
    }

    function subscribe(uint256 serviceId, einput encryptedSubscriber, bytes calldata subscriberProof) external {
        require(services[serviceId].isActive, "Service not active");
        euint64 price = services[serviceId].subscriptionPrice;
        
        eaddress subscriber = TFHE.asEaddress(encryptedSubscriber, subscriberProof);
        require(token.transferFrom(msg.sender, address(this), price), "Transfer failed");
        
        deposits[serviceId][subscriber] = TFHE.add(deposits[serviceId][subscriber], price);
        serviceTotalDeposits[serviceId] = TFHE.add(serviceTotalDeposits[serviceId], price);
        totalDeposits = TFHE.add(totalDeposits, price);
        lastPaymentTimestamp[serviceId][subscriber] = block.timestamp;
        
        emit Deposited(serviceId, subscriber);
    }

    function donate(uint256 serviceId, einput encryptedDonor, bytes calldata donorProof, einput encryptedAmount, bytes calldata amountProof) external {
        require(services[serviceId].isActive, "Service not active");
        eaddress donor = TFHE.asEaddress(encryptedDonor, donorProof);
        euint64 amount = TFHE.asEuint64(encryptedAmount, amountProof);
        
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        services[serviceId].donations = TFHE.add(services[serviceId].donations, amount);
        serviceTotalDeposits[serviceId] = TFHE.add(serviceTotalDeposits[serviceId], amount);
        totalDeposits = TFHE.add(totalDeposits, amount);
        
        emit Donated(serviceId, donor);
    }

    function withdraw(uint256 serviceId, einput encryptedAmount, bytes calldata amountProof) external onlyServiceReceiver(serviceId) {
        euint64 amount = TFHE.asEuint64(encryptedAmount, amountProof);
        ebool canTransfer = TFHE.le(amount, serviceTotalDeposits[serviceId]);
        euint64 transferValue = TFHE.select(canTransfer, amount, TFHE.asEuint64(0));
        require(token.transfer(services[serviceId].receiver, transferValue), "Transfer failed");
        
        serviceTotalDeposits[serviceId] = TFHE.sub(serviceTotalDeposits[serviceId], amount);
        totalDeposits = TFHE.sub(totalDeposits, amount);
        
        emit Withdrawn(serviceId, services[serviceId].receiver);
    }

    function isSubscriptionActive(uint256 serviceId, einput encryptedSubscriber, bytes calldata subscriberProof) public returns (bool) {
        if (!services[serviceId].isActive) return false;
        eaddress subscriber = TFHE.asEaddress(encryptedSubscriber, subscriberProof);
        return block.timestamp <= lastPaymentTimestamp[serviceId][subscriber] + SUBSCRIPTION_PERIOD;
    }
}
