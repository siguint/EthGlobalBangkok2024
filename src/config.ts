export const config = {
  development: {
    rpcUrl: 'http://localhost:8545',
    explorerUrl: 'http://localhost:4000'
  },
  production: {
    rpcUrl: 'https://api.explorer.rivest.inco.org/api/eth-rpc',
    explorerUrl: 'https://explorer.rivest.inco.org'
  }
}[process.env.NODE_ENV || 'development']; 