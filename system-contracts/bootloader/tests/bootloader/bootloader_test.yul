function TEST_safeSub() {
    testing_assertEq(safeSub(10, 7, "err"), 3, "Failed to subtract 7")
    testing_assertEq(safeSub(10, 8, "err"), 2, "Failed to subtract 8")
}

function TEST_safeDiv() {
    testing_assertEq(safeDiv(4, 2, "err"), 2, "Simple division")
    testing_assertEq(safeDiv(5, 2, "err"), 2, "Rounding")
    testing_assertEq(safeDiv(5, 3, "err"), 1, "Rounding down")
    testing_assertEq(safeDiv(4, 3, "err"), 1, "Rounding down")
    testing_assertEq(safeDiv(0, 3, "err"), 0, "Rounding down")
}
function TEST_safeDivAssert() {
    testing_testWillFailWith("divByZero")
    safeDiv(4, 0, "divByZero")
}

function TEST_asserts() {
    testing_testWillFailWith("willFail")
    safeSub(10, 12, "willFail")
}

function TEST_safeMul() {
    testing_assertEq(safeMul(4, 2, "err"), 8, "Simple")
    testing_assertEq(safeMul(0, 2, "err"), 0, "With zero")
    testing_assertEq(safeMul(0, 0, "err"), 0, "With zero")
    testing_assertEq(safeMul(2, 0, "err"), 0, "With zero")
}

function TEST_safeMulAssert() {
    testing_testWillFailWith("overflow")
    let left := shl(129, 1)
    testing_log("left", left)
    safeMul(left, left, "overflow")
}

// function TEST_should ignore

function TEST_strLen() {
    testing_assertEq(getStrLen("abcd"), 4, "short string")
    testing_assertEq(getStrLen("00"), 2, "0 filled string")
    testing_assertEq(getStrLen(""), 0, "empty string")
    testing_assertEq(getStrLen("12345678901234567890123456789012"), 32, "max length")
    testing_assertEq(getStrLen("1234567890123456789012345678901234"), 0, "over max length")
}

function TEST_simple_transaction() {
    // We'll test the transaction from 0.json
    let txDataOffset := testing_txDataOffset(0)
    let innerTxDataOffset := add(txDataOffset, 0x20)
    testing_assertEq(getGasPerPubdataByteLimit(innerTxDataOffset), 0xC350, "Invalid pubdata limit")
}

function TEST_getTransactionUpfrontOverhead() {
    // For very large transactions it should be proportional to the memory,
    // but for small ones, the transaction slots are more important

    let smallTxOverhead := getTransactionUpfrontOverhead(32)
    let largeTxOverhead := getTransactionUpfrontOverhead(1000000)

    testing_assertEq(smallTxOverhead, TX_SLOT_OVERHEAD_GAS(), "Invalid small tx overhead")
    testing_assertEq(largeTxOverhead, mul(1000000, MEMORY_OVERHEAD_GAS()), "Invalid small tx overhead")
}

function TEST_getFeeParams_HighPubdataPrice() {
    // Under very large L1 gas price, the L2 base fee will start rising to ensure the
    // boundary on the gasLimit

    // 150k gwei L1 pubdata price
    let veryHighL1PubdataPrice := 150000000000000
    // 0.1 gwei L2 base fee
    let l2GasPrice := 100000000

    let baseFee, gasPricePerPubdata := getFeeParams(
        veryHighL1PubdataPrice,
        // 0.1 gwei L2 base fee
        l2GasPrice
    )

    testing_assertEq(baseFee, ceilDiv(veryHighL1PubdataPrice, MAX_L2_GAS_PER_PUBDATA()), "Invalid base fee")
    testing_assertEq(gasPricePerPubdata, MAX_L2_GAS_PER_PUBDATA(), "Invalid gasPricePerPubdata")
}

function TEST_getFeeParams_LowPubdataPrice() {
    // Under low to medium pubdata price, the baseFee is equal to the fair gas price,
    // while the gas per pubdata pubdata is derived by strict division

    // 0.2 gwei L1 pubdata price
    let veryLowL1GasPrice := 200000000
    // 0.1 gwei L2 base fee
    let l2GasPrice := 100000000

    let baseFee, gasPricePerPubdata := getFeeParams(
        veryLowL1GasPrice,
        l2GasPrice
    )

    testing_assertEq(baseFee, l2GasPrice, "Invalid base fee")
    testing_assertEq(gasPricePerPubdata, div(veryLowL1GasPrice, l2GasPrice), "Invalid gasPricePerPubdata")
}

