import hardhat from "hardhat";
const { ethers } = hardhat as any;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with", deployer.address);

  const members = [deployer.address];
  const monthly = ethers.parseEther("0.01");
  const required = 1;

  const Factory = await ethers.getContractFactory("LotteryPoolV1");
  const pool = await Factory.deploy(members, monthly, required);
  await pool.waitForDeployment();

  console.log("Deployed LotteryPoolV1 to:", await pool.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
