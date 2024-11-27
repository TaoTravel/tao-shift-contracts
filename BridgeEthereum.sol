// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ITsftStaking } from "./interfaces/ITsftStaking.sol";

contract Bridge is Ownable {
    IERC20 public constant WTAO = IERC20(0x77E06c9eCCf2E797fd462A92B6D7642EF85b0A44);
    uint256 public constant MIN_DEPOSIT_AMOUNT = 50000000; // 0.05 WTAO
    uint256 public constant STAKING_REWARDS = 50; // 50% of fees are distributed as staking rewards

    ITsftStaking public staking;

    address public validator;
    address public processor;
    uint256 public nonce;

    uint256 public collectedFees;
    uint256 public feePercentage;

    mapping(bytes32 => bool) public processedReleases;

    event InitiateBridge(address indexed user, uint256 amount, uint256 fees, uint256 nonce);
    event Release(address indexed user, uint256 amount);

    constructor(address _processor, address _validator) Ownable(_msgSender()) {
        processor = _processor;
        validator = _validator;
        feePercentage = 5;
    }

    function deposit(uint256 amount) external {
        require(amount > MIN_DEPOSIT_AMOUNT, "INVALID_AMOUNT");

        WTAO.transferFrom(_msgSender(), address(this), amount);

        uint256 feeAmount = amount * feePercentage / 100;
        collectedFees += feeAmount;

        emit InitiateBridge(_msgSender(), amount - feeAmount, feeAmount, nonce++);
    }

    function release(bytes32 hash, address user, uint256 amount, bytes memory signature) external {
        require(msg.sender == processor, "INVALID_PROCESSOR");
        require(!processedReleases[hash], "ALREADY_PROCESSED");
        require(recoverSigner(hash, signature) == validator, "INVALID_SIGNATURE");

        processedReleases[hash] = true;
        WTAO.transfer(user, amount);

        emit Release(user, amount);
    }

    function collectFees() external onlyOwner {
        uint256 stakingRewards = collectedFees * STAKING_REWARDS / 100;

        staking.depositWTAO(stakingRewards);
        WTAO.transfer(owner(), collectedFees - stakingRewards);

        delete collectedFees;
    }

    function setStaking(ITsftStaking _staking) external onlyOwner {
        require(address(_staking) != address(0), "INVALID_STAKING_ADDRESS");
        staking = _staking;
        WTAO.approve(address(_staking), type(uint256).max);
    }

    function recoverSigner(bytes32 _hash, bytes memory _signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        require(_signature.length == 65, "INVALID_SIGNATURE_LENGTH");

        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "INVALID_SIGNATURE_V");

        return ecrecover(prefixed(_hash), v, r, s);
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}