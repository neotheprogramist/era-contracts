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

  it("should pass and emit", async () => {
    const balanceBefore = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);
    console.log("balanceBefore", balanceBefore.toString());

    await expect(
      extraAbiCaller.fallback({
        data: encodeExtraAbiCallerCalldata(
          messageValueSimulator.address,
          BigNumber.from(0),
          ["1000000000000000000", mockContract.address, "0"],
          "0x01ca"
        ),
      })
    )
      .to.emit(messageValueSimulator, "AbiParams")
      .withArgs(1000000000000000000n, false, "0x000000000000000000000000000000000000bEEF");
    // .to.emit(mockContract, "Called")
    // .withArgs(1000000000000000000n, "0x01ca");

    const balanceAfter = await hardhat.ethers.provider.getBalance(extraAbiCaller.address);

    console.log("diff", balanceBefore.sub(balanceAfter).toNumber() / 1e18);

    console.log("balanceAfter", balanceAfter.toString());
  });
});
