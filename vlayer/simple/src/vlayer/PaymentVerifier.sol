// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Verifier} from "vlayer-0.1.0/Verifier.sol";

import {PaymentProver} from "./PaymentProver.sol";

contract PaymentVerifier is Verifier {
    address public prover;

    mapping(bytes32 => bool) public claimed;

    event Claimed(bytes32 indexed claimerHash);

    constructor(address _prover) {
        prover = _prover;
    }

    function claimSubscription(Proof calldata proof, bytes32 claimerHash)
        public
        onlyVerified(prover, PaymentProver.proveSubscription.selector)
    {
        require(!claimed[claimerHash], "Already claimed");
        claimed[claimerHash] = true;
        emit Claimed(claimerHash);
    }
}
