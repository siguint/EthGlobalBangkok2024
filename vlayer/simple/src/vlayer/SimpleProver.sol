// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Prover} from "vlayer-0.1.0/Prover.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {PaymentVault} from "../../PaymentsVault.sol";

contract SimpleProver is Prover {
    IERC20 immutable token;
    PaymentVault immutable vault;
    uint256 immutable subscriptionPrice;

    constructor(IERC20 _token, PaymentVault _vault, uint256 _blockNo) {
        token = _token;
        vault = _vault;
        blockNo = _blockNo;
        subscriptionPrice = vault.subscriptionPrice();
    }

    function proveDeposit(address depositor) public returns (Proof memory, bytes32) {
        uint256 depositAmount = vault.deposits(depositor);
        
        // Verify the deposit exists and matches subscription price
        require(depositAmount == subscriptionPrice, "Deposit amount does not match subscription price");

        return (proof(), keccak256(abi.encodePacked(depositor)));
    }
}
