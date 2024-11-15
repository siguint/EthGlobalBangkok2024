// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Verifier} from "vlayer-0.1.0/Verifier.sol";

import {SimpleProver} from "./SimpleProver.sol";

contract SimpleVerifier is Verifier {
    address public prover;

    mapping(bytes32 => bool) public claimed;

    constructor(address _prover) {
        prover = _prover;
    }

    function claimSubscription(Proof calldata proof, bytes32 claimerHash)
        public
        onlyVerified(prover, SimpleProver.proveDeposit.selector)
    {
        require(!claimed[claimerHash], "Already claimed");
        claimed[claimerHash] = true;
    }
}
