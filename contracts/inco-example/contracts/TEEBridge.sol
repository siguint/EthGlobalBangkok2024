// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@hyperlane-xyz/core/interfaces/IMailbox.sol";

contract TEEBridge is Ownable {
    IMailbox public mailbox;
    address public teeOracle;
    uint32 public fheChainId;
    address public fheVaultAddress;
    
    // Store TEE attestation info
    bytes public lastAttestation;
    uint256 public lastAttestationTime;
    
    event EncryptionRequested(
        bytes32 indexed requestId,
        address indexed requester,
        uint256 value
    );
    
    event EncryptionProcessed(
        bytes32 indexed requestId,
        bytes encryptedData,
        bytes proof
    );

    constructor(
        address _mailbox,
        address _teeOracle,
        uint32 _fheChainId,
        address _fheVaultAddress
    ) {
        mailbox = IMailbox(_mailbox);
        teeOracle = _teeOracle;
        fheChainId = _fheChainId;
        fheVaultAddress = _fheVaultAddress;
    }

    modifier onlyTEEOracle() {
        require(msg.sender == teeOracle, "Only TEE Oracle");
        _;
    }

    // Request encryption of a value
    function requestEncryption(uint256 value) external returns (bytes32) {
        bytes32 requestId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            value
        ));
        
        emit EncryptionRequested(requestId, msg.sender, value);
        return requestId;
    }

    // TEE Oracle calls this with the encrypted result
    function submitEncryption(
        bytes32 requestId,
        bytes calldata encryptedData,
        bytes calldata proof,
        bytes calldata attestation
    ) external onlyTEEOracle {
        require(verifyAttestation(attestation), "Invalid attestation");
        
        // Store attestation for verification
        lastAttestation = attestation;
        lastAttestationTime = block.timestamp;
        
        emit EncryptionProcessed(requestId, encryptedData, proof);
        
        // Forward to FHE chain via Hyperlane
        bytes memory message = abi.encode(
            "ENCRYPTED_DATA",
            requestId,
            encryptedData,
            proof
        );
        
        mailbox.dispatch(
            fheChainId,
            bytes32(uint256(uint160(fheVaultAddress))),
            message
        );
    }

    // Verify the TEE attestation
    function verifyAttestation(bytes calldata attestation) 
        internal 
        view 
        returns (bool) 
    {
        // Implement attestation verification logic
        // This would verify the TEE hasn't been compromised
        return true; // Simplified for example
    }
} 