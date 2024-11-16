import { TEEEncryptionService } from '../services/tee-encryption-service';
import { ethers } from 'ethers';

async function main() {
    // Initialize TEE service
    const teeService = new TEEEncryptionService();
    await teeService.initialize();
    
    // Listen for encryption requests
    const bridge = new ethers.Contract(
        BRIDGE_ADDRESS,
        BRIDGE_ABI,
        provider
    );
    
    bridge.on('EncryptionRequested', async (requestId, requester, value) => {
        try {
            // Verify TEE integrity
            const isValid = await teeService.verifyAttestation();
            if (!isValid) {
                console.error('TEE attestation failed');
                return;
            }
            
            // Generate encryption inside TEE
            const { encryptedValue, proof } = 
                await teeService.generateFHEEncryption(value);
            
            // Get current attestation
            const attestation = await teeService.getAttestation();
            
            // Submit back to bridge
            await bridge.submitEncryption(
                requestId,
                encryptedValue,
                proof,
                attestation
            );
            
        } catch (error) {
            console.error('Error processing encryption:', error);
        }
    });
}

main(); 