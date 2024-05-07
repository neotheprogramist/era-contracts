// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L1ContractDeployer} from "./_SharedL1ContractDeployer.t.sol";
import {RegisterHyperchainsScript} from "../../../scripts-rs/script/RegisterHyperchains.s.sol";
import {ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";

contract HyperchainDeployer is L1ContractDeployer {
    RegisterHyperchainsScript deployScript;
    HyperchainDeployInfo[] hyperchainsToDeploy;

    struct HyperchainDeployInfo {
        string name;
        RegisterHyperchainsScript.HyperchainDescription description;
    }

    uint256 currentHyperChainId = 10;
    uint256 eraHyperchainId = 9;
    uint256[] hyperchainIds;

    function deployHyperchains() internal {
        deployScript = new RegisterHyperchainsScript();

        hyperchainsToDeploy.push(getDefaultHyperchainDeployInfo("era", eraHyperchainId, ETH_TOKEN_ADDRESS));
        hyperchainIds.push(eraHyperchainId);

        saveHyperchainConfig();

        vm.setEnv("HYPERCHAINS_CONFIG", "/scripts-rs/script-out/output-deploy-hyperchains.toml");

        deployScript.run();
    }

    function addNewHyperchainToDeploy(string memory _name, address _baseToken) internal {
        hyperchainsToDeploy.push(getDefaultHyperchainDeployInfo(_name, currentHyperChainId, _baseToken));
        hyperchainIds.push(currentHyperChainId);
        currentHyperChainId++;
    }

    function getDefaultDescription(
        uint256 __chainId,
        address __baseToken
    ) internal returns (RegisterHyperchainsScript.HyperchainDescription memory description) {
        description = RegisterHyperchainsScript.HyperchainDescription({
            hyperchainChainId: __chainId,
            baseToken: __baseToken,
            bridgehubCreateNewChainSalt: 0,
            validiumMode: false,
            validatorSenderOperatorCommitEth: address(0),
            validatorSenderOperatorBlobsEth: address(1),
            baseTokenGasPriceMultiplierNominator: uint128(1),
            baseTokenGasPriceMultiplierDenominator: uint128(1)
        });
    }

    function getDefaultHyperchainDeployInfo(
        string memory __name,
        uint256 __chainId,
        address __baseToken
    ) internal returns (HyperchainDeployInfo memory deployInfo) {
        deployInfo = HyperchainDeployInfo({name: __name, description: getDefaultDescription(__chainId, __baseToken)});
    }

    function saveHyperchainConfig() public {
        string memory serialized;

        for (uint256 i = 0; i < hyperchainsToDeploy.length; i++) {
            HyperchainDeployInfo memory info = hyperchainsToDeploy[i];
            RegisterHyperchainsScript.HyperchainDescription memory description = info.description;
            string memory hyperchainName = info.name;

            vm.serializeUint(hyperchainName, "hyperchain_chain_id", description.hyperchainChainId);
            vm.serializeAddress(hyperchainName, "base_token_addr", description.baseToken);
            vm.serializeUint(
                hyperchainName,
                "bridgehub_create_new_chain_salt",
                description.bridgehubCreateNewChainSalt
            );

            uint256 validiumMode = 0;

            if (description.validiumMode) {
                validiumMode = 1;
            }

            vm.serializeUint(hyperchainName, "validium_mode", validiumMode);

            vm.serializeAddress(
                hyperchainName,
                "validator_sender_operator_commit_eth",
                description.validatorSenderOperatorCommitEth
            );
            vm.serializeAddress(
                hyperchainName,
                "validator_sender_operator_blobs_eth",
                description.validatorSenderOperatorBlobsEth
            );
            vm.serializeUint(
                hyperchainName,
                "base_token_gas_price_multiplier_nominator",
                description.baseTokenGasPriceMultiplierNominator
            );

            string memory single_serialized = vm.serializeUint(
                hyperchainName,
                "base_token_gas_price_multiplier_denominator",
                description.baseTokenGasPriceMultiplierDenominator
            );

            serialized = vm.serializeString("hyperchain", hyperchainName, single_serialized);
        }

        string memory toml = vm.serializeString("toml1", "hyperchains", serialized);
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts-rs/script-out/output-deploy-hyperchains.toml");
        vm.writeToml(toml, path);
    }

    function getHyperchainAddress(uint256 _chainId) public view returns (address) {
        return bridgeHub.getHyperchain(_chainId);
    }

    function getHyperchainBaseToken(uint256 _chainId) public view returns (address) {
        return bridgeHub.baseToken(_chainId);
    }
}

contract TestHyperchainDeployConfig is HyperchainDeployer {
    function test_saveAndReadHyperchainsConfig() public {
        RegisterHyperchainsScript deployScript = new RegisterHyperchainsScript();
        address someBaseAddress = makeAddr("baseToken");
        hyperchainsToDeploy.push(getDefaultHyperchainDeployInfo("era", currentHyperChainId, ETH_TOKEN_ADDRESS));
        hyperchainsToDeploy.push(getDefaultHyperchainDeployInfo("era2", currentHyperChainId + 1, someBaseAddress));

        saveHyperchainConfig();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts-rs/script-out/output-deploy-hyperchains.toml");
        string memory toml = vm.readFile(path);
        string[] memory hyperchains = vm.parseTomlKeys(toml, "$.hyperchains");

        vm.setEnv("HYPERCHAINS_CONFIG", "/scripts-rs/script-out/output-deploy-hyperchains.toml");

        RegisterHyperchainsScript.HyperchainDescription[] memory descriptions = deployScript.readHyperchainsConfig();

        for (uint256 i = 0; i < descriptions.length; i++) {
            RegisterHyperchainsScript.HyperchainDescription memory description = descriptions[i];
            RegisterHyperchainsScript.HyperchainDescription memory hyperchain = hyperchainsToDeploy[i].description;

            assertEq(hyperchain.baseToken, description.baseToken);
            assertEq(hyperchain.bridgehubCreateNewChainSalt, description.bridgehubCreateNewChainSalt);

            assertEq(hyperchain.validiumMode, description.validiumMode);
            assertEq(hyperchain.validatorSenderOperatorCommitEth, description.validatorSenderOperatorCommitEth);
            assertEq(hyperchain.validatorSenderOperatorBlobsEth, description.validatorSenderOperatorBlobsEth);
            assertEq(hyperchain.hyperchainChainId, description.hyperchainChainId);
            assertEq(hyperchain.baseTokenGasPriceMultiplierNominator, description.baseTokenGasPriceMultiplierNominator);
            assertEq(
                hyperchain.baseTokenGasPriceMultiplierDenominator,
                description.baseTokenGasPriceMultiplierDenominator
            );
        }
    }
}
