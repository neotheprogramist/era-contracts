import { MsgValueSimulator, MsgValueSimulatorFactory } from "../typechain";
import { deployContract, deployContractOnAddress, getWallets } from "./shared/utils";
import { TEST_ETH_TOKEN_SYSTEM_CONTRACT_ADDRESS, TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS } from "./shared/constants";
import { prepareEnvironment } from "./shared/mocks";
import { expect } from "chai";
import { EXTRA_ABI_CALLER_ADDRESS, encodeExtraAbiCallerCalldata } from "./shared/extraAbiCaller";
import { BigNumber } from "ethers";
import { Contract } from "zksync-web3";

describe("MsgValueSimulator tests", () => {
  let messageValueSimulator: MsgValueSimulator;
  let extraAbiCaller: Contract;
  let systemCaller: MsgValueSimulator;

  before(async () => {
    await prepareEnvironment();
    const deployerWallet = getWallets()[0];
    await deployContractOnAddress(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, "MsgValueSimulator");

    messageValueSimulator = MsgValueSimulatorFactory.connect(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, deployerWallet);
    const messageValueSimulatorSystemCallContract = await deployContract("SystemCaller", [
      messageValueSimulator.address,
    ]);
    systemCaller = MsgValueSimulatorFactory.connect(messageValueSimulatorSystemCallContract.address, deployerWallet);
    extraAbiCaller = new Contract(EXTRA_ABI_CALLER_ADDRESS, [], deployerWallet);
  });

  describe("fallback", () => {
    it("should pass and emit", async () => {
      await expect(
        systemCaller.fallback({
          data: encodeExtraAbiCallerCalldata(
            messageValueSimulator.address,
            BigNumber.from(1),
            [
              "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
              "0x2222222222222222222222222222222222222222222222222222222222222222",
              "0x3333333333333333333333333333333333333333333333333333333333333333",
              "0x4444444444444444444444444444444444444444444444444444444444444444",
              "0x5555555555555555555555555555555555555555555555555555555555555555",
              "0x6666666666666666666666666666666666666666666666666666666666666666",
              "0x7777777777777777777777777777777777777777777777777777777777777777",
              "0x8888888888888888888888888888888888888888888888888888888888888888",
              "0x9999999999999999999999999999999999999999999999999999999999999999",
              "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ],
            "0x01"
          ),
        })
      )
        .to.emit(messageValueSimulator, "AbiParams")
        .withArgs(1, true, "0x0000000000000000000000000000000000000002");
    });
  });
});
