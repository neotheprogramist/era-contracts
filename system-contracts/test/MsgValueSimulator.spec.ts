import {MsgValueSimulator, MsgValueSimulatorFactory} from "../typechain";
import {deployContract, deployContractOnAddress, getWallets } from "./shared/utils";
import {
    TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS
} from "./shared/constants";
import { prepareEnvironment } from "./shared/mocks";
import {expect} from "chai";
import {EXTRA_ABI_CALLER_ADDRESS, encodeExtraAbiCallerCalldata} from "./shared/extraAbiCaller";
import {BigNumber} from "ethers";
import { Contract } from "zksync-web3";
describe("L2EthToken tests", () => {
    let messageValueSimulator: MsgValueSimulator;
    let extraAbiCaller: Contract;
    let messageValueSimulatorSystemCall: MsgValueSimulator;

    before(async () => {
        await prepareEnvironment();
        const deployerWallet = getWallets()[0];
        await deployContractOnAddress(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, "MsgValueSimulator");
        messageValueSimulator = MsgValueSimulatorFactory.connect(TEST_MSG_VALUE_SYSTEM_CONTRACT_ADDRESS, deployerWallet);
        const messageValueSimulatorSystemCallContract = await deployContract("SystemCaller", [messageValueSimulator.address]);
        messageValueSimulatorSystemCall = MsgValueSimulatorFactory.connect(messageValueSimulatorSystemCallContract.address, deployerWallet);
        extraAbiCaller = new Contract(EXTRA_ABI_CALLER_ADDRESS, [], deployerWallet);
    });

    describe("fallback", () => {
        it("should fail if not called as System Call", async () => {
            await expect(
                messageValueSimulator.fallback({data: "0x"})
            ).to.be.revertedWith("This method require system call flag");
        });

        it("should get reverted if called by itself", async () => {
            const abiParams = await extraAbiCaller.fallback({
                data: encodeExtraAbiCallerCalldata(
                    messageValueSimulator.address,
                    BigNumber.from(0),
            [
                        '0x1111111111111111111111111111111111111111111111111111111111111111',
                        '0x2222222222222222222222222222222222222222222222222222222222222222',
                        '0x3333333333333333333333333333333333333333333333333333333333333333',
                        '0x4444444444444444444444444444444444444444444444444444444444444444',
                        '0x5555555555555555555555555555555555555555555555555555555555555555',
                        '0x6666666666666666666666666666666666666666666666666666666666666666',
                        '0x7777777777777777777777777777777777777777777777777777777777777777',
                        '0x8888888888888888888888888888888888888888888888888888888888888888',
                        '0x9999999999999999999999999999999999999999999999999999999999999999',
                        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                    ],
                '0x',
                )}
            );

            await expect(
                messageValueSimulatorSystemCall.fallback()
            )
                .to.emit(messageValueSimulator, 'AbiParams')
                .withArgs(BigInt(0), false, messageValueSimulator.address);
        });


        // it("should attempt to transfer token to recipient if value is non-zero", async () => {

        // });

    //
    //     it("should revert if transfer fails", async () => {
    //
    //     });
    });
    //
    // describe("_getAbiParams", () => {
    //    it("should return the correct abi params", async () => {
    //
    //    });
    // });

});
