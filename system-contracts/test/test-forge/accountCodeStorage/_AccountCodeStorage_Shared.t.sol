// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "l1-contracts/lib/forge-std/src/Test.sol";

import {IAccountCodeStorage} from "system-contracts/contracts/interfaces/IAccountCodeStorage.sol";
import {Wallet} from "zksync-ethers";
import {AccountCodeStorage} from "system-contracts/typechain/AccountCodeStorage.d.ts";
import {ethers} from "hardhat";

contract AccountCodeFacetTest is Test {
    IAccountCodeStorage internal accountCode;
    AccountCodeFacetWrapper internal accountCodeFacetWrapper;
    AccountCodeStorage internal accountCodeStorage;
    ethers.Signer internal deployerAccount;


    function setUp() public virtual {
        accountCodeFacetWrapper = new AccountCodeFacetWrapper();
        accountCode = IAccountCodeStorage(accountCodeFacetWrapper);
        Wallet wallet = getWallets();
        deployContractOnAddress("0x0000000000000000000000000000000000009002", "AccountCodeStorage");
        AccountCodeStorage accountCodeStorage = AccountCodeStorageFactory.connect(
            "0x0000000000000000000000000000000000009002",
            wallet
        );
        ethers.Signer deployerAccount = ethers.getImpersonatedSigner(TEST_DEPLOYER_SYSTEM_CONTRACT_ADDRESS);
    }
}

//contract AccountCodeFacetWrapper is AccountCodeFacet {}
