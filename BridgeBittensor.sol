// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Bridge is Ownable {
    uint256 public constant MIN_DEPOSIT_AMOUNT = 50000000000000000; // 0.05 TAO

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

    function deposit() external payable {
        require(msg.value > MIN_DEPOSIT_AMOUNT, "INVALID_AMOUNT");

        uint256 feeAmount = msg.value * feePercentage / 100;
        collectedFees += feeAmount;

        emit InitiateBridge(_msgSender(), msg.value - feeAmount, feeAmount, nonce++);
    }

    function release(bytes32 hash, address user, uint256 amount, bytes memory signature) external {
        require(msg.sender == processor, "INVALID_PROCESSOR");
        require(!processedReleases[hash], "ALREADY_PROCESSED");
        require(recoverSigner(hash, signature) == validator, "INVALID_SIGNATURE");

        processedReleases[hash] = true;

        (bool sent,) = user.call{value: amount}("");
        require(sent, "TRANSFER_FAILED");

        emit Release(user, amount);
    }

    function collectFees() external {
        (bool sent,) = owner().call{value: collectedFees}("");
        require(sent, "TRANSFER_FAILED");

        delete collectedFees;
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

        return ecrecover(prefixed(_hash), v, r, s);
    }

    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    receive() external payable {}
    fallback() external payable {}
}
