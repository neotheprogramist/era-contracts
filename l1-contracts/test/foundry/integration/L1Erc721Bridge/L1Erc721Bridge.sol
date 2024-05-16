// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IL1ERC20Bridge} from "contracts/bridge/interfaces/IL1ERC20Bridge.sol";
import {IL1SharedBridge} from "contracts/bridge/interfaces/IL1SharedBridge.sol";
import {IL2Bridge} from "contracts/bridge/interfaces/IL2Bridge.sol";

import {IMailbox} from "contracts/state-transition/chain-interfaces/IMailbox.sol";
import {L2Message, TxStatus} from "contracts/common/Messaging.sol";
import {UnsafeBytes} from "contracts/common/libraries/UnsafeBytes.sol";
import {ReentrancyGuard} from "contracts/common/ReentrancyGuard.sol";
import {AddressAliasHelper} from "contracts/vendor/AddressAliasHelper.sol";
import {ETH_TOKEN_ADDRESS, TWO_BRIDGES_MAGIC_VALUE} from "contracts/common/Config.sol";
import {IBridgehub, L2TransactionRequestTwoBridgesInner, L2TransactionRequestDirect} from "contracts/bridgehub/IBridgehub.sol";
import {IGetters} from "contracts/state-transition/chain-interfaces/IGetters.sol";
import {L2_BASE_TOKEN_SYSTEM_CONTRACT_ADDR} from "contracts/common/L2ContractAddresses.sol";

