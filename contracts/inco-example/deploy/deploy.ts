import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const deployedConfidentialERC20 = await deploy("ConfidentialERC20", {
    from: deployer,
    log: true,
  });

  const deployedPaymentVault = await deploy("PaymentVault", {
    from: deployer,
    args: [deployedConfidentialERC20.address],
    log: true,
  });
  
  console.log(`ConfidentialToken contract deployed at: ${deployedConfidentialERC20.address}`);
  console.log(`PaymentVault contract deployed at: ${deployedPaymentVault.address}`);
};

export default func;
func.id = "deploy_confidentialERC20_paymentVault";
func.tags = ["ConfidentialToken", "PaymentVault"];
