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

function TEST_gasPerPubdataFromBaseFee() {
    let expected := 0 

    let baseFee := basefee()
    let pubdataPrice := 1000000000000000
    let received := gasPerPubdataFromBaseFee(baseFee, pubdataPrice

    testing_assertEq(expected, received, "Invalid Pubdata from base fee")
}

function TEST_scratchSpaceBeginByte() {
    testing_assertEq(SCRATCH_SPACE_BEGIN_BYTE(), 256, "Invalid scratch space begin byte")
}

function TEST_paymasterContextBeginSlot() {
    testing_assertEq(PAYMASTER_CONTEXT_BEGIN_SLOT(), 40, "Invalid Paymaster begin slot")
}

function TEST_paymasterContextBeginByte() {
    testing_assertEq(PAYMASTER_CONTEXT_BEGIN_BYTE(), 1280, "Invalid Paymaster begin byte")
}

function TEST_maxPostopSlots() {
    testing_assertEq(MAX_POSTOP_SLOTS(), 40, "Invalid number of PostOp slots")
}

function TEST_currentL2TxHashesBeginSlot() {
    testing_assertEq(CURRENT_L2_TX_HASHES_BEGIN_SLOT(), 73, "Invalid current L2 hashes begin slot")
}

function TEST_currentL2TxHashesBeginByte() {
    testing_assertEq(CURRENT_L2_TX_HASHES_BEGIN_BYTE(), 2336, "Invalid current L2 hashes begin byte")
}

function TEST_newFactoryDepsReservedSlots() {
    testing_assertEq(NEW_FACTORY_DEPS_RESERVED_SLOTS(), 36, "Invalid Factory reserved slots")
}

function TEST_newFactoryDepsBeginSlot() {
    testing_assertEq(NEW_FACTORY_DEPS_BEGIN_SLOT(), 75, "Invalid Factory begin slot")
}

function TEST_newFactoryDepsBeginByte() {
    testing_assertEq(NEW_FACTORY_DEPS_BEGIN_BYTE(), 2400, "Invalid Factory begin byte")
}

function TEST_txOperatorRefundBeginSlot() {
    testing_assertEq(TX_OPERATOR_REFUND_BEGIN_SLOT(), 111, "Invalid refund slot")
}

function TEST_txOperatorRefundBeginByte() {
    testing_assertEq(TX_OPERATOR_REFUND_BEGIN_BYTE(), 3552, "Invalid refund byte")
}

function TEST_txOperatorTrustedGasLimitBeginSlot() {
    testing_assertEq(TX_OPERATOR_TRUSTED_GAS_LIMIT_BEGIN_SLOT(), 20111, "Invalid trusted gas limit begin slot")
}

function TEST_txOperatorTrustedGasLimitBeginByte() {
    testing_assertEq(TX_OPERATOR_TRUSTED_GAS_LIMIT_BEGIN_BYTE(), 643552, "Invalid trusted gas limit begin byte")
}

function TEST_txOperatorL2BlockInfoBeginSlot() {
    testing_assertEq(TX_OPERATOR_L2_BLOCK_INFO_BEGIN_SLOT(), 30111, "Invalid L2 block info begin slot")
}

function TEST_txOperatorL2BlockInfoBeginByte() {
    testing_assertEq(TX_OPERATOR_L2_BLOCK_INFO_BEGIN_BYTE(), 963552, "Invalid L2 block info begin byte")
}

function TEST_txOperatorL2BlockInfoSizeBytes() {
    testing_assertEq(TX_OPERATOR_L2_BLOCK_INFO_SIZE_BYTES(), 128, "Invalid L2 block info size bytes")
}

function TEST_txOperatorL2BlockInfoSlots() {
    testing_assertEq(TX_OPERATOR_L2_BLOCK_INFO_SLOTS(), 40004, "Invalid L2 block info slots")
}
