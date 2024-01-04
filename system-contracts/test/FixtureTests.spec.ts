import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getWallets } from "./shared/utils";

describe("FixtureTests", function () {
  async function getFirstWallet() {
    const wallet = getWallets()[0];
    return wallet;
  }

  it("should print wallet address", async function () {
    const wallet = await loadFixture(getFirstWallet);
    console.log(wallet.address);
  });
});
