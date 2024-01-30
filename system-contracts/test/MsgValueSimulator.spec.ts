import { expect } from "chai";
import { ethers, network } from "hardhat";
import type { MsgValueSimulator } from "../typechain";
import { MsgValueSimulatorFactory } from "../typechain";
import { TEST_BOOTLOADER_FORMAL_ADDRESS, TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS } from "./shared/constants";
import { prepareEnvironment } from "./shared/mocks";
import { deployContractOnAddress, getWallets } from "./shared/utils";
import {   type Wallet } from "zksync-web3";
import { BigNumber } from "ethers";

describe("MsgValueSimulator tests", function () {
  let wallet: Wallet;
  let msgValueSimulator: MsgValueSimulator;
  let bootloaderAccount: ethers.Signer;

  before(async function () {
    await prepareEnvironment();
    await deployContractOnAddress(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, "MsgValueSimulator");
    wallet = getWallets()[0];
    bootloaderAccount = await ethers.getImpersonatedSigner(TEST_BOOTLOADER_FORMAL_ADDRESS);
    msgValueSimulator = MsgValueSimulatorFactory.connect(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, wallet);
  });

  after(async function () {
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [TEST_BOOTLOADER_FORMAL_ADDRESS],
    });
  });

  describe("fallback", function () {
    it("should revert This method require system call flag", async function () {
      const firstParam = BigNumber.from(1).shl(128).sub(1);
      console.log(firstParam._hex);
      
      const data = ethers.utils.defaultAbiCoder.encode(["uint128", "address"], [firstParam, msgValueSimulator.address]);
      await expect(msgValueSimulator.fallback({ data })).to.be.rejectedWith(
        "This method require system call flag"
      );
    });

    it("should revert MsgValueSimulator calls itself", async function () {
      const firstParam = BigNumber.from(1).shl(128).sub(1);
      const data = ethers.utils.defaultAbiCoder.encode(["uint256", "address"], [firstParam, msgValueSimulator.address]);
      await msgValueSimulator.connect(bootloaderAccount).fallback({
        data,
      });
    });
  });
});