function TEST_systemLogKeys() {
    // Test that the values for various system log keys are correct
    let chainedPriorityTxnHashLogKey := chainedPriorityTxnHashLogKey()
    let numberOfLayer1TxsLogKey := numberOfLayer1TxsLogKey()
    let protocolUpgradeTxHashKey := protocolUpgradeTxHashKey()

    testing_assertEq(chainedPriorityTxnHashLogKey, 5, "Invalid priority txn hash log key")
    testing_assertEq(numberOfLayer1TxsLogKey, 6, "Invalid num layer 1 txns log key")
    testing_assertEq(protocolUpgradeTxHashKey, 13, "Invalid protocol upgrade txn hash log key")
}

// function processTx(
//                 txDataOffset,
//                 resultPtr,
//                 transactionIndex,
//                 isETHCall,
//                 gasPerPubdata
//             ) {
//                 // We set the L2 block info for this particular transaction
//                 setL2Block(transactionIndex)

//                 let innerTxDataOffset := add(txDataOffset, 32)

//                 // By default we assume that the transaction has failed.
//                 mstore(resultPtr, 0)

//                 let userProvidedPubdataPrice := getGasPerPubdataByteLimit(innerTxDataOffset)
//                 debugLog("userProvidedPubdataPrice:", userProvidedPubdataPrice)

//                 debugLog("gasPerPubdata:", gasPerPubdata)

//                 switch getTxType(innerTxDataOffset)
//                     case 254 {
//                         // This is an upgrade transaction.
//                         // Protocol upgrade transactions are processed totally in the same manner as the normal L1->L2 transactions,
//                         // the only difference are:
//                         // - They must be the first one in the batch
//                         // - They have a different type to prevent tx hash collisions and preserve the expectation that the
//                         // L1->L2 transactions have priorityTxId inside them.
//                         if transactionIndex {
//                             assertionError("Protocol upgrade tx not first")
//                         }

//                         // This is to be called in the event that the L1 Transaction is a protocol upgrade txn.
//                         // Since this is upgrade transactions, we are okay that the gasUsed by the transaction will
//                         // not cover this additional hash computation
//                         let canonicalL1TxHash := getCanonicalL1TxHash(txDataOffset)
//                         sendToL1Native(true, protocolUpgradeTxHashKey(), canonicalL1TxHash)

//                         processL1Tx(txDataOffset, resultPtr, transactionIndex, userProvidedPubdataPrice, false)
//                     }
//                     case 255 {
//                         // This is an L1->L2 transaction.
//                         processL1Tx(txDataOffset, resultPtr, transactionIndex, userProvidedPubdataPrice, true)
//                     }
//                     default {
//                         // The user has not agreed to this pubdata price
//                         if lt(userProvidedPubdataPrice, gasPerPubdata) {
//                             revertWithReason(UNACCEPTABLE_GAS_PRICE_ERR_CODE(), 0)
//                         }

//                         <!-- @if BOOTLOADER_TYPE=='proved_batch' -->
//                         processL2Tx(txDataOffset, resultPtr, transactionIndex, gasPerPubdata)
//                         <!-- @endif -->

//                         <!-- @if BOOTLOADER_TYPE=='playground_batch' -->
//                         switch isETHCall
//                             case 1 {
//                                 let gasLimitForTx, reservedGas := getGasLimitForTx(
//                                     innerTxDataOffset,
//                                     transactionIndex,
//                                     gasPerPubdata,
//                                     L2_TX_INTRINSIC_GAS(),
//                                     L2_TX_INTRINSIC_PUBDATA()
//                                 )

//                                 let nearCallAbi := getNearCallABI(gasLimitForTx)
//                                 checkEnoughGas(gasLimitForTx)

//                                 if iszero(gasLimitForTx) {
//                                     // We disallow providing 0 gas limit for an eth call transaction.
//                                     // Note, in case it is 0 `ZKSYNC_NEAR_CALL_ethCall` will get the entire
//                                     // gas of the bootloader.
//                                     revertWithReason(
//                                         ETH_CALL_ERR_CODE(),
//                                         0
//                                     )
//                                 }

