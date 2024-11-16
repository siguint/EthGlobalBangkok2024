// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@hyperlane-xyz/core/interfaces/IMailbox.sol";
import "@hyperlane-xyz/core/interfaces/IInterchainSecurityModule.sol";

contract NonFHEPaymentVault {
    address public owner;
    IERC20 public immutable token;
    uint256 public totalDeposits;
    uint256 public nextServiceId;
    IMailbox public mailbox;
    uint32 public fheChainId;
    address public fheVaultAddress;

    struct Service {
        uint64 subscriptionPrice;
        address receiver;
        bool isActive;
        uint64 donations;
    }

    mapping(uint256 => Service) public services;
    mapping(uint256 => mapping(address => uint256)) private deposits;
    mapping(uint256 => mapping(address => uint256)) private lastPaymentTimestamp;
    mapping(uint256 => uint256) private serviceTotalDeposits;

    event ServiceRegistered(uint256 indexed serviceId, address indexed receiver);
    event ServicePriceChanged(uint256 indexed serviceId);
    event ServiceDeactivated(uint256 indexed serviceId);
    event Deposited(uint256 indexed serviceId, address indexed depositor);
    event Withdrawn(uint256 indexed serviceId, address indexed receiver);
    event Donated(uint256 indexed serviceId, address indexed donor);
    event MessageSent(uint32 destinationDomain, bytes32 messageId);

    uint256 constant SUBSCRIPTION_PERIOD = 30 days;

    constructor(
        address _token,
        address _mailbox,
        uint32 _fheChainId,
        address _fheVaultAddress
    ) {
        owner = msg.sender;
        token = IERC20(_token);
        mailbox = IMailbox(_mailbox);
        fheChainId = _fheChainId;
        fheVaultAddress = _fheVaultAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    function registerService(address receiver, uint64 price) external onlyOwner returns (uint256) {
        uint256 serviceId = nextServiceId++;
        services[serviceId] = Service({
            subscriptionPrice: price,
            receiver: receiver,
            isActive: true,
            donations: 0
        });
        
        // Send message to FHE chain to register service
        bytes memory message = abi.encode("REGISTER_SERVICE", serviceId, receiver, price);
        bytes32 messageId = mailbox.dispatch(
            fheChainId,
            bytes32(uint256(uint160(fheVaultAddress))),
            message
        );
        
        emit ServiceRegistered(serviceId, receiver);
        emit MessageSent(fheChainId, messageId);
        return serviceId;
    }

    function subscribe(uint256 serviceId) external {
        require(services[serviceId].isActive, "Service not active");
        uint64 price = services[serviceId].subscriptionPrice;
        
        require(token.transferFrom(msg.sender, address(this), price), "Transfer failed");
        
        deposits[serviceId][msg.sender] += price;
        serviceTotalDeposits[serviceId] += price;
        totalDeposits += price;
        lastPaymentTimestamp[serviceId][msg.sender] = block.timestamp;
        
        // Send message to FHE chain about subscription
        bytes memory message = abi.encode("SUBSCRIBE", serviceId, msg.sender, price);
        bytes32 messageId = mailbox.dispatch(
            fheChainId,
            bytes32(uint256(uint160(fheVaultAddress))),
            message
        );
        
        emit Deposited(serviceId, msg.sender);
        emit MessageSent(fheChainId, messageId);
    }

    // Add other functions like donate, withdraw, etc. with similar Hyperlane messaging pattern
} 