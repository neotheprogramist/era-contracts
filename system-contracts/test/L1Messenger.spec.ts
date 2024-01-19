import { ethers, network } from "hardhat";
import type { L1Messenger } from "../typechain";
import { L1MessengerFactory } from "../typechain";
import { prepareEnvironment, setResult } from "./shared/mocks";
import type { StateDiff } from "./shared/utils";
import { compressStateDiffs, deployContractOnAddress, encodeStateDiffs, getCode, getWallets } from "./shared/utils";
import { utils } from "zksync-web3";
import type { Wallet } from "zksync-web3";
import {
  TEST_KNOWN_CODE_STORAGE_CONTRACT_ADDRESS,
  TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS,
  TEST_BOOTLOADER_FORMAL_ADDRESS,
  TWO_IN_256,
} from "./shared/constants";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { randomBytes } from "crypto";

describe("L1Messenger tests", () => {
  let l1Messenger: L1Messenger;
  let wallet: Wallet;
  let l1MessengerAccount: ethers.Signer;
  let knownCodeStorageAccount: ethers.Signer;
  let bootloaderAccount: ethers.Signer;
  let stateDiffsSetupData: StateDiffSetupData;
  let logData: LogData;
  let bytecodeData: BytecodeData;
  let emulator: L1MessengerPubdataEmulator;

  before(async () => {
    await prepareEnvironment();
    wallet = getWallets()[0];
    await deployContractOnAddress(TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS, "L1Messenger");
    l1Messenger = L1MessengerFactory.connect(TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS, wallet);
    l1MessengerAccount = await ethers.getImpersonatedSigner(TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS);
    knownCodeStorageAccount = await ethers.getImpersonatedSigner(TEST_KNOWN_CODE_STORAGE_CONTRACT_ADDRESS);
    bootloaderAccount = await ethers.getImpersonatedSigner(TEST_BOOTLOADER_FORMAL_ADDRESS);
    // setup
    stateDiffsSetupData = await setupStateDiffs();
    logData = setupLogData(l1MessengerAccount, l1Messenger);
    bytecodeData = await setupBytecodeData(l1Messenger.address);
    await setResult("SystemContext", "txNumberInBlock", [], {
      failure: false,
      returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [1]),
    });
    emulator = new L1MessengerPubdataEmulator();
  });

  
  after(async () => {
    // cleaning the state of l1Messenger
    await l1Messenger
      .connect(bootloaderAccount)
      .publishPubdataAndClearState(emulator.buildTotalL2ToL1PubdataAndStateDiffs());
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

  describe("publishPubdataAndClearState", async () => {
    it("publishPubdataAndClearState passes correctly", async () => {
      await (
        await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(logData.isService, logData.key, logData.value)
      ).wait();
      emulator.addLog(logData.logs[0]);
      await (await l1Messenger.connect(l1MessengerAccount).sendToL1(logData.message)).wait();
      emulator.addLog(logData.logs[1]);
      emulator.addMessage({ lengthBytes: logData.currentMessageLengthBytes, content: logData.message });
      await (
        await l1Messenger
          .connect(knownCodeStorageAccount)
          .requestBytecodeL1Publication(await ethers.utils.hexlify(utils.hashBytecode(bytecodeData.content)), {
            gasLimit: 130000000,
          })
      ).wait();
      emulator.addBytecode(bytecodeData);
      emulator.setStateDiffsSetupData(stateDiffsSetupData);
      await (
        await l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(emulator.buildTotalL2ToL1PubdataAndStateDiffs(), { gasLimit: 10000000 })
      ).wait();
    });

    it("should revert Too many L2->L1 logs", async () => {
      // set numberOfLogsBytes to 0x900 to trigger the revert (max value is 0x800)
      emulator.numberOfLogs = 0x900;
      await expect(
        l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(emulator.buildTotalL2ToL1PubdataAndStateDiffs())
      ).to.be.rejectedWith("Too many L2->L1 logs");
    });

    it("should revert logshashes mismatch", async () => {
      emulator.numberOfLogs = 2;
      await (
        await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(logData.isService, logData.key, logData.value)
      ).wait();
      await (await l1Messenger.connect(l1MessengerAccount).sendToL1(logData.message)).wait();
      // set secondlog hash to random data to trigger the revert
      const secondLogModified = ethers.utils.concat([
        ethers.utils.hexlify([0]),
        ethers.utils.hexlify(1),
        ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 2),
        ethers.utils.hexZeroPad(l1Messenger.address, 20),
        ethers.utils.hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32).toLowerCase(),
        ethers.utils.hexlify(randomBytes(32)),
      ]);
      emulator.logs[1] = secondLogModified;
      await expect(
        l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(emulator.buildTotalL2ToL1PubdataAndStateDiffs())
      ).to.be.rejectedWith("reconstructedChainedLogsHash is not equal to chainedLogsHash");
    });

    it("should revert chainedMessageHash mismatch", async () => {
      emulator.logs[1] = logData.logs[1];
      // Buffer.alloc(32, 6), to trigger the revert
      const wrongMessage = { lengthBytes: logData.currentMessageLengthBytes, content: Buffer.alloc(32, 6) };
      emulator.messages[0] = wrongMessage;
      await expect(
        l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(emulator.buildTotalL2ToL1PubdataAndStateDiffs())
      ).to.be.rejectedWith("reconstructedChainedMessagesHash is not equal to chainedMessagesHash");
    });

    it("should revert state diff compression version mismatch", async () => {
      await (
        await l1Messenger
          .connect(knownCodeStorageAccount)
          .requestBytecodeL1Publication(await ethers.utils.hexlify(utils.hashBytecode(bytecodeData.content)), {
            gasLimit: 130000000,
          })
      ).wait();
      emulator.messages[0] = { lengthBytes: logData.currentMessageLengthBytes, content: logData.message };
      // modify version to trigger the revert
      emulator.version = ethers.utils.hexZeroPad(ethers.utils.hexlify(66), 1);
      await expect(
        l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(emulator.buildTotalL2ToL1PubdataAndStateDiffs())
      ).to.be.rejectedWith("state diff compression version mismatch");
    });

    it("should revert extra data", async () => {
      emulator.version = ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 1);
      // add extra data to trigger the revert
      await expect(
        l1Messenger
          .connect(bootloaderAccount)
          .publishPubdataAndClearState(
            ethers.utils.concat([emulator.buildTotalL2ToL1PubdataAndStateDiffs(), Buffer.alloc(1, 64)])
          )
      ).to.be.rejectedWith("Extra data in the totalL2ToL1Pubdata array");
    });
  });

  describe("sendL2ToL1Log", async () => {
    it("should revert when not called by the system contract", async () => {
      await expect(l1Messenger.sendL2ToL1Log(true, logData.key, logData.value)).to.be.rejectedWith(
        "This method require the caller to be system contract"
      );
    });

    it("should emit L2ToL1LogSent event when called by the system contract", async () => {
      emulator.addLog(logData.logs[0]);
      await expect(
        l1Messenger
          .connect(l1MessengerAccount)
          .sendL2ToL1Log(true, ethers.utils.hexlify(logData.key), ethers.utils.hexlify(logData.value))
      )
        .to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([
          0,
          true,
          1,
          l1MessengerAccount.address,
          ethers.utils.hexlify(logData.key),
          ethers.utils.hexlify(logData.value),
        ]);
    });

    it("should emit L2ToL1LogSent event when called by the system contract with isService false", async () => {
      const fourthLog = ethers.utils.concat([
        ethers.utils.hexlify([0]),
        ethers.utils.hexlify([0]),
        ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 2),
        ethers.utils.hexZeroPad(l1MessengerAccount.address, 20),
        logData.key,
        logData.value,
      ]);
      emulator.addLog(fourthLog);
      await expect(
        l1Messenger
          .connect(l1MessengerAccount)
          .sendL2ToL1Log(false, ethers.utils.hexlify(logData.key), ethers.utils.hexlify(logData.value))
      )
        .to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([
          0,
          false,
          1,
          l1MessengerAccount.address,
          ethers.utils.hexlify(logData.key),
          ethers.utils.hexlify(logData.value),
        ]);
    });
  });

  describe("sendToL1", async () => {
    it("should emit L1MessageSent & L2ToL1LogSent events", async () => {
      emulator.addLog(logData.logs[1]);
      emulator.addMessage({ lengthBytes: logData.currentMessageLengthBytes, content: logData.message });
      const expectedKey = ethers.utils
        .hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32)
        .toLowerCase();
      await expect(l1Messenger.connect(l1MessengerAccount).sendToL1(logData.message))
        .to.emit(l1Messenger, "L1MessageSent")
        .withArgs(l1MessengerAccount.address, ethers.utils.keccak256(logData.message), logData.message)
        .and.to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([0, true, 1, l1Messenger.address, expectedKey, ethers.utils.keccak256(logData.message)]);
    });
  });

  describe("requestBytecodeL1Publication", async () => {
    emulator.addBytecode(bytecodeData);
    it("should revert when not called by known code storage contract", async () => {
      const byteCodeHash = ethers.utils.hexlify(randomBytes(32));
      await expect(l1Messenger.requestBytecodeL1Publication(byteCodeHash)).to.be.rejectedWith("Inappropriate caller");
    });

    it("shoud emit event, called by known code system contract", async () => {
      await expect(
        l1Messenger
          .connect(knownCodeStorageAccount)
          .requestBytecodeL1Publication(await ethers.utils.hexlify(utils.hashBytecode(bytecodeData.content)), {
            gasLimit: 130000000,
          })
      )
        .to.emit(l1Messenger, "BytecodeL1PublicationRequested")
        .withArgs(await ethers.utils.hexlify(utils.hashBytecode(bytecodeData.content)));
    });
  });
});