//                                 ZKSYNC_NEAR_CALL_ethCall(
//                                     nearCallAbi,
//                                     txDataOffset,
//                                     resultPtr,
//                                     reservedGas,
//                                     gasPerPubdata
//                                 )
//                             }
//                             default {
//                                 processL2Tx(txDataOffset, resultPtr, transactionIndex, gasPerPubdata)
//                             }
//                         <!-- @endif -->
//                     }
//     }

    function TEST_ensurePayment() {
        let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
        let txDataOffset := mload(add(txPtr, 32))
        let gasPrice := basefee()

        ensurePayment(txDataOffset, gasPrice)

    }

    function TEST_mintEther() {
        let to := BOOTLOADER_FORMAL_ADDR()
        let amount := 20
        let useNearCallPanic := 1
        let bootloaderBalance := balance(BOOTLOADER_FORMAL_ADDR())

        mintEther(to, amount, useNearCallPanic)

        testing_assertEq(amount, sub(balance(BOOTLOADER_FORMAL_ADDR()), bootloaderBalance), "Mint ether failed")
    }

// processL1Tx

// l1TxPreparation

// processL2Tx

// l2TxValidation

// l2TxExecution

// refundCurrentL2Transaction

function TEST_directETHTransferRevert() {
    let amount := 10
    let recipient := BOOTLOADER_FORMAL_ADDR()

    testing_testWillFailWith("Failed to refund")
    directETHTransfer(amount, recipient)
}

function TEST_directETHTransfer() {
    mintEther(BOOTLOADER_FORMAL_ADDR(), 50, 1)
    let amount := 10
    let recipient := ACCOUNT_CODE_STORAGE_ADDR()

    directETHTransfer(amount, recipient)

    testing_assertEq(amount, balance(ACCOUNT_CODE_STORAGE_ADDR()) , "Direct ETH transfer failed")
    testing_assertEq(balance(BOOTLOADER_FORMAL_ADDR()), 40, "Direct ETH transfer failed")
}

function TEST_accountPayForTxFail() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let account := getFrom(innerTxDataOffset)

    let success := accountPayForTx(account, txDataOffset)

    testing_assertEq(success, 0, "Account pay for Tx failed")
}

function TEST_accountPayForTx() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let account := getFrom(innerTxDataOffset)

    mintEther(account, 20, 1)

    let success := accountPayForTx(account, txDataOffset)

    testing_assertEq(success, 1, "Account pay for Tx failed")
}

function TEST_saveTxHashes() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))

    saveTxHashes(txDataOffset)

    testing_assertEq(mload(CURRENT_L2_TX_HASHES_BEGIN_BYTE()), 0xcc688b06478c77de5727148fa48a7b5db3be430af5270e024cedcfe466cfa752, "Invalid tx hash")
}

// accountValidateTx

function TEST_markFactoryDepsForTxRevert() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)

    let factoryDepsPtr := getFactoryDepsPtr(innerTxDataOffset)
    mstore(factoryDepsPtr, 33)

    let isL1Tx := 0

    testing_testWillFailWith("too many factory deps")

    markFactoryDepsForTx(innerTxDataOffset, isL1Tx)
}

function TEST_markFactoryDepsForTx() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let isL1Tx := 0

    markFactoryDepsForTx(innerTxDataOffset, isL1Tx)

    testing_assertEq(mload(NEW_FACTORY_DEPS_BEGIN_BYTE()), 3843454494, "Invalid factory deps")
}

function TEST_executeL1Tx() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let from := getFrom(innerTxDataOffset)

    let result := executeL1Tx(innerTxDataOffset, from)

    testing_assertEq(1, result, "Execute L1 tx failed")
}

function TEST_executeL2Tx() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let from := getFrom(innerTxDataOffset)

    let result := executeL2Tx(txDataOffset, from)

    testing_assertEq(1, result, "Execute L2 tx failed")
}

function TEST_appendTransactionHash() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let txHash := getCanonicalL1TxHash(txDataOffset)
    let isL1Tx := 1

    appendTransactionHash(txHash, isL1Tx)
}

function TEST_validateAbiEncoding() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))

    let result := validateAbiEncoding(txDataOffset)

    testing_assertEq(result, 52697504, "ABI encoding failed to validate")
}

