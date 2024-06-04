// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L1ContractDeployer} from "./_SharedL1ContractDeployer.t.sol";
import {RegisterHyperchainScript} from "deploy-scripts/RegisterHyperchain.s.sol";
import {ETH_TOKEN_ADDRESS} from "contracts/common/Config.sol";

contract HyperchainDeployer is L1ContractDeployer {
    RegisterHyperchainScript deployScript;

    struct HyperchainDescription {
        uint256 hyperchainChainId;
        address baseToken;
        uint256 bridgehubCreateNewChainSalt;
        bool validiumMode;
        address validatorSenderOperatorCommitEth;
        address validatorSenderOperatorBlobsEth;
        uint128 baseTokenGasPriceMultiplierNominator;
        uint128 baseTokenGasPriceMultiplierDenominator;
    }

    struct HyperchainDeployInfo {
        string name;
        HyperchainDescription description;
    }

    uint256 currentHyperChainId = 10;
    uint256 eraHyperchainId = 9;
    uint256[] public hyperchainIds;

    function _deployEra() internal {
        vm.setEnv(
            "HYPERCHAIN_CONFIG",
            "/test/foundry/integration/deploy-scripts/script-out/output-deploy-hyperchain-era.toml"
        );

        deployScript = new RegisterHyperchainScript();
        hyperchainIds.push(eraHyperchainId);
        saveHyperchainConfig(_getDefaultHyperchainDeployInfo("era", eraHyperchainId, ETH_TOKEN_ADDRESS));
        deployScript.run();
    }

    function _deployHyperchain(string memory _name, address _baseToken) internal {
        vm.setEnv(
            "HYPERCHAIN_CONFIG",
            string.concat(
                "/test/foundry/integration/deploy-scripts/script-out/output-deploy-hyperchain-",
                _name,
                ".toml"
            )
        );
        hyperchainIds.push(currentHyperChainId);
        saveHyperchainConfig(_getDefaultHyperchainDeployInfo(_name, currentHyperChainId, _baseToken));
        currentHyperChainId++;
        deployScript.run();
    }

    function _getDefaultDescription(
        uint256 __chainId,
        address __baseToken
    ) internal returns (HyperchainDescription memory description) {
        description = HyperchainDescription({
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

    function _getDefaultHyperchainDeployInfo(
        string memory __name,
        uint256 __chainId,
        address __baseToken
    ) internal returns (HyperchainDeployInfo memory deployInfo) {
        deployInfo = HyperchainDeployInfo({name: __name, description: _getDefaultDescription(__chainId, __baseToken)});
    }

    function saveHyperchainConfig(HyperchainDeployInfo memory info) public {
        string memory serialized;
        HyperchainDescription memory description = info.description;
        string memory hyperchainName = info.name;

        vm.serializeUint("chain", "chain_chain_id", description.hyperchainChainId);
        vm.serializeAddress("chain", "base_token_addr", description.baseToken);
        vm.serializeUint("chain", "bridgehub_create_new_chain_salt", description.bridgehubCreateNewChainSalt);

        uint256 validiumMode = 0;

        if (description.validiumMode) {
            validiumMode = 1;
        }

        vm.serializeUint("chain", "validium_mode", validiumMode);

        vm.serializeAddress(
            "chain",
            "validator_sender_operator_commit_eth",
            description.validatorSenderOperatorCommitEth
        );
        vm.serializeAddress(
            "chain",
            "validator_sender_operator_blobs_eth",
            description.validatorSenderOperatorBlobsEth
        );
        vm.serializeUint(
            "chain",
            "base_token_gas_price_multiplier_nominator",
            description.baseTokenGasPriceMultiplierNominator
        );

        vm.serializeUint(
            "chain",
            "governance_min_delay",
            0
        );

        vm.serializeAddress("chain", "governance_security_council_address", address(0));

        string memory single_serialized = vm.serializeUint(
            "chain",
            "base_token_gas_price_multiplier_denominator",
            description.baseTokenGasPriceMultiplierDenominator
        );
    

        // serialized = vm.serializeString("hyperchain", "chain", single_serialized);

        string memory toml = vm.serializeString("toml1", "chain", single_serialized);
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/test/foundry/integration/deploy-scripts/script-out/output-deploy-hyperchain-",
            hyperchainName,
            ".toml"
        );
        vm.writeToml(toml, path);
    }

    function getHyperchainAddress(uint256 _chainId) public view returns (address) {
        return bridgeHub.getHyperchain(_chainId);
    }

    function getHyperchainBaseToken(uint256 _chainId) public view returns (address) {
        return bridgeHub.baseToken(_chainId);
    }
}
