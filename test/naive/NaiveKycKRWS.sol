// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

/// @title NaiveKycKRWS - 3단계에서 처음 만든 버전
/// @notice 처음엔 발행할 때만 KYC를 확인하면 된다고 생각했다.
///         그런데 확인된 alice 가 받은 토큰을 확인 안 된 주소로 그냥 보낼 수 있었다.
contract NaiveKycKRWS is ERC20, Ownable {
    mapping(address => bool) public isVerified;

    constructor(address issuer) ERC20("Naive KYC KRW Stable", "nkKRWS") Ownable(issuer) {}

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function setKyc(address account, bool verified) external onlyOwner {
        isVerified[account] = verified;
    }

    // 문제: 발행할 때만 본다. transfer 는 ERC20 기본 그대로라 아무한테나 간다.
    function issue(address to, uint256 amount) external onlyOwner {
        require(isVerified[to], "NOT_VERIFIED");
        _mint(to, amount);
    }
}