contract L1Erc721Bridge is
    IL1SharedBridge,
    ReentrancyGuard,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    IERC721Receiver
{
    error NotImplementedError();

    /// @dev The address of the WETH token on L1.
    address public immutable override L1_WETH_TOKEN;

    /// @dev Bridgehub smart contract that is used to operate with L2 via asynchronous L2 <-> L1 communication.
    IBridgehub public immutable override BRIDGE_HUB;

    /// @dev Era's chainID
    uint256 immutable ERA_CHAIN_ID;

    /// @dev The address of zkSync Era diamond proxy contract.
    address immutable ERA_DIAMOND_PROXY;

    /// @dev Stores the first batch number on the zkSync Era Diamond Proxy that was settled after Diamond proxy upgrade.
    /// This variable is used to differentiate between pre-upgrade and post-upgrade Eth withdrawals. Withdrawals from batches older
    /// than this value are considered to have been finalized prior to the upgrade and handled separately.
    uint256 internal eraPostDiamondUpgradeFirstBatch;

    /// @dev Stores the first batch number on the zkSync Era Diamond Proxy that was settled after L1ERC20 Bridge upgrade.
    /// This variable is used to differentiate between pre-upgrade and post-upgrade ERC20 withdrawals. Withdrawals from batches older
    /// than this value are considered to have been finalized prior to the upgrade and handled separately.
    uint256 internal eraPostLegacyBridgeUpgradeFirstBatch;

    /// @dev Stores the zkSync Era batch number that processes the last deposit tx initiated by the legacy bridge
    /// This variable (together with eraLegacyBridgeLastDepositTxNumber) is used to differentiate between pre-upgrade and post-upgrade deposits. Deposits processed in older batches
    /// than this value are considered to have been processed prior to the upgrade and handled separately.
    /// We use this both for Eth and erc20 token deposits, so we need to update the diamond and bridge simultaneously.
    uint256 internal eraLegacyBridgeLastDepositBatch;

    /// @dev The tx number in the _eraLegacyBridgeLastDepositBatch of the last deposit tx initiated by the legacy bridge
    /// This variable (together with eraLegacyBridgeLastDepositBatch) is used to differentiate between pre-upgrade and post-upgrade deposits. Deposits processed in older txs
    /// than this value are considered to have been processed prior to the upgrade and handled separately.
    /// We use this both for Eth and erc20 token deposits, so we need to update the diamond and bridge simultaneously.
    uint256 internal eraLegacyBridgeLastDepositTxNumber;

    /// @dev Legacy bridge smart contract that used to hold ERC20 tokens.
    IL1ERC20Bridge public override legacyBridge;

    /// @dev A mapping chainId => bridgeProxy. Used to store the bridge proxy's address, and to see if it has been deployed yet.
    mapping(uint256 chainId => address l2Bridge) public override l2BridgeAddress;

    /// @dev A mapping chainId => L2 deposit transaction hash => keccak256(abi.encode(account, tokenAddress, amount))
    /// @dev Tracks deposit transactions from L2 to enable users to claim their funds if a deposit fails.
    mapping(uint256 chainId => mapping(bytes32 l2DepositTxHash => bytes32 depositDataHash))
        public
        override depositHappened;

    /// @dev Tracks the processing status of L2 to L1 messages, indicating whether a message has already been finalized.
    mapping(uint256 chainId => mapping(uint256 l2BatchNumber => mapping(uint256 l2ToL1MessageNumber => bool isFinalized)))
        public isWithdrawalFinalized;

    /// @dev Indicates whether the hyperbridging is enabled for a given chain.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 chainId => bool enabled) internal hyperbridgingEnabled;

    /// @dev Maps token balances for each chain to prevent unauthorized spending across hyperchains.
    /// This serves as a security measure until hyperbridging is implemented.
    /// NOTE: this function may be removed in the future, don't rely on it!
    mapping(uint256 chainId => mapping(address l1Token => uint256 balance)) public chainBalance;

    /// @notice Checks that the message sender is the bridgehub.
    modifier onlyBridgehub() {
        require(msg.sender == address(BRIDGE_HUB), "ShB not BH");
        _;
    }

    /// @notice Checks that the message sender is the bridgehub or zkSync Era Diamond Proxy.
    modifier onlyBridgehubOrEra(uint256 _chainId) {
        require(
            msg.sender == address(BRIDGE_HUB) || (_chainId == ERA_CHAIN_ID && msg.sender == ERA_DIAMOND_PROXY),
            "L1SharedBridge: not bridgehub or era chain"
        );
        _;
    }

    /// @notice Checks that the message sender is the legacy bridge.
    modifier onlyLegacyBridge() {
        require(msg.sender == address(legacyBridge), "ShB not legacy bridge");
        _;
    }

    /// @dev Contract is expected to be used as proxy implementation.
    /// @dev Initialize the implementation to prevent Parity hack.
    constructor(
        address _l1WethAddress,
        IBridgehub _bridgehub,
        uint256 _eraChainId,
        address _eraDiamondProxy
    ) reentrancyGuardInitializer {
        _disableInitializers();
        L1_WETH_TOKEN = _l1WethAddress;
        BRIDGE_HUB = _bridgehub;
        ERA_CHAIN_ID = _eraChainId;
        ERA_DIAMOND_PROXY = _eraDiamondProxy;
    }

    /// @dev Initializes a contract bridge for later use. Expected to be used in the proxy
    /// @param _owner Address which can change L2 token implementation and upgrade the bridge
    /// implementation. The owner is the Governor and separate from the ProxyAdmin from now on, so that the Governor can call the bridge.
    function initialize(address _owner) external reentrancyGuardInitializer initializer {
        require(_owner != address(0), "ShB owner 0");
        _transferOwnership(_owner);
    }

    /// @dev This sets the first post diamond upgrade batch for era, used to check old eth withdrawals
    /// @param _eraPostDiamondUpgradeFirstBatch The first batch number on the zkSync Era Diamond Proxy that was settled after diamond proxy upgrade.
    function setEraPostDiamondUpgradeFirstBatch(uint256 _eraPostDiamondUpgradeFirstBatch) external onlyOwner {
        require(eraPostDiamondUpgradeFirstBatch == 0, "ShB: eFPUB already set");
        eraPostDiamondUpgradeFirstBatch = _eraPostDiamondUpgradeFirstBatch;
    }

    /// @dev This sets the first post upgrade batch for era, used to check old token withdrawals
    /// @param _eraPostLegacyBridgeUpgradeFirstBatch The first batch number on the zkSync Era Diamond Proxy that was settled after legacy bridge upgrade.
    function setEraPostLegacyBridgeUpgradeFirstBatch(uint256 _eraPostLegacyBridgeUpgradeFirstBatch) external onlyOwner {
        require(eraPostLegacyBridgeUpgradeFirstBatch == 0, "ShB: eFPUB already set");
        eraPostLegacyBridgeUpgradeFirstBatch = _eraPostLegacyBridgeUpgradeFirstBatch;
    }

    /// @dev This sets the first post upgrade batch for era, used to check old withdrawals
    /// @param  _eraLegacyBridgeLastDepositBatch The the zkSync Era batch number that processes the last deposit tx initiated by the legacy bridge
    /// @param _eraLegacyBridgeLastDepositTxNumber The tx number in the _eraLegacyBridgeLastDepositBatch of the last deposit tx initiated by the legacy bridge
    function setEraLegacyBridgeLastDepositTime(
        uint256 _eraLegacyBridgeLastDepositBatch,
        uint256 _eraLegacyBridgeLastDepositTxNumber
    ) external onlyOwner {
        require(eraLegacyBridgeLastDepositBatch == 0, "ShB: eLOBDB already set");
        require(eraLegacyBridgeLastDepositTxNumber == 0, "ShB: eLOBDTN already set");
        eraLegacyBridgeLastDepositBatch = _eraLegacyBridgeLastDepositBatch;
        eraLegacyBridgeLastDepositTxNumber = _eraLegacyBridgeLastDepositTxNumber;
    }

    function receiveEth(uint256 _chainId) external payable {
        require(BRIDGE_HUB.getHyperchain(_chainId) == msg.sender, "receiveEth not state transition");
    }

    function initializeChainGovernance(uint256 _chainId, address _l2BridgeAddress) external onlyOwner {
        l2BridgeAddress[_chainId] = _l2BridgeAddress;
    }

    /// @notice Initiates a deposit of an ERC721 token to the L2 chain.
    function bridgehubDeposit(
        uint256 _chainId,
        address _prevMsgSender,
        // solhint-disable-next-line no-unused-vars
        uint256 _l2Value,
        bytes calldata _data
    )
        external
        payable
        override
        onlyBridgehub
        whenNotPaused
        returns (L2TransactionRequestTwoBridgesInner memory request)
    {
        require(l2BridgeAddress[_chainId] != address(0), "ShB l2 bridge not deployed");

        (address _l1Token, uint256 _tokenId, address _l2Receiver) = abi.decode(_data, (address, uint256, address));

        uint256 depositedAmount = _depositERC721Token(_prevMsgSender, IERC721(_l1Token), _tokenId);
        require(depositedAmount == 1, "ShB: wrong amount of ERC721 token deposited");

        bytes32 txDataHash = keccak256(abi.encode(_prevMsgSender, _l1Token, _tokenId));
        {
            // Request the finalization of the deposit on the L2 side
            bytes memory l2TxCalldata = _getDepositL2ERC721Calldata(_prevMsgSender, _l2Receiver, _l1Token, _tokenId);

            request = L2TransactionRequestTwoBridgesInner({
                magicValue: TWO_BRIDGES_MAGIC_VALUE,
                l2Contract: l2BridgeAddress[_chainId],
                l2Calldata: l2TxCalldata,
                factoryDeps: new bytes[](0),
                txDataHash: txDataHash
            });
        }

        emit BridgehubDepositInitiated({
            chainId: _chainId,
            txDataHash: txDataHash,
            from: _prevMsgSender,
            to: _l2Receiver,
            l1Token: _l1Token,
            amount: 1
        });
    }

    function _depositERC721Token(address _from, IERC721 _token, uint256 _tokenId) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        // slither-disable-next-line arbitrary-send-erc20
        _token.safeTransferFrom(_from, address(this), _tokenId);
        uint256 balanceAfter = _token.balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    function _getDepositL2ERC721Calldata(
        address _l1Sender,
        address _l2Receiver,
        address _l1Token,
        uint256 _tokenId
    ) internal view returns (bytes memory) {
        bytes memory gettersData = _getERC721Getters(_l1Token);
        return abi.encodeCall(IL2Bridge.finalizeDeposit, (_l1Sender, _l2Receiver, _l1Token, _tokenId, gettersData));
    }

    function _getERC721Getters(address _token) internal view returns (bytes memory) {
        (, bytes memory data1) = _token.staticcall(abi.encodeCall(IERC721Metadata.name, ()));
        (, bytes memory data2) = _token.staticcall(abi.encodeCall(IERC721Metadata.symbol, ()));
        return abi.encode(data1, data2);
    }

    function _withdrawERC721Token(address _to, IERC721 _token, uint256 _tokenId) internal returns (uint256) {
        uint256 balanceBefore = _token.balanceOf(address(this));
        // slither-disable-next-line arbitrary-send-erc20
        _token.safeTransferFrom(address(this), _to, _tokenId);
        uint256 balanceAfter = _token.balanceOf(address(this));

        return balanceBefore - balanceAfter;
    }

    function bridgehubConfirmL2Transaction(
        uint256 _chainId,
        bytes32 _txDataHash,
        bytes32 _txHash
    ) external override onlyBridgehub whenNotPaused {
        require(depositHappened[_chainId][_txHash] == 0x00, "ShB tx hap");
        depositHappened[_chainId][_txHash] = _txDataHash;
        emit BridgehubDepositFinalized(_chainId, _txDataHash, _txHash);
    }

    /*//////////////////////////////////////////////////////////////
                            NOT IMPLEMENTED
    //////////////////////////////////////////////////////////////*/

    function bridgehubDepositBaseToken(
        uint256 _chainId,
        address _prevMsgSender,
        address _l1Token,
        uint256 _amount
    ) external payable virtual onlyBridgehubOrEra(_chainId) whenNotPaused {
        revert NotImplementedError();
    }

    function finalizeWithdrawal(
        uint256 _chainId,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external override {
        revert NotImplementedError();
    }

    function claimFailedDeposit(
        uint256 _chainId,
        address _depositSender,
        address _l1Token,
        uint256 _amount,
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof
    ) external override {
        revert NotImplementedError();
    }

    /*//////////////////////////////////////////////////////////////
                            LEGACY BRIDGE UNIMPLEMENTED
    //////////////////////////////////////////////////////////////*/

    function depositLegacyErc20Bridge(
        address _prevMsgSender,
        address _l2Receiver,
        address _l1Token,
        uint256 _amount,
        uint256 _l2TxGasLimit,
        uint256 _l2TxGasPerPubdataByte,
        address _refundRecipient
    ) external payable override onlyLegacyBridge nonReentrant whenNotPaused returns (bytes32 l2TxHash) {
        revert NotImplementedError();
    }

    function finalizeWithdrawalLegacyErc20Bridge(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes calldata _message,
        bytes32[] calldata _merkleProof
    ) external override onlyLegacyBridge returns (address l1Receiver, address l1Token, uint256 amount) {
        revert NotImplementedError();
    }

    function claimFailedDepositLegacyErc20Bridge(
        address _depositSender,
        address _l1Token,
        uint256 _amount,
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof
    ) external override onlyLegacyBridge {
        revert NotImplementedError();
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all functions marked with the `whenNotPaused` modifier.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, allowing all functions marked with the `whenNotPaused` modifier to be called again.
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            ERC721Receiver
    //////////////////////////////////////////////////////////////*/

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
