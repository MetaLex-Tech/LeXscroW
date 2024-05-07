```
██╗     ███████╗██╗   ██╗███████╗███████╗██████╗ ███████╗██╗    ██╗
██║     ██╔════╝ ██║ ██╔╝██╔════╝██╔════╝██╔══██╗██╔══██║██║    ██║
██║     █████╗    ╚██╔╝  ███████╗██║     ██████╔╝██║  ██║██║ █╗ ██║
██║     ██╔══╝   ██╔╝██╗ ╚════██║██║     ██╔══██╗██║  ██║██║███╗██║
███████╗███████╗██║   ██╗███████║███████╗██║  ██║███████║╚███╔███╔╝
╚══════╝╚══════╝╚═╝   ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝   
///Immutable, non-custodial, conditional smart contract escrow.
   ╚═══════╝  ╚═╝ ╚═══════╝   ╚════════╝ ╚═══╝ ╚══════╝ ╚════╝
```

# Overview
Immutable, non-custodial, flexibly-conditioned escrow, transfers, and swaps. 

All LeXscrow types have the following features:

* Ownerless unique contract deployment
* Optional conditions for execution, including signatures, time, oracle-fed data, and more, which are immutable from construction
* specify depositing part(ies) or allow any address to deposit (open offer)
* parties may replace their own address, and may be an EOA or a contract
* expiration denominated in seconds / Unix time
* re-usable until expiration

As all parameters aside from parties' addresses are immutable upon a LeXscrow's deployment, configuration of each such parameter is critical

## DoubleTokenLexscrow

Bilateral smart escrow contract for (non-fee-on-transfer, non-rebasing) ERC20 tokens.

 - `buyer` (or, if an open offer, any address) deposits `token1` and `seller` (or if an open offer, any address) deposits `token2` via `depositTokens` or `depositTokensWithPermit`
 - if desired, `buyer` may replace its address by passing the new address to `updateBuyer`, and `seller` may do the same with `updateSeller`
 - `execute` is not permissioned, and thus may be called by any address. If called, the LeXscrow executes and simultaneously releases `totalAmount1` of `token1` to `seller` and `totalAmount2` of `token2` to `buyer` iff:
      
      (1) `buyer` and `seller` have respectively deposited `totalAmount1` + any applicable `fee1` of `token1` and `totalAmount2` + any applicable `fee2`  of `token2`,

      (2) `expirationTime` > block.timestamp, and 

      (3) if there is/are condition(s), such condition(s) is/are satisfied upon the external call in `execute`.

If executed, the LeXscrow is re-usable by parties until the set expiration time.

Otherwise, all deposited amounts of `token1` are returned to `buyer` and all deposited amounts of `token2` are returned to `seller` if the LeXscrow expires.

## TokenLexscrow

Unilateral smart escrow contract for (non-fee-on-transfer, non-rebasing) ERC20 tokens.

- initialized with a `deposit` amount which can be any amount up to the `totalAmount`, and may be refundable or non-refundable to `buyer` upon expiry
- `buyer` (or, if an open offer, any address) deposits via `depositTokens` or `depositTokensWithPermit`
- if desired, `buyer` may replace its address by passing the new address to `updateBuyer`, and `seller` may do the same with `updateSeller`
- `seller` may call `rejectDepositor` to reject a depositing address, which will cause any amount deposited by such address to become withdrawable (via `withdraw`) by the rejected depositor
- `execute` is not permissioned, and thus may be called by any address. If called, the LeXscrow executes and simultaneously releases `totalAmount` to `seller` iff:

    (1) `buyer` has deposited `totalAmount` + any applicable `fee` net of any `pendingWithdraw` amount,

    (2) `expirationTime` > block.timestamp, 

    (3) if there is/are condition(s), such condition(s) is/are satisfied upon the external call in `execute`.

If executed, the LeXscrow is re-usable by parties until the set expiration time. 

Otherwise, amount held in address(this) will be treated according to the code in `checkIfExpired` when called following expiry. If expired, the applicable party must call `withdraw` to receive their tokens.

## EthLexscrow

Unilateral smart escrow contract for native gas tokens, denominated in 1e18 decimals (wei).

- initialized with a `deposit` amount which can be any amount up to the `totalAmount`, and may be refundable or non-refundable to `buyer` upon expiry
- `buyer` (or, if an open offer, any address) deposits by sending amount directly to the LeXscrow contract address and thus invoking the `receive` function. The conditional logic rejects any amount in excess of `totalWithFee`
- if desired, `buyer` may replace its address by passing the new address to `updateBuyer`, and `seller` may do the same with `updateSeller`
- `seller` may call `rejectDepositor` to reject a depositing address, which will cause any amount deposited by such address to become withdrawable (via `withdraw`) by the rejected depositor
- `execute` is not permissioned, and thus may be called by any address. If called, the LeXscrow executes and simultaneously releases `totalAmount` to `seller` iff:
      
    (1) `buyer` has deposited `totalAmount` + any applicable `fee` net of any `pendingWithdraw` amount,

    (2) `expirationTime` > block.timestamp, and 

    (3) if there is/are condition(s), such condition(s) is/are satisfied upon the external call in `execute`.

If executed, the LeXscrow is re-usable by parties until the set expiration time. 

Otherwise, amount held in address(this) will be treated according to the code in `checkIfExpired` when called following expiry. If expired, the applicable party must call `withdraw` to receive their funds.

## Other Contracts

- `DoubleTokenLexscrowFactory`, `TokenLexscrowFactory`, and `EthLexscrowFactory` set any applicable fee amounts, fee receiver address, and enable easy deployment of the corresponding LeXscrow type 

- `LexscrowConditionManager` is an adaptation of the [BORG-CORE `ConditionManager`](https://github.com/MetaLex-Tech/BORG-CORE/blob/main/src/libs/conditions/conditionManager.sol), without auth/access control (and thus also the ability to add or remove conditions post-deployment) in favor of immutability
    
- `Receipt` is an optional informational contract that provides a USD-value "receipt" for certain tokens with initialized and configured data feeds


## Prerequisites

Before you begin, ensure you have the following installed:
- [Node.js](https://nodejs.org/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- solc v0.8.20

## Installation

To set up the project locally, follow these steps:

1. **Clone the repository**
   ```bash
   git clone https://github.com/MetaLex-Tech/LeXscrow
   cd LeXscrow
   ```
   
2. **Install dependencies**
   ```bash
   foundryup # Update Foundry tools
   forge install # Install project dependencies
   ```
3. **Compile Contracts**

    ```base
    forge build --optimize --optimizer-runs 200 --use solc:0.8.20 --via-ir
    ```

