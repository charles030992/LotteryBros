import { network } from "hardhat";

const { ethers } = await network.connect();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with", deployer.address);

  const members = [deployer.address];
  const monthly = ethers.parseEther("0.01");
  const required = 1;

  const pool = await ethers.deployContract("LotteryPoolV1", [
    members,
    monthly,
    required,
  ]);
  await pool.waitForDeployment();

  console.log("Deployed LotteryPoolV1 to:", await pool.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
