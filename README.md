# KRW Stablecoin Lab (KRWS)

![Solidity](https://img.shields.io/badge/Solidity-0.8.31-363636?logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-tested-orange)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.1.0-4E5EE4)
![Network](https://img.shields.io/badge/Network-Testnet%20only-lightgrey)

원화 스테이블코인을 발행사 입장에서 처음부터 만들어 보는 실습 레포입니다. **1 KRWS = 1원**으로 정하고, 발행과 상환부터 시작해서 준비금 확인, KYC, 동결, 발행 한도처럼 실제 발행사가 갖춰야 할 기능을 한 단계씩 붙여 나갈 계획입니다. 나중에는 직접 만들고 있는 체인 [KRES](https://github.com/Andrewpark-hub/kres) 위로 옮기는 것까지 해 볼 생각입니다.

> ⚠️ 테스트넷 학습용입니다. 실제 원화와 교환되지 않고, 메인넷에 배포하지 않습니다. 이미 있는 다른 원화 토큰(KRWT 등)과는 관련이 없습니다.

## 왜 만드나

국내에서는 원화 스테이블코인을 허용하는 디지털자산기본법이 논의되고 있다. 지금까지 나온 안들은 금융위원회 인가, 준비자산 100% 보유, 최소 자기자본을 공통으로 담고 있고, 자기자본 기준은 안마다 5억, 10억, 50억 원으로 다르다. 2026년 1월 보도로는 처음엔 은행 중심 컨소시엄부터 발행을 허용하는 방향이다. 2026년 10월 기준으로도 법은 아직 만들어지지 않았다.

법이 정해지면 발행사는 이 조건들을 코드로 지켜야 한다. 그래서 단계마다 "이 조건을 컨트랙트로 어떻게 지키나, 어디까지는 코드로 못 지키나"를 직접 확인해 보려고 한다.

- 민병덕 의원 디지털자산기본법 발의 (자본금 5억 원): [파이낸셜뉴스 2025-06-16](https://www.fnnews.com/news/202506161308049313)
- 자기자본 10억 원 안: [딜사이트](https://dealsite.co.kr/articles/143153)
- 은행 중심 단계적 허용, 자기자본 50억 원 전망: [파이낸셜뉴스 2026-01-07](https://www.fnnews.com/news/202601071047230515)
- 발행 자격이 아직 쟁점: [CEO스코어데일리 2026-10-21](https://ceoscoredaily.com/page/view/2026102116085383431)

## 프로젝트 핵심 요소 (1단계)

1. **발행은 발행사만**
   - 고객이 은행에 원화를 넣으면 발행사가 `issue(to, amount)` 로 같은 금액을 찍어 준다.
   - 발행사 말고 다른 주소가 부르면 `OwnableUnauthorizedAccount` 로 막힌다 (`test_Fix_OnlyIssuerCanIssue`).
   - 0원 발행은 `ZERO_AMOUNT` 로 막는다 (`test_Issue_ZeroAmountReverts`).

2. **상환은 보유자가 직접 태워서 신청**
   - 처음엔 발행사가 `burn(from, amount)` 로 태워 주면 된다고 생각했다 (`test/naive/NaiveKRWS.sol`). 그런데 이러면 발행사가 고객 동의 없이 아무 지갑의 잔고나 지울 수 있었다 (`test_Exploit_IssuerErasesBalance`).
   - 고친 버전은 `redeem(amount)` 하나만 두고, 부른 사람 자기 잔고만 태운다. 발행사가 불러도 발행사 잔고에서 빠지려다 실패한다 (`test_Fix_IssuerCannotBurnOthers`).
   - 태울 때 상환 번호(`redeemCount`)를 붙여 `RedeemRequested` 이벤트를 남긴다. 발행사는 이 번호로 은행 송금 내역과 맞춰 본다 (`test_Redeem_BurnsOwnTokens`).

3. **소수점 없음**
   - 원화는 1원 밑으로 안 쪼개서 `decimals()` 를 0으로 뒀다. USDC는 6이다.
   - 1 KRWS를 보내면 1원이 그대로 간다 (`test_Transfer_WholeWonOnly`).

### 그리고 아직 못 고친 것

- 은행에 원화가 한 푼도 없어도 발행사는 1조 원어치를 찍을 수 있다 (`test_Limit_IssueWithoutReserve`). 2단계에서 준비금 확인으로 막는다.
- `RedeemRequested` 는 신청 기록일 뿐이다. 발행사가 실제로 원화를 보냈는지는 체인에서 알 수 없다.
- 발행사 키 하나가 털리면 끝이다. 6단계에서 멀티시그로 바꾼다.

## 시스템 아키텍처 & 라이프사이클 흐름

```mermaid
sequenceDiagram
    autonumber
    actor A as 고객 (alice)
    participant B as 은행 계좌 (발행사)
    actor I as 발행사 (issuer)
    participant K as KRWS.sol

    Note over A,K: 발행 (test_Redeem_BurnsOwnTokens 앞부분)
    A->>B: 원화 10,000원 입금
    I->>K: issue(alice, 10000)
    K-->>A: 10,000 KRWS

    Note over A,K: 상환 (test_Redeem_BurnsOwnTokens)
    A->>K: redeem(3000)
    K->>K: alice 잔고에서 3,000 태움, redeemCount = 1
    K-->>I: RedeemRequested(1, alice, 3000)
    I->>B: 상환 번호 1번 확인
    B-->>A: 원화 3,000원 송금 (체인 밖)
```

## 기술 스택

| 구분 | 사용 기술 |
| --- | --- |
| 언어 | Solidity 0.8.31 (EVM osaka) |
| 라이브러리 | OpenZeppelin Contracts 5.1.0 (ERC20, Ownable) |
| 테스트 | Foundry (forge 1.8.1), forge-std 1.17.0 |

## 트러블슈팅 및 환경 최적화

> **문제 상황**
> 검사를 하나씩 지워 보면서 테스트가 잡는지 확인했는데, `redeem` 의 `require(amount > 0, "ZERO_AMOUNT")` 를 지워도 테스트 8개가 전부 통과했다.
>
> **원인 분석**
> `issue` 의 0원 검사 테스트만 만들고 `redeem` 쪽은 안 만들었다. OpenZeppelin `_burn` 은 0을 넣어도 되돌리지 않아서, 검사를 지우면 0원짜리 상환 신청이 그냥 쌓인다.
>
> **해결 방안**
> `test_Redeem_ZeroAmountReverts` 를 추가했다. 지금은 `onlyOwner`, `ZERO_AMOUNT` 두 개, `redeemCount++`, `decimals` 다섯 군데를 각각 지우면 실패하는 테스트가 하나씩 있다.

## 실행 가이드 (Quick Start)

사전 조건: [Foundry](https://book.getfoundry.sh/getting-started/installation)

```bash
git clone --recurse-submodules https://github.com/Andrewpark-hub/krw-stablecoin-lab.git
cd krw-stablecoin-lab
forge test -vv
```

## 로드맵

| 단계 | 내용 | 상태 |
| --- | --- | --- |
| 1 | 발행사만 발행, 보유자가 직접 상환 | ✅ 2026-11-07 |
| 2 | 준비금 확인: 은행 잔고(가상 데이터)보다 많이 못 찍게 | |
| 3 | KYC: 확인된 주소끼리만 주고받기 | |
| 4 | 동결: 범죄 연루 주소 동결 ([stablecoin-freeze-zk-lab](https://github.com/Andrewpark-hub/stablecoin-freeze-zk-lab) 연결) | |
| 5 | 하루 발행 한도와 긴급 정지 | |
| 6 | 발행 승인을 여러 명 서명으로 (멀티시그) | |
| 7 | 준비금과 발행량을 보여주는 웹 화면 | |
| 8 | Spring + web3j 백엔드 연결 | |
| 9 | 테스트넷 Uniswap에 KRWS/USDC 풀 만들어 환전 흉내 | |

법안이 바뀌거나 새 기사가 나오면 해당 단계에 반영하고 아래 기록에 남긴다.

## 업데이트 기록

- **2026-11-07** 1단계. `KRWS.sol`, 처음 만든 버전 `NaiveKRWS.sol`, 테스트 9개.

## 파일 구조

```
krw-stablecoin-lab/
├── src/
│   └── KRWS.sol                 # 원화 스테이블코인 (1단계)
├── test/
│   ├── 01_IssueRedeem.t.sol     # 발행, 상환 테스트 9개
│   └── naive/
│       └── NaiveKRWS.sol        # 처음 만든 버전 (발행사가 남의 잔고를 지움)
└── foundry.toml
```

*학습용으로 만든 레포라 실제 서비스에 쓰면 안 됩니다. 법안 내용은 위 기사 기준이고 1차 자료(법안 원문)는 아직 직접 확인하지 않았습니다.*
