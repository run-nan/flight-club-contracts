// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";


// 1 $Fat = 1 $ETH
contract FatToken is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // MARK: errors
    error FatToken_NotAllowedToTransfer(address to, uint256 value);
    error FatToken_NotAllowedToApprove(address spender, uint256 value);
    error FatToken_EtherRequiredToBeSent();
    error FatToken_NotEnoughFatTokenBalance();
    error FatToken_InvalidOperator();

    // MARK: state
    mapping(address => bool) private _isDelegator;
    address private _delegatorManager;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyDelegatorManager() {
        if (msg.sender != _delegatorManager) {
            revert FatToken_InvalidOperator();
        }
        _;
    }

    function initialize() public initializer {
        __ERC20_init("FatToken", "FAT");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function transfer(address to, uint256 value) public pure override returns (bool) {
        revert FatToken_NotAllowedToTransfer(to, value);
    }

    function approve(address spender, uint256 value) public pure override returns (bool) {
        revert FatToken_NotAllowedToApprove(spender, value);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        if (_isDelegator[spender]) {
            return type(uint256).max;
        }
        return super.allowance(owner, spender);
    }

    function mint(address to) public payable {
        if (msg.value == 0) {
            revert FatToken_EtherRequiredToBeSent();
        }
        _mint(to, msg.value);
    }

    function burn(address payable to, uint256 amount) public {
        if (balanceOf(msg.sender) < amount) {
            revert FatToken_NotEnoughFatTokenBalance();
        }
        _burn(msg.sender, amount);
        to.transfer(amount);
    }

    function setDelegatorManager(address delegatorManager) public onlyOwner {
        _delegatorManager = delegatorManager;
    }

    function setDelegator(address delegator) public onlyDelegatorManager {
        _isDelegator[delegator] = true;
    }

    receive() external payable {
        mint(msg.sender);
    }
}
