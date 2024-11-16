import { ethers } from "hardhat";

async function main() {
  // Deploy on non-FHE chain
  const token = await ethers.deployContract("IERC20", ["USD Token", "USDT"]);
  await token.waitForDeployment();

  const nonFHEVault = await ethers.deployContract("NonFHEPaymentVault", [
    token.address,
    "HYPERLANE_MAILBOX_ADDRESS",
    FHE_CHAIN_ID,
    FHE_VAULT_ADDRESS
  ]);
  await nonFHEVault.waitForDeployment();

  console.log("NonFHEPaymentVault deployed to:", nonFHEVault.address);

  // Deploy on FHE chain
  const fheVault = await ethers.deployContract("PaymentVault", [
    "FHE_TOKEN_ADDRESS"
  ]);
  await fheVault.waitForDeployment();

  const handler = await ethers.deployContract("FHEHyperlaneHandler", [
    fheVault.address
  ]);
  await handler.waitForDeployment();

  console.log("FHE PaymentVault deployed to:", fheVault.address);
  console.log("FHE Hyperlane Handler deployed to:", handler.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 