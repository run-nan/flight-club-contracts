// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {FatToken} from "./fat-token.sol";

struct RootInfo {
    bytes32 attackRoot;
    bytes32 cellRoot;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct GameRegisterInfo {
    RootInfo registorRootInfo;
    uint256 bet;
    address starter;
    Signature registorSig;
    Signature starterSig;
}

struct GameStartInfo {
    RootInfo starterRootInfo;
    address registor;
}

struct Game {
    uint256 startDeadline;
    bool ended;
    mapping(address player => Signature sig) approvalSigs;
    mapping(address player => RootInfo r) rootInfos;
}

bytes32 constant PERMIT_TYPEHASH =
    keccak256("FatTokenTransferPermit(address sender,address receiver,uint256 value,uint256 nonce)");

contract Games is Initializable, OwnableUpgradeable, UUPSUpgradeable, EIP712Upgradeable {
    error FlightClub_InvalidPlayers(address[2]);
    error FlightClub_GameNotRegistered(bytes32 gameID);
    error FlightClub_GameAlreadyEnded(bytes32 gameID);
    error FlightClub_GameAlreadyStarted(bytes32 gameID);
    error FlightClub_PlayerAlreadyInAnotherGame(address player);
    error FlightClub_ExpiredGameStartRequest(bytes32 gameID);
    error FlightClub_InvalidSigner(address);
    error FlighClub_InvalidPlayer(address operator);
    error FlightClub_FailedToConfirmWinner(address winner);


    event FlightClub_GameRegistered(
        bytes32 indexed gameID, address indexed registor, address indexed starter, uint256 bet, uint256 startDeadline
    );
    event FlightClub_GameStarted(bytes32 indexed gameID);

    // MARK: state
    FatToken public fatToken;
    mapping(address => mapping(address => uint256)) private _gameNonce;
    mapping(bytes32 gameID => Game) private _games;
    mapping(address user => address enemy) private _enemy;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _checkGameNotEnded(bytes32 gameID, Game storage game) private view {
        if (game.ended) {
            revert FlightClub_GameAlreadyEnded(gameID);
        }
    }

    function _checkMsgSenderIsPlayer(Game storage game) private view {
        Signature memory sig = game.approvalSigs[msg.sender];
        if (!_isSignatureEmpty(sig)) {
            revert FlighClub_InvalidPlayer(msg.sender);
        }
    }

    function initialize(address _owner_, FatToken _fatToken_) public initializer {
        __Ownable_init(_owner_);
        __UUPSUpgradeable_init();
        __EIP712_init("FatTokenTransferPermit", "1");
        fatToken = _fatToken_;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _separatePlayers(address[2] memory players) private pure returns (address, address) {
        address smallAddr = players[0] < players[1] ? players[0] : players[1];
        address bigAddr = players[0] < players[1] ? players[1] : players[0];
        if (smallAddr == bigAddr) {
            revert FlightClub_InvalidPlayers(players);
        }
        return (smallAddr, bigAddr);
    }

    function _updateGameNonce(address[2] memory players) private {
        (address smallAddr, address bigAddr) = _separatePlayers(players);
        _gameNonce[smallAddr][bigAddr]++;
    }

    function _getGameNonce(address[2] memory players) private view returns (uint256) {
        (address smallAddr, address bigAddr) = _separatePlayers(players);
        return _gameNonce[smallAddr][bigAddr];
    }

    function _getGameID(address[2] memory players) private view returns (bytes32) {
        (address small, address big) = _separatePlayers(players);
        uint256 nonce = _getGameNonce(players);
        return keccak256(abi.encode(small, big, nonce));
    }

    function _getGameID() private view returns (bytes32) {
        address[2] memory players = [msg.sender, _enemy[msg.sender]];
        (address small, address big) = _separatePlayers(players);
        uint256 nonce = _getGameNonce(players);
        return keccak256(abi.encode(small, big, nonce));
    }

    function _verifyFatTokenTransferPermitSig(address sender, address receiver, uint256 value, Signature memory sig)
        private
        view
        returns (bool)
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, sender, receiver, value, _getGameNonce([sender, receiver])));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, sig.v, sig.r, sig.s);
        return signer == sender;
    }

    // 先摆好飞机的玩家注册游戏
    function registerGame(GameRegisterInfo calldata info) public {
        if (_enemy[msg.sender] != address(0)) {
            revert FlightClub_PlayerAlreadyInAnotherGame(msg.sender);
        }
        if (_enemy[info.starter] != address(0)) {
            revert FlightClub_PlayerAlreadyInAnotherGame(info.starter);
        }
        bytes32 gameID = _getGameID([msg.sender, info.starter]);
        Game storage game = _games[gameID];
        if (!_verifyFatTokenTransferPermitSig(msg.sender, info.starter, info.bet, info.registorSig)) {
            revert FlightClub_InvalidSigner(msg.sender);
        }
        if (!_verifyFatTokenTransferPermitSig(info.starter, msg.sender, info.bet, info.starterSig)) {
            revert FlightClub_InvalidSigner(info.starter);
        }
        game.approvalSigs[msg.sender] = info.registorSig;
        game.approvalSigs[info.starter] = info.starterSig;
        game.rootInfos[msg.sender] = info.registorRootInfo;
        game.startDeadline = block.timestamp + 2 minutes;
        emit FlightClub_GameRegistered(gameID, msg.sender, info.starter, info.bet, game.startDeadline);
    }

    function startGame(GameStartInfo calldata info) public {
        bytes32 gameID = _getGameID([msg.sender, info.registor]);
        Game storage game = _games[gameID];
        _checkGameNotEnded(gameID, game);
        _checkMsgSenderIsPlayer(game);
        uint256 startDeadline = game.startDeadline;
        if (startDeadline == 0) {
            revert FlightClub_GameNotRegistered(gameID);
        }
        if (startDeadline == type(uint256).max) {
            revert FlightClub_GameAlreadyStarted(gameID);
        }
        if (block.timestamp > startDeadline) {
            revert FlightClub_ExpiredGameStartRequest(gameID);
        }
        game.rootInfos[msg.sender] = info.starterRootInfo;
        game.startDeadline = type(uint256).max;
        emit FlightClub_GameStarted(gameID);
    }

    function _isSignatureEmpty(Signature memory sig) private pure returns(bool) {
        return sig.r == 0 && sig.v == 0 && sig.s == 0;
    }

    function _isRootInfoEmpty(RootInfo memory rootInfo) private pure returns(bool) {
        return rootInfo.attackRoot == 0 && rootInfo.cellRoot == 0;
    }

    function winnerConfirmByProvideExpiredStarter(address expiredStarter, uint256 value) public {
        bytes32 gameID = _getGameID([msg.sender, expiredStarter]);
        Game storage game = _games[gameID];
        _checkGameNotEnded(gameID, game);
        uint256 startDeadline = game.startDeadline;
        Signature memory registorSig = game.approvalSigs[msg.sender];
        RootInfo memory starterRootInfo = game.rootInfos[expiredStarter];
        if (
            !_isSignatureEmpty(registorSig) && // 确保registor已经注册
            _isRootInfoEmpty(starterRootInfo) && // 确保starter没有启动游戏
            block.timestamp > startDeadline // 确保已经超过启动游戏的deadline
        ) {
            _endGame(game, msg.sender, expiredStarter, value);
        } else {
            revert FlightClub_FailedToConfirmWinner(msg.sender);
        }
    }

    function _endGame(Game storage game, address winner, address loser, uint256 bet) private {
        Signature memory loserSig = game.approvalSigs[loser];
        if (!_verifyFatTokenTransferPermitSig(loser, winner, bet, loserSig)) {
            revert FlightClub_InvalidSigner(loser);
        }
        fatToken.transferFrom(loser, winner, bet);
        game.ended = true;
    }
}
