"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.config = void 0;
exports.config = {
    development: {
        rpcUrl: 'http://localhost:8545',
        explorerUrl: 'http://localhost:4000'
    },
    production: {
        rpcUrl: 'https://api.explorer.rivest.inco.org/api/eth-rpc',
        explorerUrl: 'https://explorer.rivest.inco.org'
    }
}[process.env.NODE_ENV || 'development'];