function TEST_validateAbiEncodingInvalidOffset() {
    let txDataOffset := 12

    testing_testWillFailWith("Encoding offset")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidFrom() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 32)
    let from := 0x0000000000000000000000011000000000000000000000000000000000000000
    mstore(ptr, from)

    testing_testWillFailWith("Encoding from")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidTo() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 64)
    let to := 0x0000000000000000000000011000000000000000000000000000000000000000
    mstore(ptr, to)

    testing_testWillFailWith("Encoding to")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidGasLimit() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 96)
    let gasLimit := 0x0000000000000000000000000000000000000000000000011000000000000000
    mstore(ptr, gasLimit)

    testing_testWillFailWith("Encoding gasLimit")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidGasPerPubdata() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 128)
    let gasPerPubdata := 4294967297
    mstore(ptr, gasPerPubdata)

    testing_testWillFailWith("Encoding gasPerPubdataByteLimit")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidMaxFeePerGas() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000110000000000000000000000000000000
    mstore(ptr, maxFeePerGas)

    testing_testWillFailWith("Encoding maxFeePerGas")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidMaxPriorityFeePerGas() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000110000000000000000000000000000000
    mstore(ptr, maxPriorityFeePerGas)

    testing_testWillFailWith("Encoding maxPriorityFeePerGas")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidPaymaster() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := add(innerTxDataOffset, 224)
    let paymaster := 0x0000000000000000000000011000000000000000000000000000000000000000
    mstore(ptr, paymaster)

    testing_testWillFailWith("Encoding paymaster")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidDataPtr() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32) 
    let ptr := add(innerTxDataOffset, 448)
    let dataPtr := 600
    mstore(ptr, dataPtr)

    testing_testWillFailWith("Encoding data")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidSignaturePtr() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32) 
    let ptr := add(innerTxDataOffset, 480)
    let signaturePtr := 600
    mstore(ptr, signaturePtr)

    testing_testWillFailWith("Encoding signature")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidFactoryDepsPtr() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32) 
    let ptr := add(innerTxDataOffset, 512)
    let factoryDepsPtr := 600
    mstore(ptr, factoryDepsPtr)

    testing_testWillFailWith("Encoding factoryDeps")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateAbiEncodingInvalidReservedDynamicPtr() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32) 
    let ptr := add(innerTxDataOffset, 576)
    let reservedDynamicPtr := 600
    mstore(ptr, reservedDynamicPtr)

    testing_testWillFailWith("Encoding reservedDynamic")

    validateAbiEncoding(txDataOffset)
}

function TEST_validateTypedTxStructure() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureReservedDynamic() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    let ptr := getReservedDynamicPtr(innerTxDataOffset)
    mstore(ptr, 1)

    testing_testWillFailWith("non-empty reservedDynamic")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureEIP1559() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000020000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    testing_testWillFailWith("EIP1559 params wrong")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureGasPerPubdataByteLimit() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := add(innerTxDataOffset, 128)
    let gasPerPubdataByteLimit := 50001
    mstore(ptr, gasPerPubdataByteLimit)

    testing_testWillFailWith("Gas per pubdata is wrong")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructurePaymaster() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := add(innerTxDataOffset, 224)
    mstore(ptr, 1)

    testing_testWillFailWith("paymaster non zero")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureReserved1() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := add(innerTxDataOffset, 352)
    mstore(ptr, 1)

    testing_testWillFailWith("reserved1 non zero")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureReserved2() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := add(innerTxDataOffset, 384)
    mstore(ptr, 1)

    testing_testWillFailWith("reserved2 non zero")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureReserved3() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := add(innerTxDataOffset, 416)
    mstore(ptr, 1)

    testing_testWillFailWith("reserved3 non zero")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructureFactoryDeps() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := getFactoryDepsPtr(innerTxDataOffset)
    mstore(ptr, 1)

    testing_testWillFailWith("factory deps non zero")

    validateTypedTxStructure(innerTxDataOffset)
}

function TEST_validateTypedTxStructurePaymasterInput() {
    let txPtr := TX_DESCRIPTION_BEGIN_BYTE()
    let txDataOffset := mload(add(txPtr, 32))
    let innerTxDataOffset := add(txDataOffset, 32)
    mstore(innerTxDataOffset, 0)

    let ptr1 := add(innerTxDataOffset, 160)
    let maxFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr1, maxFeePerGas)

    let ptr2 := add(innerTxDataOffset, 192)
    let maxPriorityFeePerGas := 0x0000000000000000000000000000000010000000000000000000000000000000
    mstore(ptr2, maxPriorityFeePerGas)

    let ptr := getPaymasterInputPtr(innerTxDataOffset)
    mstore(ptr, 1)

    testing_testWillFailWith("paymasterInput non zero")

    validateTypedTxStructure(innerTxDataOffset)
}