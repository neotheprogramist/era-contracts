import { L2EthToken, L2EthTokenFactory, MockContract, MsgValueSimulator, MsgValueSimulatorFactory } from "../typechain";
import { deployContract, deployContractOnAddress, getWallets, loadZasmBytecode, setCode } from "./shared/utils";
import {
  TEST_BOOTLOADER_FORMAL_ADDRESS,
  TEST_ETH_TOKEN_SYSTEM_CONTRACT_ADDRESS,
  TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS,
} from "./shared/constants";
import { prepareEnvironment } from "./shared/mocks";
import { expect } from "chai";
import { EXTRA_ABI_CALLER_ADDRESS, encodeExtraAbiCallerCalldata } from "./shared/extraAbiCaller";
import { BigNumber } from "ethers";
import { Contract } from "zksync-web3";
import * as hardhat from "hardhat";

describe("MsgValueSimulator tests", () => {
  let messageValueSimulator: MsgValueSimulator;
  let extraAbiCaller: Contract;
  let mockContract: MockContract;
  let l2EthToken: L2EthToken;
  const wallet = getWallets()[0];

  before(async () => {
    await prepareEnvironment();
    await deployContractOnAddress(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, "MsgValueSimulator");

    mockContract = (await deployContract("MockContract")) as MockContract;

    messageValueSimulator = MsgValueSimulatorFactory.connect(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, wallet);
    const extraAbiCallerBytecode = await loadZasmBytecode("ExtraAbiCaller", "test-contracts");
    await setCode(EXTRA_ABI_CALLER_ADDRESS, extraAbiCallerBytecode);
    extraAbiCaller = new Contract(EXTRA_ABI_CALLER_ADDRESS, [], wallet);

    await deployContractOnAddress(TEST_ETH_TOKEN_SYSTEM_CONTRACT_ADDRESS, "L2EthToken");
    l2EthToken = L2EthTokenFactory.connect(TEST_ETH_TOKEN_SYSTEM_CONTRACT_ADDRESS, wallet);

    // Mint some tokens to the wallet
    const bootloaderAccount = await hardhat.ethers.getImpersonatedSigner(TEST_BOOTLOADER_FORMAL_ADDRESS);
    await (
      await l2EthToken.connect(bootloaderAccount).mint(wallet.address, hardhat.ethers.utils.parseEther("10.0"))
    ).wait();
    await (
      await l2EthToken
        .connect(bootloaderAccount)
        .mint("0x000000000000000000000000000000000000beef", hardhat.ethers.utils.parseEther("10.0"))
    ).wait();

    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [TEST_BOOTLOADER_FORMAL_ADDRESS],
    });
  });

  it("send 1 ETH", async () => {
    const value = 2137n;
    const balanceBefore = await l2EthToken.balanceOf(wallet.address);
    expect(l2EthToken.address).to.equal("0x000000000000000000000000000000000000900a");
    expect(wallet.address).to.equal("0x36615Cf349d7F6344891B1e7CA7C72883F5dc049");

    await expect(
      extraAbiCaller.connect(wallet).fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          [value.toString(), mockContract.address, "0"],
          "0x01ca"
        ),
      })
    )
      .to.emit(messageValueSimulator, "S")
      .withArgs(wallet.address);

    //   .to.emit(mockContract, "Called")
    //   .withArgs("2", "0x01ca");

    const balanceAfter = await l2EthToken.balanceOf(wallet.address);
    console.log("balanceBefore", balanceBefore.toString());
    console.log("balanceAfter", balanceAfter.toString());
    // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  });

  // it("send 0 ETH", async () => {
  //   const value = 0;
  //   const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

  //   await expect(
  //     extraAbiCaller.fallback({
  //       data: encodeExtraAbiCallerCalldata(
  //         messageValueSimulator.address,
  //         BigNumber.from(0),
  //         [value.toString(), mockContract.address, "0"],
  //         "0x01ca"
  //       ),
  //     })
  //   )
  //     .to.emit(mockContract, "Called")
  //     .withArgs(value, "0x01ca");

  //   const balanceAfter = await l2EthToken.balanceOf(wallet.address);
  //   // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  // });

  // it("send 1 wei", async () => {
  //   const value = 1;
  //   const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

  //   await expect(
  //     extraAbiCaller.fallback({
  //       data: encodeExtraAbiCallerCalldata(
  //         messageValueSimulator.address,
  //         BigNumber.from(0),
  //         [value.toString(), mockContract.address, "0"],
  //         "0x01ca"
  //       ),
  //     })
  //   )
  //     // .to.emit(messageValueSimulator, "AbiParams")
  //     // .withArgs(1000000000000000000n, false, 0xbeefn);
  //     .to.emit(mockContract, "Called")
  //     .withArgs(value, "0x01ca");

  //   const balanceAfter = await l2EthToken.balanceOf(wallet.address);
  //   // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  // });

  // it("send 2^127 wei", async () => {
  //   const value = BigNumber.from(2).pow(127);
  //   const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

  //   await expect(
  //     extraAbiCaller.fallback({
  //       data: encodeExtraAbiCallerCalldata(
  //         messageValueSimulator.address,
  //         BigNumber.from(0),
  //         [value.toString(), mockContract.address, "0"],
  //         "0x01ca"
  //       ),
  //     })
  //   )
  //     .to.emit(mockContract, "Called")
  //     .withArgs(value, "0x01ca");

  //   const balanceAfter = await l2EthToken.balanceOf(wallet.address);
  //   // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  // });

  // it("send with reentry", async () => {
  //   const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

  //   await expect(
  //     extraAbiCaller.fallback({
  //       data: encodeExtraAbiCallerCalldata(
  //         messageValueSimulator.address,
  //         BigNumber.from(0),
  //         ["0x1", messageValueSimulator.address, "0"],
  //         "0x01ca"
  //       ),
  //     })
  //   ).to.be.reverted;

  //   const balanceAfter = await l2EthToken.balanceOf(wallet.address);
  //   expect(balanceBefore).to.equal(balanceAfter);
  // });

  // it("send more than balance", async () => {
  //   const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
  //   const value = balanceBefore.add(1);

  //   await expect(
  //     extraAbiCaller.fallback({
  //       data: encodeExtraAbiCallerCalldata(
  //         messageValueSimulator.address,
  //         BigNumber.from(0),
  //         [value.toString(), mockContract.address, "0"],
  //         "0x01ca"
  //       ),
  //     })
  //   );
  //   // .to.be.reverted;

  //   const balanceAfter = await l2EthToken.balanceOf(wallet.address);
  //   expect(balanceBefore).to.equal(balanceAfter);
  // });
});
