// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts@5.1.0/interfaces/draft-IERC6093.sol";
import {KRWS} from "../src/KRWS.sol";
import {NaiveKRWS} from "./naive/NaiveKRWS.sol";

contract IssueRedeemTest is Test {
    KRWS krws;
    NaiveKRWS naive;

    address issuer = makeAddr("issuer");
    address auditor = makeAddr("auditor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event RedeemRequested(uint256 indexed requestId, address indexed holder, uint256 amount);

    function setUp() public {
        krws = new KRWS(issuer, auditor);
        naive = new NaiveKRWS(issuer);

        // 2단계부터는 준비금이 있어야 발행된다. 1단계 테스트는 넉넉하게 10만 원으로 시작한다.
        vm.prank(auditor);
        krws.reportReserve(100_000);
    }

    // --- 처음 만든 버전 ---

    function test_Exploit_IssuerErasesBalance() public {
        vm.prank(issuer);
        naive.mint(alice, 10_000);

        // alice 는 아무것도 안 했는데 발행사가 잔고를 지운다
        vm.prank(issuer);
        naive.burn(alice, 10_000);

        assertEq(naive.balanceOf(alice), 0, "alice balance erased");
    }

    // --- 고친 버전 ---

    function test_Fix_IssuerCannotBurnOthers() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        // KRWS 에는 burn(address,uint256) 이 없어서 호출 자체가 실패한다
        vm.prank(issuer);
        (bool ok,) = address(krws).call(abi.encodeWithSignature("burn(address,uint256)", alice, 10_000));
        assertFalse(ok, "burn should not exist");

        // 발행사가 redeem 을 불러도 발행사 자기 잔고만 태우려고 해서 실패한다
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, issuer, 0, 10_000));
        krws.redeem(10_000);

        assertEq(krws.balanceOf(alice), 10_000, "alice balance kept");
    }

    function test_Fix_OnlyIssuerCanIssue() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        krws.issue(alice, 10_000);
    }

    function test_Issue_ZeroAmountReverts() public {
        vm.prank(issuer);
        vm.expectRevert(bytes("ZERO_AMOUNT"));
        krws.issue(alice, 0);
    }

    function test_Redeem_BurnsOwnTokens() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        vm.expectEmit(true, true, false, true);
        emit RedeemRequested(1, alice, 3_000);
        vm.prank(alice);
        krws.redeem(3_000);

        assertEq(krws.balanceOf(alice), 7_000, "alice left");
        assertEq(krws.totalSupply(), 7_000, "supply down");
        assertEq(krws.redeemCount(), 1, "request id");
    }

    function test_Redeem_CannotExceedBalance() public {
        vm.prank(issuer);
        krws.issue(alice, 1_000);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1_000, 1_001));
        krws.redeem(1_001);
    }

    function test_Redeem_ZeroAmountReverts() public {
        // 0원 상환 신청이 쌓이면 발행사가 맞춰 볼 내역만 늘어난다
        vm.prank(alice);
        vm.expectRevert(bytes("ZERO_AMOUNT"));
        krws.redeem(0);
    }

    function test_Transfer_WholeWonOnly() public {
        assertEq(krws.decimals(), 0, "no decimals");

        vm.prank(issuer);
        krws.issue(alice, 1);

        // 1원은 1 단위 그대로. 0.5원 같은 건 표현할 수 없다.
        vm.prank(alice);
        krws.transfer(bob, 1);
        assertEq(krws.balanceOf(bob), 1, "bob got 1 won");
    }

    // 1단계의 test_Limit_IssueWithoutReserve 는 2단계에서 고쳤다.
    // test/02_Reserve.t.sol 의 test_Fix_IssueWithoutReserveReverts 로 옮겼다.
}
