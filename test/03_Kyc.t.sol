// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";
import {KRWS} from "../src/KRWS.sol";
import {NaiveKycKRWS} from "./naive/NaiveKycKRWS.sol";

contract KycTest is Test {
    KRWS krws;
    NaiveKycKRWS naive;

    address issuer = makeAddr("issuer");
    address auditor = makeAddr("auditor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    // 신분 확인을 안 거친 주소
    address mallory = makeAddr("mallory");

    event KycUpdated(address indexed account, bool verified);

    function setUp() public {
        krws = new KRWS(issuer, auditor);
        naive = new NaiveKycKRWS(issuer);

        vm.warp(1_763_000_000);
        vm.prank(auditor);
        krws.reportReserve(100_000);

        // alice, bob 은 KYC 를 마쳤다. mallory 는 안 했다.
        vm.startPrank(issuer);
        krws.setKyc(alice, true);
        krws.setKyc(bob, true);
        naive.setKyc(alice, true);
        vm.stopPrank();
    }

    // --- 처음 만든 버전 ---

    function test_Exploit_UnverifiedGetsTokensByTransfer() public {
        // 발행할 때는 mallory 한테 못 찍는다
        vm.prank(issuer);
        vm.expectRevert(bytes("NOT_VERIFIED"));
        naive.issue(mallory, 10_000);

        // 그런데 alice 한테 찍고 alice 가 보내 주면 그냥 받는다
        vm.prank(issuer);
        naive.issue(alice, 10_000);
        vm.prank(alice);
        naive.transfer(mallory, 10_000);

        assertEq(naive.balanceOf(mallory), 10_000, "unverified mallory holds tokens");
    }

    // --- 고친 버전 ---

    function test_Fix_TransferToUnverifiedReverts() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        vm.prank(alice);
        vm.expectRevert(bytes("NOT_VERIFIED"));
        krws.transfer(mallory, 10_000);

        assertEq(krws.balanceOf(alice), 10_000, "alice kept");
    }

    function test_Fix_IssueToUnverifiedReverts() public {
        vm.prank(issuer);
        vm.expectRevert(bytes("NOT_VERIFIED"));
        krws.issue(mallory, 10_000);
    }

    function test_Fix_RevokedCannotSend() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        // 나중에 alice 신분증이 위조로 밝혀져서 발행사가 확인을 취소한다
        vm.prank(issuer);
        krws.setKyc(alice, false);

        vm.prank(alice);
        vm.expectRevert(bytes("NOT_VERIFIED"));
        krws.transfer(bob, 1_000);
    }

    function test_Fix_OnlyIssuerCanSetKyc() public {
        // mallory 가 자기 주소를 스스로 확인된 걸로 바꾸려고 하면 막힌다
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, mallory));
        krws.setKyc(mallory, true);

        // 감사인도 KYC 는 못 건드린다
        vm.prank(auditor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, auditor));
        krws.setKyc(mallory, true);
    }

    function test_Kyc_SetAndRevoke() public {
        assertFalse(krws.isVerified(mallory), "not yet");

        vm.expectEmit(true, false, false, true);
        emit KycUpdated(mallory, true);
        vm.prank(issuer);
        krws.setKyc(mallory, true);
        assertTrue(krws.isVerified(mallory), "verified");

        vm.expectEmit(true, false, false, true);
        emit KycUpdated(mallory, false);
        vm.prank(issuer);
        krws.setKyc(mallory, false);
        assertFalse(krws.isVerified(mallory), "revoked");
    }

    function test_Transfer_BetweenVerified() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        vm.prank(alice);
        krws.transfer(bob, 4_000);
        assertEq(krws.balanceOf(bob), 4_000, "bob");

        // mallory 도 KYC 를 마치면 받을 수 있다
        vm.prank(issuer);
        krws.setKyc(mallory, true);
        vm.prank(bob);
        krws.transfer(mallory, 1_000);
        assertEq(krws.balanceOf(mallory), 1_000, "mallory after kyc");
    }

    // --- 아직 못 고친 것 ---

    function test_Limit_RevokedTokensStuck() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);
        vm.prank(issuer);
        krws.setKyc(alice, false);

        // 보내지도 못하고 상환 신청도 못 한다
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_VERIFIED"));
        krws.redeem(10_000);

        // 토큰은 alice 지갑에 그대로 있고 발행량에도 계속 잡힌다. 돌려줄 방법이 아직 없다.
        assertEq(krws.balanceOf(alice), 10_000, "stuck in alice");
        assertEq(krws.totalSupply(), 10_000, "still counted");
    }

    function test_Limit_IssuerCanVerifyAnyone() public {
        // 체인은 setKyc(..., true) 만 본다. 발행사가 신분 확인 없이 아무 주소나 true 로 올려도 모른다.
        vm.prank(issuer);
        krws.setKyc(mallory, true);
        vm.prank(issuer);
        krws.issue(mallory, 10_000);

        assertEq(krws.balanceOf(mallory), 10_000, "mallory verified without real check");
    }

    function test_Limit_UnverifiedSpenderCanMove() public {
        vm.prank(issuer);
        krws.issue(alice, 10_000);

        // alice 가 mallory 한테 approve 해 주면, mallory 는 KYC 가 없어도 alice 돈을 bob 한테 옮길 수 있다.
        // 보내는 쪽(alice)과 받는 쪽(bob)만 보고, 버튼을 누른 사람(mallory)은 안 본다.
        vm.prank(alice);
        krws.approve(mallory, 10_000);
        vm.prank(mallory);
        krws.transferFrom(alice, bob, 10_000);

        assertEq(krws.balanceOf(bob), 10_000, "moved by unverified spender");
    }
}
