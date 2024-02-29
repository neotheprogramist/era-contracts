import { L2EthToken, L2EthTokenFactory, MockContract, MsgValueSimulator, MsgValueSimulatorFactory } from "../typechain";
import { deployContract, deployContractOnAddress, getWallets, loadZasmBytecode, setCode } from "./shared/utils";
import { TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS } from "./shared/constants";
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
  const deployerWallet = getWallets()[0];

  before(async () => {
    await prepareEnvironment();
    await deployContractOnAddress(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, "MsgValueSimulator");

    mockContract = (await deployContract("MockContract")) as MockContract;

    messageValueSimulator = MsgValueSimulatorFactory.connect(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, deployerWallet);
    const extraAbiCallerBytecode = await loadZasmBytecode("ExtraAbiCaller", "test-contracts");
    await setCode(EXTRA_ABI_CALLER_ADDRESS, extraAbiCallerBytecode);
    extraAbiCaller = new Contract(EXTRA_ABI_CALLER_ADDRESS, [], deployerWallet);
  });

  it("send 0 ETH", async () => {
    const value = 0;
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          [value.toString(), mockContract.address, "0"],
          "0x01ca"
        ),
      })
    )
      .to.emit(mockContract, "Called")
      .withArgs(value, "0x01ca");

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  });

  it("send 1 wei", async () => {
    const value = 1;
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          [value.toString(), mockContract.address, "0"],
          "0x01ca"
        ),
      })
    )
      // .to.emit(messageValueSimulator, "AbiParams")
      // .withArgs(1000000000000000000n, false, 0xbeefn);
      .to.emit(mockContract, "Called")
      .withArgs(value, "0x01ca");

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  });

  it("send 1 ETH", async () => {
    const value = 1000000000000000000n;
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          [value.toString(), mockContract.address, "0"],
          "0x01ca"
        ),
      })
    )
      .to.emit(mockContract, "Called")
      .withArgs(value, "0x01ca");

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  });

  it("send 2^127 wei", async () => {
    const value = BigNumber.from(2).pow(127);
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          [value.toString(), mockContract.address, "0"],
          "0x01ca"
        ),
      })
    )
      .to.emit(mockContract, "Called")
      .withArgs(value, "0x01ca");

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    // expect(balanceBefore.sub(value)).to.equal(balanceAfter);
  });

  it("send with reentry", async () => {
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          ["0x1", messageValueSimulator.address, "0"],
          "0x01ca"
        ),
      })
    ).to.be.reverted;

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    expect(balanceBefore).to.equal(balanceAfter);
  });

  it("send more than balance", async () => {
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    const value = balanceBefore.add(1);

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          [value.toString(), mockContract.address, "0"],
          "0x01ca"
        ),
      })
    );
    // .to.be.reverted;

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    expect(balanceBefore).to.equal(balanceAfter);
  });
});
