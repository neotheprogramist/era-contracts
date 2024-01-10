import { ethers, network } from "hardhat";
import { L1MessengerFactory } from "../typechain";
import type { L1Messenger } from "../typechain"; 
import { prepareEnvironment, setResult } from "./shared/mocks";
import { deployContractOnAddress, getCode, getWallets } from "./shared/utils";
import { utils, type Wallet } from "zksync-web3";
import {
  TEST_KNOWN_CODE_STORAGE_CONTRACT_ADDRESS,
  TEST_L1_MESSENGER_SYSTEM_CONTRACT_ADDRESS,
  TEST_BOOTLOADER_FORMAL_ADDRESS
} from "./shared/constants";
import { expect } from "chai";
import { randomBytes } from "crypto";
import _ from "lodash";

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

  describe("sendL2ToL1Log", async () => {
    
    it("should revert when not called by the system contract", async () => {
      const isService = true;
      const key = ethers.utils.hexlify(randomBytes(32));
      const value = ethers.utils.hexlify(randomBytes(32));
      await expect(l1Messenger.connect(getWallets()[2]).sendL2ToL1Log(isService, key, value)).to.be.rejectedWith(
        "This method require the caller to be system contract"
      );
    });

    it("should emit L2ToL1LogSent event when called by the system contract", async () => {
      const isService = true;
      const key = ethers.utils.hexlify(randomBytes(32));
      const value = ethers.utils.hexlify(randomBytes(32));
      
      const txNumberInBlock = 1;
      const callResult = {
        failure: false,
        returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
      };
      await setResult("SystemContext", "txNumberInBlock", [], callResult);

      await expect(l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value))
        .to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([0, isService, txNumberInBlock, l1MessengerAccount.address, key, value]);
    });

    it("should emit L2ToL1LogSent event when called by the system contract with isService false", async () => {
      const isService = false;
      const key = ethers.utils.hexlify(randomBytes(32));
      const value = ethers.utils.hexlify(randomBytes(32));

      const txNumberInBlock = 1;
      const callResult = {
        failure: false,
        returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
      };

      await setResult("SystemContext", "txNumberInBlock", [], callResult);
      await expect(l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value))
        .to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([0, isService, txNumberInBlock, l1MessengerAccount.address, key, value]);
    });

    it("should revert when called by the system contract with empty key & value", async () => {
      const isService = true;
      const key = ethers.utils.hexlify([]);
      const value = ethers.utils.hexlify([]);
      await expect(l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value)).to.be.rejected;
    });

    it("should revert when called by the system contract with key & value > 32 bytes", async () => {
      const isService = true;
      const key = ethers.utils.hexlify(randomBytes(33));
      const value = ethers.utils.hexlify(randomBytes(33));
      await expect(l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value)).to.be.rejected;
    });

    it("should revert when called by the system contract with key & value < 32 bytes", async () => {
      const isService = true;
      const key = ethers.utils.hexlify(randomBytes(31));
      const value = ethers.utils.hexlify(randomBytes(31));
      await expect(l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value)).to.be.rejected;
    });
  });

  describe("sendToL1", async () => {
    it("should emit L1MessageSent & L2ToL1LogSent events", async () => {
      const message = ethers.utils.hexlify(randomBytes(32));
      const expectedHash = ethers.utils.keccak256(message);
      const expectedKey = ethers.utils
        .hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32)
        .toLowerCase();
  
      const txNumberInBlock = 1; 
      const callResult = {
        failure: false,
        returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
      };
      await setResult("SystemContext", "txNumberInBlock", [], callResult);
  
      await expect(l1Messenger.connect(l1MessengerAccount).sendToL1(message))
        .to.emit(l1Messenger, "L1MessageSent")
        .withArgs(l1MessengerAccount.address, expectedHash, message)
        .and.to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([0, true, txNumberInBlock, l1Messenger.address, expectedKey, expectedHash]);
    });
  
    it("should emit L1MessageSent & L2ToL1LogSent events when called with default account", async () => {
      const message = ethers.utils.hexlify(randomBytes(64));
      const expectedHash = ethers.utils.keccak256(message);
      const expectedKey = ethers.utils.hexZeroPad(ethers.utils.hexStripZeros(wallet.address), 32).toLowerCase();
  
      const txNumberInBlock = 1;
      const callResult = {
        failure: false,
        returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
      };
      await setResult("SystemContext", "txNumberInBlock", [], callResult);
  
      await expect(l1Messenger.sendToL1(message))
        .to.emit(l1Messenger, "L1MessageSent")
        .withArgs(wallet.address, expectedHash, message)
        .and.to.emit(l1Messenger, "L2ToL1LogSent")
        .withArgs([0, true, txNumberInBlock, l1Messenger.address, expectedKey, expectedHash]);
    });
  });

  describe("requestBytecodeL1Publication", async () => {
    it("should revert when not called by known code storage contract", async () => {
      const byteCodeHash = ethers.utils.hexlify(randomBytes(32));
      await expect(l1Messenger.requestBytecodeL1Publication(byteCodeHash)).to.be.rejectedWith("Inappropriate caller");
    });

    it("shoud revert when byteCodeHash < 32 bytes, called by known code system contract", async () => {
      const byteCodeHash = ethers.utils.hexlify(randomBytes(8));
      await expect(l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(byteCodeHash)).to.be
        .rejected;
    });

    it("shoud revert when byteCodeHash > 32 bytes, called by known code system contract", async () => {
      const byteCodeHash = ethers.utils.hexlify(randomBytes(64));
      await expect(l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(byteCodeHash)).to.be
        .rejected;
    });

    it("shoud emit event, called by known code system contract", async () => {
      const bytecode = await getCode(l1Messenger.address);
      const bytecodeHash = await ethers.utils.hexlify(utils.hashBytecode(bytecode));
      await expect(l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(bytecodeHash, { gasLimit: 130000000 }))
      .to.emit(l1Messenger, "BytecodeL1PublicationRequested").withArgs(bytecodeHash);
    });
  });

  // TODO: IN PROGRESS - for now run these tests separately
  describe("publishPubdataAndClearState", async () => {
      it("should revert when not called by bootloader", async () => {
          const totalL2ToL1PubdataAndStateDiffs = ethers.utils.hexZeroPad("0x01", 32);
          await expect(l1Messenger.connect(getWallets()[2]).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs)).to.be.rejectedWith("Callable only by the bootloader");
      });

      it("publishPubdataAndClearState passes correctly", async () => {
        // sendL2ToL1Log()
        const isService = true;
        const key = Buffer.alloc(32, 1);
        const value = Buffer.alloc(32, 2);
        
        const txNumberInBlock = 1;
        const callResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult);
        await(await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value)).wait();
        
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
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock2])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult2);
        await(await l1Messenger.connect(l1MessengerAccount).sendToL1(message)).wait();

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
        await(await l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(bytecodeHash, {gasLimit: 130000000})).wait();
        numberOfBytecodes++;
        const lengthOfBytecode = bytecode.length;
        console.log("bytecodeLength: ", ethers.utils.hexlify(lengthOfBytecode));
        

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
          bytecode
        ]);
        console.log(ethers.utils.hexlify(totalL2ToL1PubdataAndStateDiffs));
        
        // Sample data for _numberOfStateDiffs, _enumerationIndexSize, _stateDiffs, _compressedStateDiffs
        const _numberOfStateDiffs = 10;
        const _enumerationIndexSize = 1;
        const _stateDiffs = ethers.utils.formatBytes32String("stateDiffs");
        const _compressedStateDiffs = ethers.utils.formatBytes32String("compressedStateDiffs");

        // Calculate the keccak256 hash of _stateDiffs
        const stateDiffHash = ethers.utils.keccak256(_stateDiffs);

        // tmp mock
        const verifyCompressedStateDiffsResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(
            ["bytes32"],
            [stateDiffHash]
          ),
        };

        await setResult("Compressor", "verifyCompressedStateDiffs",
          [
            _numberOfStateDiffs,
            _enumerationIndexSize,
            _stateDiffs,
            _compressedStateDiffs
          ], 
          verifyCompressedStateDiffsResult
        );
        
        // publishPubdataAndClearState()
        await(await l1Messenger.connect(bootloaderAccount).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs, {gasLimit: 1000000000000000})).wait();
        
        numberOfLogs = 0;
        numberOfMessages = 0;
        numberOfBytecodes = 0;
      });

      // TOO MANY L2->L1 LOGS
      it("should revert Too many L2->L1 logs", async () => {
        // sendL2ToL1Log()
        const isService = true;
        const key = Buffer.alloc(32, 1);
        const value = Buffer.alloc(32, 2);
        
        const txNumberInBlock = 1;
        const callResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult);
        await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value);
        
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
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock2])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult2);
        await l1Messenger.connect(l1MessengerAccount).sendToL1(message);

        const senderAddress = ethers.utils
        .hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32)
        .toLowerCase();
        const messageHash = ethers.utils.keccak256(message);

        // random values senderAddress & messageHash
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
        await l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(bytecodeHash, {gasLimit: 130000000});
        numberOfBytecodes++;
        const lengthOfBytecode = bytecode.length;
        console.log("bytecodeLength: ", ethers.utils.hexlify(lengthOfBytecode));
        

        // Concatenate all the bytes together
        // set numberofLogs to 0x900 to trigger the revert (max value is 0x800)
        numberOfLogs = 0x900;
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
          bytecode
        ]);
        console.log(ethers.utils.hexlify(totalL2ToL1PubdataAndStateDiffs));
        
        
        // Sample data for _numberOfStateDiffs, _enumerationIndexSize, _stateDiffs, _compressedStateDiffs
        const _numberOfStateDiffs = 10;
        const _enumerationIndexSize = 1;
        const _stateDiffs = ethers.utils.formatBytes32String("stateDiffs");
        const _compressedStateDiffs = ethers.utils.formatBytes32String("compressedStateDiffs");

        // Calculate the keccak256 hash of _stateDiffs
        const stateDiffHash = ethers.utils.keccak256(_stateDiffs);

        // tmp mock
        const verifyCompressedStateDiffsResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(
            ["bytes32"],
            [stateDiffHash]
          ),
        };

        await setResult("Compressor", "verifyCompressedStateDiffs",
          [
            _numberOfStateDiffs,
            _enumerationIndexSize,
            _stateDiffs,
            _compressedStateDiffs
          ], 
          verifyCompressedStateDiffsResult
        );

        // publishPubdataAndClearState()
        await expect(l1Messenger.connect(bootloaderAccount).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs))
        .to.be.rejectedWith("Too many L2->L1 logs");
        
        numberOfLogs = 0;
        numberOfMessages = 0;
        numberOfBytecodes = 0;
      });

      it("should revert reconstructedChainedLogsHash !== chainedLogsHash", async () => {
        // sendL2ToL1Log()
        const isService = true;
        const key = Buffer.alloc(32, 1);
        const value = Buffer.alloc(32, 2);
        
        const txNumberInBlock = 1;
        const callResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult);
        await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value);
        
        // random key and value
        const firstLog = ethers.utils.concat([
          ethers.utils.hexlify([0]),
          ethers.utils.hexlify([isService ? 1 : 0]),
          ethers.utils.hexZeroPad(ethers.utils.hexlify(txNumberInBlock), 2),
          ethers.utils.hexZeroPad(l1MessengerAccount.address, 20),
          ethers.utils.hexlify(randomBytes(32)),
          ethers.utils.hexlify(randomBytes(32)),
      ]);
        numberOfLogs++;
        console.log("firstLog:\n ", ethers.utils.hexlify(firstLog));
        console.log("numberOfLogs: ", ethers.utils.hexlify(numberOfLogs));
        
        // sendToL1()
        const message = Buffer.alloc(32, 3);
        const txNumberInBlock2 = 1; 
        const callResult2 = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock2])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult2);
        await l1Messenger.connect(l1MessengerAccount).sendToL1(message);

        const senderAddress = ethers.utils
        .hexZeroPad(ethers.utils.hexStripZeros(l1MessengerAccount.address), 32)
        .toLowerCase();
        const messageHash = ethers.utils.keccak256(message);

        // random values senderAddress & messageHash
        const secondLog = ethers.utils.concat([
          ethers.utils.hexlify([0]),
          ethers.utils.hexlify([isService ? 1 : 0]),
          ethers.utils.hexZeroPad(ethers.utils.hexlify(txNumberInBlock), 2),
          ethers.utils.hexZeroPad(l1Messenger.address, 20),
          ethers.utils.hexlify(randomBytes(32)),
          ethers.utils.hexlify(randomBytes(32)),
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
        await l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(bytecodeHash, {gasLimit: 130000000});
        numberOfBytecodes++;
        const lengthOfBytecode = bytecode.length;
        console.log("bytecodeLength: ", ethers.utils.hexlify(lengthOfBytecode));
        

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
          bytecode
        ]);
        console.log(ethers.utils.hexlify(totalL2ToL1PubdataAndStateDiffs));
        
        
        // Sample data for _numberOfStateDiffs, _enumerationIndexSize, _stateDiffs, _compressedStateDiffs
        const _numberOfStateDiffs = 10;
        const _enumerationIndexSize = 1;
        const _stateDiffs = ethers.utils.formatBytes32String("stateDiffs");
        const _compressedStateDiffs = ethers.utils.formatBytes32String("compressedStateDiffs");

        // Calculate the keccak256 hash of _stateDiffs
        const stateDiffHash = ethers.utils.keccak256(_stateDiffs);

        // tmp mock
        const verifyCompressedStateDiffsResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(
            ["bytes32"],
            [stateDiffHash]
          ),
        };

        await setResult("Compressor", "verifyCompressedStateDiffs",
          [
            _numberOfStateDiffs,
            _enumerationIndexSize,
            _stateDiffs,
            _compressedStateDiffs
          ], 
          verifyCompressedStateDiffsResult
        );

        // publishPubdataAndClearState()
        await expect(l1Messenger.connect(bootloaderAccount).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs))
        .to.be.rejectedWith("reconstructedChainedLogsHash is not equal to chainedLogsHash");
        
        numberOfLogs = 0;
        numberOfMessages = 0;
        numberOfBytecodes = 0;
      });

      it("should revert reconstructedChainedMessageHash !== chainedMessageHash", async () => {
        // sendL2ToL1Log()
        const isService = true;
        const key = Buffer.alloc(32, 1);
        const value = Buffer.alloc(32, 2);
        
        const txNumberInBlock = 1;
        const callResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult);
        await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value);
        
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
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock2])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult2);
        await l1Messenger.connect(l1MessengerAccount).sendToL1(message);

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
        await l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(bytecodeHash, {gasLimit: 130000000});
        numberOfBytecodes++;
        const lengthOfBytecode = bytecode.length;
        console.log("bytecodeLength: ", ethers.utils.hexlify(lengthOfBytecode));
        

        // Concatenate all the bytes together
        const numberOfLogsBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfLogs), 4);
        const numberOfMessagesBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfMessages), 4);
        const currentMessageLengthBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(currentMessageLength), 4);
        const numberOfBytecodesBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfBytecodes), 4);
        const lengthOfBytecodeBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(lengthOfBytecode), 4);

        // incorrect message
        const totalL2ToL1PubdataAndStateDiffs = ethers.utils.concat([
          numberOfLogsBytes,
          firstLog,
          secondLog,
          numberOfMessagesBytes,
          currentMessageLengthBytes,
          ethers.utils.hexlify(randomBytes(32)),
          numberOfBytecodesBytes,
          lengthOfBytecodeBytes,
          bytecode
        ]);
        console.log(ethers.utils.hexlify(totalL2ToL1PubdataAndStateDiffs));
        
        
        // publishPubdataAndClearState()
        await expect(l1Messenger.connect(bootloaderAccount).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs))
        .to.be.rejectedWith("reconstructedChainedMessagesHash is not equal to chainedMessagesHash");
        
        numberOfLogs = 0;
        numberOfMessages = 0;
        numberOfBytecodes = 0;
      });

      it("should revert not equal to chainedL1BytecodesRevealDataHash", async () => {
        // sendL2ToL1Log()
        const isService = true;
        const key = Buffer.alloc(32, 1);
        const value = Buffer.alloc(32, 2);
        
        const txNumberInBlock = 1;
        const callResult = {
          failure: false,
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult);
        await l1Messenger.connect(l1MessengerAccount).sendL2ToL1Log(isService, key, value);
        
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
          returnData: ethers.utils.defaultAbiCoder.encode(["uint16"], [txNumberInBlock2])
        };
        await setResult("SystemContext", "txNumberInBlock", [], callResult2);
        await l1Messenger.connect(l1MessengerAccount).sendToL1(message);

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
        await l1Messenger.connect(knownCodeStorageAccount).requestBytecodeL1Publication(bytecodeHash, {gasLimit: 130000000});
        numberOfBytecodes++;
        const lengthOfBytecode = bytecode.length;
        console.log("bytecodeLength: ", ethers.utils.hexlify(lengthOfBytecode));
        

        // Concatenate all the bytes together
        const numberOfLogsBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfLogs), 4);
        const numberOfMessagesBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfMessages), 4);
        const currentMessageLengthBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(currentMessageLength), 4);
        const numberOfBytecodesBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(numberOfBytecodes), 4);
        const lengthOfBytecodeBytes = ethers.utils.hexZeroPad(ethers.utils.hexlify(lengthOfBytecode), 4);

        const randomByteLength = 0xc042;
        const totalL2ToL1PubdataAndStateDiffs = ethers.utils.concat([
          numberOfLogsBytes,
          firstLog,
          secondLog,
          numberOfMessagesBytes,
          currentMessageLengthBytes,
          message,
          numberOfBytecodesBytes,
          lengthOfBytecodeBytes,
          ethers.utils.hexlify(ethers.utils.randomBytes(randomByteLength))
        ]);
        console.log(ethers.utils.hexlify(totalL2ToL1PubdataAndStateDiffs));
        
        
        // publishPubdataAndClearState()
        await expect(l1Messenger.connect(bootloaderAccount).publishPubdataAndClearState(totalL2ToL1PubdataAndStateDiffs))
        .to.be.rejectedWith("reconstructedChainedL1BytecodesRevealDataHash is not equal to chainedL1BytecodesRevealDataHash");
        
        numberOfLogs = 0;
        numberOfMessages = 0;
        numberOfBytecodes = 0;
      });
  });
});
