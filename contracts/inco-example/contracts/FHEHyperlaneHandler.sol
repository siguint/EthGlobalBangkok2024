// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@hyperlane-xyz/core/interfaces/IMessageRecipient.sol";
import "fhevm/lib/TFHE.sol";
import "./PaymentVault.sol";

contract FHEHyperlaneHandler is IMessageRecipient {
    address public owner;
    PaymentVault public paymentVault;
    mapping(uint32 => bool) public authorizedOrigins;

    constructor(address _paymentVault) {
        owner = msg.sender;
        paymentVault = PaymentVault(_paymentVault);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    function addAuthorizedOrigin(uint32 origin) external onlyOwner {
        authorizedOrigins[origin] = true;
    }

    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata message
    ) external override {
        require(authorizedOrigins[origin], "Unauthorized origin chain");
        
        (string memory action, bytes memory data) = abi.decode(message, (string, bytes));
        
        if (keccak256(bytes(action)) == keccak256(bytes("REGISTER_SERVICE"))) {
            handleRegisterService(data);
        } else if (keccak256(bytes(action)) == keccak256(bytes("SUBSCRIBE"))) {
            handleSubscribe(data);
        } else if (keccak256(bytes(action)) == keccak256(bytes("ENCRYPTED_DATA"))) {
            handleEncryptedData(data);
        }
        // Add other action handlers
    }

    function handleRegisterService(bytes memory data) internal {
        (uint256 serviceId, address receiver, uint64 price) = abi.decode(data, (uint256, address, uint64));
        
        // Convert price to encrypted format
        bytes memory priceProof;
        einput encryptedPrice = TFHE.asEuint64(price, priceProof);
        
        // Register service on FHE chain
        paymentVault.registerService(receiver, encryptedPrice, priceProof);
    }

    function handleSubscribe(bytes memory data) internal {
        (uint256 serviceId, address subscriber, uint64 amount) = abi.decode(data, (uint256, address, uint64));
        
        // Convert subscriber address to encrypted format
        bytes memory subscriberProof;
        einput encryptedSubscriber = TFHE.asEaddress(bytes32(uint256(uint160(subscriber))), subscriberProof);
        
        // Process subscription on FHE chain
        paymentVault.subscribe(serviceId, encryptedSubscriber, subscriberProof);
    }

    function handleEncryptedData(bytes memory data) internal {
        (
            bytes32 requestId,
            bytes memory encryptedData,
            bytes memory proof
        ) = abi.decode(data, (bytes32, bytes, bytes));
        
        // Verify the encryption came from our trusted TEE
        require(verifyTEEProof(proof), "Invalid TEE proof");
        
        // Process the encrypted data
        einput encryptedValue = TFHE.asEuint64(encryptedData, proof);
        
        // Use the encrypted value in your FHE contract
        paymentVault.processEncryptedValue(requestId, encryptedValue);
    }

    function verifyTEEProof(bytes memory proof) internal view returns (bool) {
        // Implement verification of TEE-generated proof
        return true; // Simplified for example
    }
} 