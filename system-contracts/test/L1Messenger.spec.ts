import { ethers, network } from "hardhat";
import { L1MessengerFactory } from "../typechain";
import type { L1Messenger } from "../typechain";
import { prepareEnvironment, setResult } from "./shared/mocks";
import { deployContractOnAddress, getCode, getWallets } from "./shared/utils";
import { utils } from "zksync-web3";
import type { Wallet } from "zksync-web3";
import {
  TEST_KNOWN_CODE_STORAGE_CONTRACT_ADDRESS,
  TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS,
  TEST_BOOTLOADER_FORMAL_ADDRESS,
} from "./shared/constants";
import { expect } from "chai";

describe("L1Messenger tests", () => {
  let l1Messenger: L1Messenger;
  let wallet: Wallet;
  let l1MessengerAccount: ethers.Signer;
  let knownCodeStorageAccount: ethers.Signer;
  let bootloaderAccount: ethers.Signer;
  let numberOfLogs: number = 0;
  let numberOfMessages: number = 0;
  let numberOfBytecodes: number = 0;

  before(async () => {
    await prepareEnvironment();
    wallet = getWallets()[0];
    await deployContractOnAddress(TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS, "L1Messenger");
    l1Messenger = L1MessengerFactory.connect(TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS, wallet);
    l1MessengerAccount = await ethers.getImpersonatedSigner(TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS);
    knownCodeStorageAccount = await ethers.getImpersonatedSigner(TEST_KNOWN_CODE_STORAGE_CONTRACT_ADDRESS);
    bootloaderAccount = await ethers.getImpersonatedSigner(TEST_BOOTLOADER_FORMAL_ADDRESS);
  });

  after(async () => {
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS],
    });
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [TEST_KNOWN_CODE_STORAGE_CONTRACT_ADDRESS],
    });
    await network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [TEST_BOOTLOADER_FORMAL_ADDRESS],
    });
  });

  // TODO: IN PROGRESS - for now run these tests separately
  describe("publishPubdataAndClearState", async () => {
    it("should revert when not called by bootloader", async () => {
      const totalL2ToL1PubdataAndStateDiffs = ethers.utils.hexZeroPad("0x01", 32);
      await expect(
        l1Messenger.connect(getWallets()[2]).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs)
      ).to.be.rejectedWith("Callable only by the bootloader");
    });

    it("publishPubdataAndClearState passes correctly", async () => {
      // sendL2ToL1Log()
      const isService = true;
      const key = Buffer.alloc(32, 1);
      const value = Buffer.alloc(32, 2);

      const txNumberInBlock = 1;
      const callResult = {
        failure: false,
        returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock]),
      };
      await setResult("SystemContext", "txNumberInBlock", [], callResult);
      await (await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value)).wait();

      const firstLog = ethers.utils.concat([
        ethers.utils.hexlify([0]),
        ethers.utils.hexlify([isService ? 1 : 0]),
        ethers.utils.hexZeroPad(ethers.utils.hexlify(txNumberInBlock), 2),
        ethers.utils.hexZeroPad(l1MessengerAccount.address, 20),
        key,
        value,
      ]);
      numberOfLogs++;
      console.log("firstLog:\n ", ethers.utils.hexlify(firstLog));
      console.log("numberOfLogs: ", ethers.utils.hexlify(numberOfLogs));

      // sendToL1()
      const message = Buffer.alloc(32, 3);
      const txNumberInBlock2 = 1;
      const callResult2 = {
        failure: false,
        returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock2]),
      };
      await setResult("SystemContext", "txNumberInBlock", [], callResult2);
      await (await l1Messenger.connect(l1MessengerAccount).sendToL1(message)).wait();

      const senderAddress = ethers.utils
        .hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32)
        .toLowerCase();
      const messageHash = ethers.utils.keccak256(message);

      const secondLog = ethers.utils.concat([
        ethers.utils.hexlify([0]),
        ethers.utils.hexlify([isService ? 1 : 0]),
        ethers.utils.hexZeroPad(ethers.utils.hexlify(txNumberInBlock), 2),
        ethers.utils.hexZeroPad(l1Messenger.address, 20),
        senderAddress,
        messageHash,
      ]);
      const currentMessageLength = 32;
      numberOfMessages++;
      numberOfLogs++;
      console.log("secondLog:\n ", ethers.utils.hexlify(secondLog));
      console.log("numberOfMessages: ", ethers.utils.hexlify(numberOfMessages));
      console.log("lengthOfMessage: ", ethers.utils.hexlify(currentMessageLength));
      console.log("numberOfLogs: ", ethers.utils.hexlify(numberOfLogs));

      // requestBytecodeL1Publication()
      const bytecode = await getCode(l1Messenger.address);
      const bytecodeHash = await ethers.utils.hexlify(utils.hashBytecode(bytecode));
      await (
        await l1Messenger
          .connect(knownCodeStorageAccount)
          .requestBytecodeL1Publication(bytecodeHash, { gasLimit: 130000000 })
      ).wait();
      numberOfBytecodes++;
      const lengthOfBytecode = bytecode.length;
      // console.log("bytecodeLength: ", ethers.utils.hexlify(lengthOfBytecode));

      // Concatenate all the bytes together
      const numberOfLogsBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfLogs), 4);
      const numberOfMessagesBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfMessages), 4);
      const currentMessageLengthBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(currentMessageLength), 4);
      const numberOfBytecodesBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfBytecodes), 4);
      const lengthOfBytecodeBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(lengthOfBytecode), 4);
      const totalL2ToL1PubdataAndStateDiffs = ethers.utils.concat([
        numberOfLogsBytes,
        firstLog,
        secondLog,
        numberOfMessagesBytes,
        currentMessageLengthBytes,
        message,
        numberOfBytecodesBytes,
        lengthOfBytecodeBytes,
        bytecode,
      ]);
      console.log("length of bytecode", ethers.utils.hexlify(lengthOfBytecode));

      // TODO: Get data for compressedStateDiffSize, enumerationIndexSize, compressedStateDiffs, numberOfStateDiffs, stateDiffs

      // // Sample data for _numberOfStateDiffs, _enumerationIndexSize, _stateDiffs, _compressedStateDiffs
      // const _numberOfStateDiffs = 10;
      // const _enumerationIndexSize = 1;
      // const _stateDiffs = ethers.utils.formatBytes32String("stateDiffs");
      // const _compressedStateDiffs = ethers.utils.formatBytes32String("compressedStateDiffs");

      // // Calculate the keccak256 hash of _stateDiffs
      // const stateDiffHash = ethers.utils.keccak256(_stateDiffs);

      // possibly needed mock for compressor tmp
      // const verifyCompressedStateDiffsResult = {
      //   failure: false,
      //   returnData: ethers.utils.defaultAbiCoder.encode(
      //     ["bytes32"],
      //     [stateDiffHash]
      //   ),
      // };

      // await setResult("Compressor", "verifyCompressedStateDiffs",
      //   [
      //     _numberOfStateDiffs,
      //     _enumerationIndexSize,
      //     _stateDiffs,
      //     _compressedStateDiffs
      //   ],
      //   verifyCompressedStateDiffsResult
      // );

      // publishPubdataAndClearState()
      await (
        await l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs, { gasLimit: 1000000000 })
      ).wait();

      numberOfLogs = 0;
      numberOfMessages = 0;
      numberOfBytecodes = 0;
    });
  });
});
