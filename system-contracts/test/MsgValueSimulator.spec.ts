import { MsgValueSimulator, MsgValueSimulatorFactory } from "../typechain";
import { deployContract, deployContractOnAddress, getWallets, loadZasmBytecode, setCode } from "./shared/utils";
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
    const extraAbiCallerBytecode = await loadZasmBytecode("ExtraAbiCaller", "test-contracts");
    await setCode(EXTRA_ABI_CALLER_ADDRESS, extraAbiCallerBytecode);
    extraAbiCaller = new Contract(EXTRA_ABI_CALLER_ADDRESS, [], deployerWallet);
  });

  describe("fallback", () => {
    it("should pass and emit", async () => {
      await expect(
        extraAbiCaller.fallback({
          data: encodeExtraAbiCallerCalldata(messageValueSimulator.address, BigNumber.from(0), ["5"], "0x01"),
        })
      )
        .to.emit(messageValueSimulator, "AbiParams")
        .withArgs(5, true, "0x0000000000000000000000000000000000000002");
    });
  });
});
