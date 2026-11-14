// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

/// @title NaiveReserveKRWS - 2단계에서 처음 만든 버전
/// @notice 처음엔 준비금 검사만 넣으면 된다고 생각해서 은행 잔고도 발행사가 올리게 했다.
///         그런데 발행사가 "1조 원 있음" 이라고 올리고 바로 1조 원을 찍으면 검사가 아무 의미 없다.
contract NaiveReserveKRWS is ERC20, Ownable {
    uint256 public reserve;

    constructor(address issuer) ERC20("Naive Reserve KRW Stable", "nrKRWS") Ownable(issuer) {}

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // 문제: 잔고를 올리는 사람과 찍는 사람이 같다
    function reportReserve(uint256 amount) external onlyOwner {
        reserve = amount;
    }

    function issue(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= reserve, "NOT_ENOUGH_RESERVE");
        _mint(to, amount);
    }
}
