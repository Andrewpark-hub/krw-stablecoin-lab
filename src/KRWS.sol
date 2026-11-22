// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

/// @title KRWS - 원화 스테이블코인 실습 (3단계: KYC)
/// @notice 1 KRWS = 1원. 발행사(owner)만 새로 찍을 수 있고,
///         상환은 보유자가 자기 토큰을 직접 태우면서 신청한다.
///         발행은 감사인이 올린 은행 잔고(준비금)를 넘을 수 없다.
///         KYC 확인된 주소끼리만 받고 보내고 상환할 수 있다.
/// @dev 고친 것: 발행사가 남의 잔고를 마음대로 지우지 못한다 (1단계, test/naive/NaiveKRWS.sol 반례)
///      고친 것: 준비금보다 많이 못 찍고, 준비금은 발행사가 아니라 감사인이 올린다 (2단계, test/naive/NaiveReserveKRWS.sol 반례)
///      고친 것: 발행 때만이 아니라 모든 이동에서 KYC를 확인한다 (3단계, test/naive/NaiveKycKRWS.sol 반례)
///      못 고친 것: 감사인이 거짓 숫자를 올리면 막을 수 없다
///      못 고친 것: KYC가 취소된 주소의 잔고는 보낼 수도 상환할 수도 없이 묶인다
contract KRWS is ERC20, Ownable {
    event Issued(address indexed to, uint256 amount);
    event RedeemRequested(uint256 indexed requestId, address indexed holder, uint256 amount);
    event ReserveReported(uint256 amount, uint256 reportedAt);
    event KycUpdated(address indexed account, bool verified);

    // 상환 신청 번호. 발행사가 은행 송금 내역이랑 맞춰 볼 때 쓴다.
    uint256 public redeemCount;

    // 은행 잔고를 확인해서 올리는 회계법인 같은 역할. 발행사와 다른 주소.
    address public immutable auditor;

    // 감사인이 마지막으로 올린 은행 잔고(원)와 올린 시각
    uint256 public reserve;
    uint256 public reserveUpdatedAt;

    // 보고가 하루 넘게 안 올라오면 발행을 멈춘다
    uint256 public constant REPORT_VALID_FOR = 1 days;

    // 발행사가 신분 확인(KYC)을 끝낸 주소. 은행이 계좌 만들 때 하는 고객 확인을 체인 밖에서 하고 결과만 올린다.
    mapping(address => bool) public isVerified;

    constructor(address issuer, address auditor_) ERC20("KRW Stable", "KRWS") Ownable(issuer) {
        require(auditor_ != issuer, "AUDITOR_IS_ISSUER");
        auditor = auditor_;
    }

    // 원화는 1원 밑으로 안 쪼개지니까 소수점 자리를 0으로 둔다
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // 감사인이 은행 잔고를 확인하고 올린다. 잔고가 줄었으면 줄어든 숫자를 그대로 올린다.
    function reportReserve(uint256 amount) external {
        require(msg.sender == auditor, "ONLY_AUDITOR");
        reserve = amount;
        reserveUpdatedAt = block.timestamp;
        emit ReserveReported(amount, block.timestamp);
    }

    // 발행사가 KYC 결과를 올리거나 취소한다
    function setKyc(address account, bool verified) external onlyOwner {
        isVerified[account] = verified;
        emit KycUpdated(account, verified);
    }

    // 고객이 은행에 원화를 입금하면 발행사가 그만큼 찍어서 보내준다
    function issue(address to, uint256 amount) external onlyOwner {
        require(amount > 0, "ZERO_AMOUNT");
        require(block.timestamp <= reserveUpdatedAt + REPORT_VALID_FOR, "RESERVE_REPORT_OLD");
        // 이미 나간 양까지 더해서 준비금을 넘으면 안 된다
        require(totalSupply() + amount <= reserve, "NOT_ENOUGH_RESERVE");
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

    // 발행(_mint), 전송(transfer, transferFrom), 상환(_burn)이 전부 여기를 지난다.
    // 그래서 여기 한 군데서 보내는 쪽과 받는 쪽을 둘 다 확인한다.
    // 발행이면 from 이 0, 상환이면 to 가 0 이라 그쪽은 건너뛴다.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            require(isVerified[from], "NOT_VERIFIED");
        }
        if (to != address(0)) {
            require(isVerified[to], "NOT_VERIFIED");
        }
        super._update(from, to, value);
    }
}
