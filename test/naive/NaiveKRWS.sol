// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

/// @title NaiveKRWS - 처음 만든 버전
/// @notice 처음엔 상환도 발행사가 알아서 태워주면 된다고 생각했다.
///         그런데 burn(from, amount) 를 발행사에게 열어두면
///         고객 동의 없이 아무 지갑의 잔고나 지울 수 있다.
contract NaiveKRWS is ERC20, Ownable {
    constructor(address issuer) ERC20("Naive KRW Stable", "nKRWS") Ownable(issuer) {}

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // 문제: from 이 누구든 발행사가 태울 수 있다
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
