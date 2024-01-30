import { expect } from "chai";
import { ethers, network } from "hardhat";
import type { MsgValueSimulator } from "../typechain";
import { MsgValueSimulatorFactory } from "../typechain";
import { TEST_BOOTLOADER_FORMAL_ADDRESS, TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS } from "./shared/constants";
import { prepareEnvironment } from "./shared/mocks";
import { deployContractOnAddress, getWallets, loadZasmBytecode, setCode } from "./shared/utils";
import { Contract, type Wallet } from "zksync-web3";
import { EXTRA_ABI_CALLER_ADDRESS, encodeExtraAbiCallerCalldata } from "./shared/extraAbiCaller";
import { BigNumber } from "ethers";

describe("MsgValueSimulator tests", function () {
  let wallet: Wallet;
  const richWallet = getWallets()[0]; //signer
  let msgValueSimulator: MsgValueSimulator;
  let bootloaderAccount: ethers.Signer;
  let extraAbiCaller;

  before(async function () {
    await prepareEnvironment();
    await deployContractOnAddress(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, "MsgValueSimulator");
    wallet = getWallets()[0];
    bootloaderAccount = await ethers.getImpersonatedSigner(TEST_BOOTLOADER_FORMAL_ADDRESS);
    msgValueSimulator = MsgValueSimulatorFactory.connect(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, wallet);
    const extraAbiCallerBytecode = await loadZasmBytecode("ExtraAbiCaller", "test-contracts");
    await setCode(EXTRA_ABI_CALLER_ADDRESS, extraAbiCallerBytecode);
    extraAbiCaller = new Contract(EXTRA_ABI_CALLER_ADDRESS, [], wallet);
  });

  // after(async function () {
  //   await network.provider.request({
  //     method: "hardhat_stopImpersonatingAccount",
  //     params: [TEST_BOOTLOADER_FORMAL_ADDRESS],
  //   });
  // });

  describe("fallback", function () {
    it("should revert with message:This method require system call flag", async function () {
      const value = 10; // Przykładowa wartość
      const isSystemCall = true; // Przykładowa flaga

      // Zakoduj wartość i flagę isSystemCall w pierwszym parametrze
      const firstParam = ethers.BigNumber.from(value)
        .mul(2)
        .add(isSystemCall ? 1 : 0);

      // Ustaw adres to
      const to = msgValueSimulator.address; // Przykładowy adres
      // Połącz parametry
      const testToBytes = ethers.utils.defaultAbiCoder.encode(["uint256", "address", "bool"], [firstParam, to, true]);

      // const aaa = await encodeCalldata("MsgValueSimulator", "", [testToBytes]);
      // const bbb = await getMock("MsgValueSimulator");

      // await setResult("MsgValueSimulator", "", testToBytes, {
      //   failure: false,
      //   returnData: ethers.constants.HashZero,
      // });

      // console.log("dasdasdasd", [aaa]);

      // await expect(callFallback(msgValueSimulator, testToBytes)).to.be.revertedWith("MsgValueSimulator calls itself");
      await expect(msgValueSimulator.fallback({ data: testToBytes })).to.be.revertedWith(
        "This method require system call flag"
      );
    });
    it("should revert with message:MsgValueSimulator calls itself", async function () {
      const value = 10; // Przykładowa wartość
      const isSystemCall = true; // Przykładowa flaga

      const firstParam = ethers.BigNumber.from(value)
        .mul(2)
        .add(isSystemCall ? 1 : 0);

      const to = msgValueSimulator.address; // Przykładowy adres

      const testToBytes = ethers.utils.defaultAbiCoder.encode(["uint256", "address", "bool"], [firstParam, to, true]);

      const allBitsSet = BigNumber.from(1).shl(128).sub(1);
      const extraData = allBitsSet.toHexString();
      console.log(extraData);

      const txResponse = await msgValueSimulator.fallback({
        data: encodeExtraAbiCallerCalldata(bootloaderAccount.address, 0, [extraData], extraData),
      });
      console.log(txResponse);

      // await msgValueSimulator.fallback({
      //   data,
      // });
    });

    // it("should set correct abiParams", async function () {});
    // it("should fail transaction", async function () {});
    // it("should complete transaction", async function () {});
  });
});