// Interface represents the structure of the data that that is used in totalL2ToL1PubdataAndStateDiffs
interface StateDiffSetupData {
  encodedStateDiffs: string;
  compressedStateDiffs: string;
  enumerationIndexSizeBytes: string;
  numberOfStateDiffsBytes: string;
  compressedStateDiffsSizeBytes: string;
}

async function setupStateDiffs(): Promise<StateDiffSetupData> {
  const stateDiffs: StateDiff[] = [
    {
      key: "0x1234567890123456789012345678901234567890123456789012345678901230",
      index: 0,
      initValue: BigNumber.from("0x1234567890123456789012345678901234567890123456789012345678901231"),
      finalValue: BigNumber.from("0x1234567890123456789012345678901234567890123456789012345678901230"),
    },
    {
      key: "0x1234567890123456789012345678901234567890123456789012345678901232",
      index: 1,
      initValue: TWO_IN_256.sub(1),
      finalValue: BigNumber.from(1),
    },
    {
      key: "0x1234567890123456789012345678901234567890123456789012345678901234",
      index: 0,
      initValue: TWO_IN_256.div(2),
      finalValue: BigNumber.from(1),
    },
    {
      key: "0x1234567890123456789012345678901234567890123456789012345678901236",
      index: 2323,
      initValue: BigNumber.from("0x1234567890123456789012345678901234567890123456789012345678901237"),
      finalValue: BigNumber.from("0x0239329298382323782378478237842378478237847237237872373272373272"),
    },
    {
      key: "0x1234567890123456789012345678901234567890123456789012345678901238",
      index: 2,
      initValue: BigNumber.from(0),
      finalValue: BigNumber.from(1),
    },
  ];
  const encodedStateDiffs = encodeStateDiffs(stateDiffs);
  const compressedStateDiffs = compressStateDiffs(4, stateDiffs);
  const enumerationIndexSizeBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(4), 1);
  await setResult(
    "Compressor",
    "verifyCompressedStateDiffs",
    [stateDiffs.length, 4, encodedStateDiffs, compressedStateDiffs],
    {
      failure: false,
      returnData: ethers.utils.defaultAbiCoder.encode(["bytes32"], [ethers.utils.keccak256(encodedStateDiffs)]),
    }
  );
  const numberOfStateDiffsBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(stateDiffs.length), 4);
  const compressedStateDiffsSizeBytes = ethers.utils.hexZeroPad(
    ethers.utils.hexlify(ethers.utils.arrayify(compressedStateDiffs).length),
    3
  );
  return {
    encodedStateDiffs,
    compressedStateDiffs,
    enumerationIndexSizeBytes,
    numberOfStateDiffsBytes,
    compressedStateDiffsSizeBytes,
  };
}

