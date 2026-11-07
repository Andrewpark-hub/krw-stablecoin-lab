// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

/// @title KRWS - 원화 스테이블코인 실습 (1단계: 발행과 상환)
/// @notice 1 KRWS = 1원. 발행사(owner)만 새로 찍을 수 있고,
///         상환은 보유자가 자기 토큰을 직접 태우면서 신청한다.
/// @dev 고친 것: 발행사가 남의 잔고를 마음대로 지우지 못한다 (test/naive/NaiveKRWS.sol 반례)
///      못 고친 것: 발행사가 은행에 원화가 없어도 얼마든지 찍을 수 있다 (2단계 준비금 확인에서)
contract KRWS is ERC20, Ownable {
    event Issued(address indexed to, uint256 amount);
    event RedeemRequested(uint256 indexed requestId, address indexed holder, uint256 amount);

    // 상환 신청 번호. 발행사가 은행 송금 내역이랑 맞춰 볼 때 쓴다.
    uint256 public redeemCount;

    constructor(address issuer) ERC20("KRW Stable", "KRWS") Ownable(issuer) {}

    // 원화는 1원 밑으로 안 쪼개지니까 소수점 자리를 0으로 둔다
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // 고객이 은행에 원화를 입금하면 발행사가 그만큼 찍어서 보내준다
    function issue(address to, uint256 amount) external onlyOwner {
        require(amount > 0, "ZERO_AMOUNT");
        _mint(to, amount);
        emit Issued(to, amount);
    }

    // 보유자가 직접 태우고 상환 신청. 발행사는 이 이벤트를 보고 은행 계좌로 원화를 보낸다.
    function redeem(uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        _burn(msg.sender, amount);
        redeemCount++;
        emit RedeemRequested(redeemCount, msg.sender, amount);
    }
}
