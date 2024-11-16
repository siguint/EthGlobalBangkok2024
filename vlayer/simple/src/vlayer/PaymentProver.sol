// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Prover} from "vlayer-0.1.0/Prover.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {PaymentVault} from "../PaymentVault.sol";

contract PaymentProver is Prover {
    IERC20 immutable token;
    PaymentVault immutable vault;

    constructor(IERC20 _token, PaymentVault _vault) {
        token = _token;
        vault = _vault;
    }

    function proveSubscription(uint256 serviceId, address subscriber) public returns (Proof memory, bytes32) {
        // Verify the subscription is active
        require(vault.isSubscriptionActive(serviceId, subscriber), "Subscription is not active");

        return (proof(), keccak256(abi.encodePacked(subscriber)));
    }
}
