import { expect } from "chai";
const hre = require("hardhat");
const ethers = hre.ethers;

describe("LotteryPoolV1", function () {
  it("deploys and allows contributions/approvals", async function () {
    const [a, b, c] = await ethers.getSigners();
    const members = [a.address, b.address, c.address];

  const Factory = await ethers.getContractFactory("LotteryPoolV1");
  const monthly = ethers.parseEther("0.1");
  const required = 2;

  const pool = await Factory.deploy(members, monthly, required);
  await pool.waitForDeployment();

    // make contribution from a
  await pool.connect(a).contribute({ value: monthly });
  // read contribution via call
  const userContribs = await pool.contributions(a.address, 0);
  expect(userContribs.amount).to.equal(monthly);

  // approve from b and c
  await pool.connect(b).approveContribution(a.address, 0);
  await pool.connect(c).approveContribution(a.address, 0);

  const approved = await pool.contributions(a.address, 0);
  expect(approved.approved).to.equal(true);
  });
});