// The LogData interface represents the structure of the data that will be logged 
interface LogData {
  isService: boolean;
  key: Buffer;
  value: Buffer;
  message: Buffer;
  currentMessageLengthBytes: string;
  logs: string[];
}

function setupLogData(l1MessengerAccount: ethers.Signer, l1Messenger: L1Messenger): LogData {
  const key = Buffer.alloc(32, 1);
  const value = Buffer.alloc(32, 2);
  const message = Buffer.alloc(32, 3);
  const currentMessageLengthBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(32), 4);
  const logs = [ethers.utils.concat([
    ethers.utils.hexlify([0]),
    ethers.utils.hexlify(1),
    ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 2),
    ethers.utils.hexZeroPad(l1MessengerAccount.address, 20),
    key,
    value,
  ]), ethers.utils.concat([
    ethers.utils.hexlify([0]),
    ethers.utils.hexlify(1),
    ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 2),
    ethers.utils.hexZeroPad(l1Messenger.address, 20),
    ethers.utils.hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32).toLowerCase(),
    ethers.utils.keccak256(message),
  ]) 
]
  return {
    isService: true,
    key,
    value,
    message,
    currentMessageLengthBytes,
    logs, 
  };
}

//Represents the structure of the bytecode/message data that is part of the pubdata.
interface BytecodeData {
  content: string;
  lengthBytes: string;
}

