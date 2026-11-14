// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test} from "forge-std/Test.sol";
import {KRWS} from "../src/KRWS.sol";
import {NaiveReserveKRWS} from "./naive/NaiveReserveKRWS.sol";

contract ReserveTest is Test {
    KRWS krws;
    NaiveReserveKRWS naive;

    address issuer = makeAddr("issuer");
    address auditor = makeAddr("auditor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event ReserveReported(uint256 amount, uint256 reportedAt);

    function setUp() public {
        krws = new KRWS(issuer, auditor);
        naive = new NaiveReserveKRWS(issuer);

        // Foundry 는 block.timestamp 가 1 에서 시작한다. 실제 체인처럼 2025-11 쯤 시각으로 옮겨 둔다.
        vm.warp(1_763_000_000);
    }

    // 감사인이 은행 잔고를 올리는 걸 줄여 쓴 것
    function _report(uint256 amount) internal {
        vm.prank(auditor);
        krws.reportReserve(amount);
    }

    // --- 처음 만든 버전 ---

    function test_Exploit_IssuerReportsFakeReserve() public {
        // 은행엔 0원인데 발행사가 직접 1조 원 있다고 올린다
        vm.startPrank(issuer);
        naive.reportReserve(1_000_000_000_000);
        naive.issue(issuer, 1_000_000_000_000);
        vm.stopPrank();

        assertEq(naive.totalSupply(), 1_000_000_000_000, "minted with fake reserve");
    }

    // --- 고친 버전 ---

    function test_Fix_IssueWithoutReserveReverts() public {
        // 1단계에서는 됐던 일. 이제는 준비금 보고가 없으면 1원도 못 찍는다.
        // 보고가 한 번도 없으면 reserveUpdatedAt 이 0 이라 시간 검사에서 먼저 막힌다.
        vm.prank(issuer);
        vm.expectRevert(bytes("RESERVE_REPORT_OLD"));
        krws.issue(issuer, 1_000_000_000_000);
    }

    function test_Fix_OnlyAuditorCanReport() public {
        // 발행사가 직접 숫자를 올리려고 하면 막힌다
        vm.prank(issuer);
        vm.expectRevert(bytes("ONLY_AUDITOR"));
        krws.reportReserve(1_000_000_000_000);

        vm.prank(alice);
        vm.expectRevert(bytes("ONLY_AUDITOR"));
        krws.reportReserve(1);
    }

    function test_Fix_AuditorCannotBeIssuer() public {
        // 처음부터 같은 주소로 만들면 감사인을 따로 둔 의미가 없다
        vm.expectRevert(bytes("AUDITOR_IS_ISSUER"));
        new KRWS(issuer, issuer);
    }

    function test_Report_SavesAmountAndTime() public {
        vm.expectEmit(false, false, false, true);
        emit ReserveReported(50_000, 1_763_000_000);
        _report(50_000);

        assertEq(krws.reserve(), 50_000, "reserve");
        assertEq(krws.reserveUpdatedAt(), 1_763_000_000, "time");
    }

    function test_Issue_UpToReserve() public {
        _report(10_000);

        // 딱 준비금만큼은 된다
        vm.prank(issuer);
        krws.issue(alice, 10_000);
        assertEq(krws.totalSupply(), 10_000, "full reserve used");

        // 1원만 더 찍어도 막힌다
        vm.prank(issuer);
        vm.expectRevert(bytes("NOT_ENOUGH_RESERVE"));
        krws.issue(alice, 1);
    }

    function test_Issue_CountsAlreadyIssued() public {
        _report(10_000);

        vm.prank(issuer);
        krws.issue(alice, 6_000);

        // 이번 5,000 만 보면 준비금 안이지만, 이미 나간 6,000 까지 더하면 11,000 이라 넘는다
        vm.prank(issuer);
        vm.expectRevert(bytes("NOT_ENOUGH_RESERVE"));
        krws.issue(bob, 5_000);
    }

    function test_Fix_OldReportBlocksIssue() public {
        _report(10_000);

        // 하루하고 1초가 지나면 그 보고는 못 믿는다
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(issuer);
        vm.expectRevert(bytes("RESERVE_REPORT_OLD"));
        krws.issue(alice, 1_000);

        // 감사인이 새로 올리면 다시 된다
        _report(10_000);
        vm.prank(issuer);
        krws.issue(alice, 1_000);
        assertEq(krws.balanceOf(alice), 1_000, "issued after new report");
    }

    function test_Issue_ReportValidForExactlyOneDay() public {
        _report(10_000);

        // 정확히 하루까지는 괜찮다
        vm.warp(block.timestamp + 1 days);
        vm.prank(issuer);
        krws.issue(alice, 1_000);
        assertEq(krws.balanceOf(alice), 1_000, "still valid");
    }

    function test_Reserve_DropBelowSupply() public {
        _report(10_000);
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        // 은행 잔고가 4,000 으로 줄었다고 감사인이 올린다
        _report(4_000);

        // 새로 찍는 건 막힌다
        vm.prank(issuer);
        vm.expectRevert(bytes("NOT_ENOUGH_RESERVE"));
        krws.issue(alice, 1);

        // 이미 가진 토큰은 그대로고 주고받을 수도 있다
        vm.prank(alice);
        krws.transfer(bob, 3_000);
        assertEq(krws.balanceOf(alice), 7_000, "alice");
        assertEq(krws.balanceOf(bob), 3_000, "bob");
    }

    // --- 아직 못 고친 것 ---

    function test_Limit_AuditorCanLie() public {
        // 감사인이 은행 잔고를 거짓으로 올리면 코드로는 알 수 없다
        _report(1_000_000_000_000);
        vm.prank(issuer);
        krws.issue(issuer, 1_000_000_000_000);

        assertEq(krws.totalSupply(), 1_000_000_000_000, "minted with lying auditor");
    }

    function test_Limit_ReserveNotUpdatedAfterRedeem() public {
        _report(10_000);
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        // alice 가 5,000 상환하면 은행에서 5,000 이 빠져나가 실제 잔고는 5,000 이다
        vm.prank(alice);
        krws.redeem(5_000);

        // 그런데 감사인이 새로 올리기 전까지 reserve 는 10,000 그대로라 발행사가 5,000 을 또 찍을 수 있다
        vm.prank(issuer);
        krws.issue(bob, 5_000);
        assertEq(krws.totalSupply(), 10_000, "supply 10,000 but bank has 5,000");
    }
}
