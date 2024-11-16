import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const deployed = await deploy("ConfidentialERC20", {
    from: deployer,
    log: true,
  });

  console.log(`ConfidentialToken contract deployed at: ${deployed.address}`);

  const deployedPaymentVault = await deploy("PaymentVault", {
    from: deployer,
    log: true,
    args: [deployed.address],
  });

  console.log(`PaymentVault contract deployed at: ${deployedPaymentVault.address}`);
};

export default func;
func.id = "deploy_confidentialERC20";
func.tags = ["ConfidentialToken"];