async function setupBytecodeData(l1MessengerAddress: string): Promise<BytecodeData> {
  const content = await getCode(l1MessengerAddress);
  const lengthBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(ethers.utils.arrayify(content).length), 4);
  return {
    content,
    lengthBytes,
  };
}

// Used for emulating the pubdata published by the L1Messenger.
class L1MessengerPubdataEmulator {
  numberOfLogs: number;
  logs: string[];
  numberOfMessages: number;
  messages: BytecodeData[];
  numberOfBytecodes: number;
  bytecodes: BytecodeData[];
  stateDiffsSetupData: StateDiffSetupData;
  version: string;

  constructor() {
    this.numberOfLogs = 0;
    this.logs = [];
    this.numberOfMessages = 0;
    this.messages = [];
    this.numberOfBytecodes = 0;
    this.bytecodes = [];
    this.stateDiffsSetupData = {
      compressedStateDiffsSizeBytes: "",
      enumerationIndexSizeBytes: "",
      compressedStateDiffs: "",
      numberOfStateDiffsBytes: "",
      encodedStateDiffs: "",
    };
    this.version = ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 1);
  }

  addLog(log: string) {
    this.logs.push(log);
    this.numberOfLogs++;
  }

  addMessage(message: BytecodeData) {
    this.messages.push(message);
    this.numberOfMessages++;
  }

  addBytecode(bytecode: BytecodeData) {
    this.bytecodes.push(bytecode);
    this.numberOfBytecodes++;
  }

  setStateDiffsSetupData(data: StateDiffSetupData) {
    this.stateDiffsSetupData = data;
  }

  buildTotalL2ToL1PubdataAndStateDiffs(): string {
    const messagePairs = [];
    for (let i = 0; i < this.numberOfMessages; i++) {
      messagePairs.push(this.messages[i].lengthBytes, this.messages[i].content);
    }
  
    const bytecodePairs = [];
    for (let i = 0; i < this.numberOfBytecodes; i++) {
      bytecodePairs.push(this.bytecodes[i].lengthBytes, this.bytecodes[i].content);
    }
  
    return ethers.utils.concat([
      ethers.utils.hexZeroPad(ethers.utils.hexlify(this.numberOfLogs), 4),
      ...this.logs,
      ethers.utils.hexZeroPad(ethers.utils.hexlify(this.numberOfMessages), 4),
      ...messagePairs,
      ethers.utils.hexZeroPad(ethers.utils.hexlify(this.numberOfBytecodes), 4),
      ...bytecodePairs,
      this.version,
      this.stateDiffsSetupData.compressedStateDiffsSizeBytes,
      this.stateDiffsSetupData.enumerationIndexSizeBytes,
      this.stateDiffsSetupData.compressedStateDiffs,
      this.stateDiffsSetupData.numberOfStateDiffsBytes,
      this.stateDiffsSetupData.encodedStateDiffs,
    ]);
  }
}
