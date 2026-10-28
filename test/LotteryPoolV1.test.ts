import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.connect();

const MONTHLY = ethers.parseEther("0.1");
const REQUIRED = 2;

async function deployPool() {
  const [a, b, c, d, outsider] = await ethers.getSigners();
  const pool = await ethers.deployContract("LotteryPoolV1", [
    [a.address, b.address, c.address],
    MONTHLY,
    REQUIRED,
  ]);
  return { pool, a, b, c, d, outsider };
}

// a contributes and b + c approve it, so `a` is allowed to buy lottery tickets.
async function poolWithApprovedContribution() {
  const ctx = await deployPool();
  const { pool, a, b, c } = ctx;
  await pool.connect(a).contribute({ value: MONTHLY });
  await pool.connect(b).approveContribution(a.address, 0);
  await pool.connect(c).approveContribution(a.address, 0);
  return ctx;
}

describe("LotteryPoolV1", function () {
  describe("deployment", function () {
    it("stores members, monthly contribution and required approvals", async function () {
      const { pool, a, b, c, outsider } = await deployPool();

      expect(await pool.getMemberCount()).to.equal(3n);
      expect(await pool.monthlyContribution()).to.equal(MONTHLY);
      expect(await pool.requiredApprovals()).to.equal(BigInt(REQUIRED));
      expect(await pool.isMember(a.address)).to.equal(true);
      expect(await pool.isMember(b.address)).to.equal(true);
      expect(await pool.isMember(c.address)).to.equal(true);
      expect(await pool.isMember(outsider.address)).to.equal(false);
    });

    it("rejects an empty member list", async function () {
      await expect(
        ethers.deployContract("LotteryPoolV1", [[], MONTHLY, 1]),
      ).to.be.revertedWith("Se necesita al menos 1 miembro");
    });

    it("rejects zero or more approvals than members", async function () {
      const [a, b] = await ethers.getSigners();
      await expect(
        ethers.deployContract("LotteryPoolV1", [[a.address, b.address], MONTHLY, 0]),
      ).to.be.revertedWith("Aprobaciones invalidas");
      await expect(
        ethers.deployContract("LotteryPoolV1", [[a.address, b.address], MONTHLY, 3]),
      ).to.be.revertedWith("Aprobaciones invalidas");
    });
  });

  describe("contributions", function () {
    it("lets a member contribute the exact monthly amount", async function () {
      const { pool, a } = await deployPool();

      await expect(pool.connect(a).contribute({ value: MONTHLY }))
        .to.emit(pool, "ContributionMade")
        .withArgs(a.address, MONTHLY, 0n);

      const contribution = await pool.contributions(a.address, 0);
      expect(contribution.amount).to.equal(MONTHLY);
      expect(contribution.approved).to.equal(false);
      expect(await pool.getPoolBalance()).to.equal(MONTHLY);
    });

    it("rejects a wrong amount", async function () {
      const { pool, a } = await deployPool();
      await expect(
        pool.connect(a).contribute({ value: MONTHLY + 1n }),
      ).to.be.revertedWith("Monto incorrecto");
    });

    it("rejects contributions from non-members", async function () {
      const { pool, outsider } = await deployPool();
      await expect(
        pool.connect(outsider).contribute({ value: MONTHLY }),
      ).to.be.revertedWith("Solo miembros");
    });
  });

  describe("contribution approvals", function () {
    it("approves a contribution once enough other members approve it", async function () {
      const { pool, a, b, c } = await deployPool();
      await pool.connect(a).contribute({ value: MONTHLY });

      await pool.connect(b).approveContribution(a.address, 0);
      expect((await pool.contributions(a.address, 0)).approved).to.equal(false);

      await pool.connect(c).approveContribution(a.address, 0);
      expect((await pool.contributions(a.address, 0)).approved).to.equal(true);
      expect(await pool.getApprovalCount(a.address, 0)).to.equal(2n);
    });

    it("does not let a member approve their own contribution", async function () {
      const { pool, a } = await deployPool();
      await pool.connect(a).contribute({ value: MONTHLY });
      await expect(
        pool.connect(a).approveContribution(a.address, 0),
      ).to.be.revertedWith("No puedes aprobar tu propia contribucion");
    });

    it("does not let the same member approve twice", async function () {
      const { pool, a, b } = await deployPool();
      await pool.connect(a).contribute({ value: MONTHLY });
      await pool.connect(b).approveContribution(a.address, 0);
      await expect(
        pool.connect(b).approveContribution(a.address, 0),
      ).to.be.revertedWith("Ya aprobaste");
    });

    it("rejects approving a contribution that does not exist", async function () {
      const { pool, a, b } = await deployPool();
      await expect(
        pool.connect(b).approveContribution(a.address, 0),
      ).to.be.revertedWith("Contribucion no existe");
    });
  });

  describe("lottery purchases", function () {
    it("requires an approved contribution before proposing a purchase", async function () {
      const { pool, a } = await deployPool();
      await pool.connect(a).contribute({ value: MONTHLY });
      await expect(
        pool.connect(a).purchaseLottery(MONTHLY, "Euromillones"),
      ).to.be.revertedWith("Debes tener contribuciones aprobadas");
    });

    it("rejects a purchase larger than the pool balance", async function () {
      const { pool, a } = await poolWithApprovedContribution();
      await expect(
        pool.connect(a).purchaseLottery(MONTHLY + 1n, "Demasiado"),
      ).to.be.revertedWith("Fondos insuficientes");
    });

    it("pays the buyer once, after enough approvals from other members", async function () {
      const { pool, a, b, c } = await poolWithApprovedContribution();

      await pool.connect(a).purchaseLottery(MONTHLY, "Euromillones");
      const purchase = await pool.lotteryPurchases(0);
      expect(purchase.purchasedBy).to.equal(a.address);
      expect(purchase.executed).to.equal(false);

      // Nothing is paid by merely proposing the purchase.
      expect(await pool.getPoolBalance()).to.equal(MONTHLY);

      await pool.connect(b).approvePurchase(0);
      await expect(pool.connect(b).executePurchase(0)).to.be.revertedWith(
        "Compra no aprobada por suficientes miembros",
      );

      await pool.connect(c).approvePurchase(0);
      expect(await pool.getPurchaseApprovalCount(0)).to.equal(2n);

      // `b` pays the gas, so `a`'s balance changes by exactly the purchase amount.
      const before = await ethers.provider.getBalance(a.address);
      await pool.connect(b).executePurchase(0);
      const after = await ethers.provider.getBalance(a.address);

      expect(after - before).to.equal(MONTHLY);
      expect(await pool.getPoolBalance()).to.equal(0n);
      expect((await pool.lotteryPurchases(0)).executed).to.equal(true);
    });

    it("prevents a double payout of the same purchase", async function () {
      const { pool, a, b, c } = await poolWithApprovedContribution();
      // Extra funds in the pool, so a second payout would otherwise be possible.
      await pool.connect(b).contribute({ value: MONTHLY });

      await pool.connect(a).purchaseLottery(MONTHLY, "Euromillones");
      await pool.connect(b).approvePurchase(0);
      await pool.connect(c).approvePurchase(0);
      await pool.connect(b).executePurchase(0);

      await expect(pool.connect(c).executePurchase(0)).to.be.revertedWith(
        "Compra ya ejecutada",
      );
      expect(await pool.getPoolBalance()).to.equal(MONTHLY);
    });

    it("does not let the buyer approve their own purchase", async function () {
      const { pool, a } = await poolWithApprovedContribution();
      await pool.connect(a).purchaseLottery(MONTHLY, "Euromillones");
      await expect(pool.connect(a).approvePurchase(0)).to.be.revertedWith(
        "No puedes aprobar tu propia compra",
      );
    });

    it("does not let the same member approve a purchase twice", async function () {
      const { pool, a, b } = await poolWithApprovedContribution();
      await pool.connect(a).purchaseLottery(MONTHLY, "Euromillones");
      await pool.connect(b).approvePurchase(0);
      await expect(pool.connect(b).approvePurchase(0)).to.be.revertedWith(
        "Ya aprobaste compra",
      );
    });

    it("rejects actions from non-members", async function () {
      const { pool, outsider } = await poolWithApprovedContribution();
      await expect(
        pool.connect(outsider).purchaseLottery(MONTHLY, "Colado"),
      ).to.be.revertedWith("Solo miembros");
      await expect(pool.connect(outsider).executePurchase(0)).to.be.revertedWith(
        "Solo miembros",
      );
    });
  });

  describe("member proposals", function () {
    it("adds a member once a majority approves", async function () {
      const { pool, a, b, d } = await deployPool();

      await expect(pool.connect(a).proposeAddMember(d.address))
        .to.emit(pool, "MemberProposalCreated")
        .withArgs(0n, d.address, true, a.address);

      // 3 members => majority is 2.
      await pool.connect(a).approveMemberProposal(0);
      expect(await pool.isMember(d.address)).to.equal(false);

      await expect(pool.connect(b).approveMemberProposal(0))
        .to.emit(pool, "MemberAdded")
        .withArgs(d.address);

      expect(await pool.isMember(d.address)).to.equal(true);
      expect(await pool.getMemberCount()).to.equal(4n);
    });

    it("removes a member once a majority approves", async function () {
      const { pool, a, b, c } = await deployPool();

      await pool.connect(a).proposeRemoveMember(c.address);
      await pool.connect(a).approveMemberProposal(0);
      await expect(pool.connect(b).approveMemberProposal(0))
        .to.emit(pool, "MemberRemoved")
        .withArgs(c.address);

      expect(await pool.isMember(c.address)).to.equal(false);
    });

    it("does not let a single member change the membership alone", async function () {
      const { pool, a, d } = await deployPool();
      await pool.connect(a).proposeAddMember(d.address);
      await pool.connect(a).approveMemberProposal(0);
      expect(await pool.isMember(d.address)).to.equal(false);
      await expect(pool.connect(a).approveMemberProposal(0)).to.be.revertedWith(
        "Ya aprobaste",
      );
    });

    it("rejects invalid proposals", async function () {
      const { pool, a, d, outsider } = await deployPool();
      await expect(pool.connect(a).proposeAddMember(a.address)).to.be.revertedWith(
        "Ya miembro",
      );
      await expect(
        pool.connect(a).proposeRemoveMember(d.address),
      ).to.be.revertedWith("No es miembro");
      await expect(
        pool.connect(outsider).proposeAddMember(d.address),
      ).to.be.revertedWith("Solo miembros");
    });

    it("does not allow approving an already executed proposal", async function () {
      const { pool, a, b, c, d } = await deployPool();
      await pool.connect(a).proposeAddMember(d.address);
      await pool.connect(a).approveMemberProposal(0);
      await pool.connect(b).approveMemberProposal(0);
      await expect(pool.connect(c).approveMemberProposal(0)).to.be.revertedWith(
        "Propuesta ya ejecutada",
      );
    });
  });
});
