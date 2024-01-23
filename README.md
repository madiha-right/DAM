# DAM

## Summary

```

                                           +------------------+
                                           |    Embankment    |
             +-------+                     |------------------|
      +------+  DAO  +-------+             | - ERC4626 Vault  |
      |      +-------+       |             | - Owned by DAM   |
      |                      |             +------------------+
      |                      |                   |   ^
      |                      |                   |   |                 +------------+
 +----+----+     +-----------+-------------+     |   |                 | Protocol D |
 |  Dapp   |     | ERC20 Compatible Wallet |     |   |                 +------------+
 +----+----+     +-----------+-------------+     |   /                        ^
      |                      |                  /   /                         |
      |                      |                 /   /                          |
      |                      |                /   /                           |
      |                      |               |   /                   +------------------+
      |                      v               v  /          +-------->| Community Stream |
      |     +----------------------------------+           |         +------------------+
      |     |               DAM                |           |                   |
      |     |----------------------------------|           |                   |
      |     | - Owned by DAO                   |           |                   |
      +---->| - Start/End Rounds               |           |                   v
            | - Discharge yield as incentive   +-----------+             +------------+
            | - Upstream Configuration         |           |      +----->| Protocol C |
            +----------------------------------+           |      |      +------------+
                             ^                             |      |
                             |                             v      |
                             |                      +-------------+        +------------+
                             |                      | Auto Stream |------->| Protocol B |
                             |                      +-------------+        +------------+
                         +--------+                        |
                         | Oracle |                        |
                         +--------+                        v
                                                     +------------+
                                                     | Protocol A |
                                                     +------------+
```

`Dam` is an EVM smart contract application designed for growth-oriented programs within a specific ecosystem and yield distribution from funded _yield bearing token_, for example _[mETH](https://meth.mantle.xyz/stake)_ to the projects of the ecosystem. It operates on a round-based system, where each round is configured with specific parameters for yield distribution, aligning with strategic goals such as fostering ecosystem development and project growth.

## Features

1. The yield distribution is organized into rounds, each with a defined period and specific configurations for reinvestment and auto-stream ratios.
2. Allows setting the parameters for upcoming rounds, including the period, reinvestment ratio, and auto-stream ratio.
3. Supports standard and permit-based deposits, adhering to EIP-2612 and EIP-712 standards, catering to various user preferences.
4. Utilizes an oracle for data verification in the round-ending process, ensuring data integrity and proper distribution of yields.
5. Handle errors on scheduled fund withdrawals.

## How it works

### Starting and Operating the DAM

The DAM is operated by the DAO who deposits an initial amount of ybToken and sets the parameters for the first round. These parameters include the duration of the round, the ratio of yield reinvested to next round, and the ratio of yield distribution to projects applied for the automatic stream.

### Round Lifecycle

Each round has a start and end time, during which yield is generated from the deposited _yield bearing tokens_. At the end of a round, the DAO or oracle can call endRound to process the yield distribution based on the provided off-chain calculated data. Next round starts once the round ends, unless the DAM is dicommisioned by the DAO.

### Deposits and Withdrawals

Additional deposits can be made during a round, increasing the principal amount and potential yield.
Withdrawals are scheduled and processed at the end of a round to ensure seamless yield distribution and fund management.

### Yield Distribution

The yield generated during a round is distributed according to the predefined ratios.
A portion of the yield can be reinvested to generate further growth, while the rest is distributed to designated projects or community initiatives.

## Error Handling

1. If a `scheduleWithdrawal()` request fails due to insufficient balance or other constraints, the contract catches and handles these exceptions, ensuring system stability. The `_withdraw()` function, in particular, includes safeguards against failures, including try-catch blocks to manage unexpected errors during the withdrawal process. The failed withdrawal request simply be removed from the withdrawal queue.

2. If `_scheduleWithdrawal()` on `decommisionDam()` request fails, DAO can call `withdrawAll()` to withdraw all funds. The `withdrawAll()` function exists as a safe guard to prevent fund stuck in the Embankment.

## Example Scenarios

Here are some example scenarios to help illustrate how DAM works. All figures, are simple assumptions for the sake of these examples.

**Assumption**:

1. Mantle DAO has _mETH_ in their wallet on Mantle Network. They want to operate their ecosystem fund and at the same time, prevent dilution of the _MNT_ governance token value.
2. APR of _mETH_ is 10%. Let's say alice has 10 _mETH_ and she has held it for a year, the amount of _mETH_ alice has will be 11 _mETH_ after holding for a year.

### 1. Yield Distribution Round

1. Mantle DAO opreates a DAM by depositing 10000 _mETH_ tokens into the Dam contract with 30 days period of round, 5% reinvestment ratio and 50:50 autoStream <> communityStream ratio.
2. The deposited 10000 _mETH_ tokens are transferred to Embankment and no one can withdraw these tokens during the round, 30 days in this case.
3. During the round, these tokens generate yield based on the 10% of APR by itself. The generated yield during this round will be approximately 83 _mETH_. (`10000 * 0.1 / 12`)
4. After 30 days passed, the Mantle DAO ends round with verified data from an oracle.
5. Part of generated yield, 4.15 _mETH_ (`83 * 0.05`) is reinvested to next round according to the reinvesment ratios set for the round.
6. Rest of the generated yield, 78.85 _mETH_ will be distributed to the treasury of each projects according to the project's weight given by the oracle. Each weight is calculated based on the autoStream <> communityStream ratio set for the round.
7. If upstream is flowing, meaning the DAM is not decomissioned by the Mantle DAO, next round will be started immediately with increased fund, 10083 _mETH_. (10000 initial deposited fund + 83 from reinvested amount of last round's yield)

### 2. Withdrawal

After several rounds, Mantle DAO decides to withdraw their funds.

1. The Mantle DAO schedules 100 _mETH_ withdrawal to Mantle DAO Treasury.
2. At the end of the ongoing round, generated yield during the round is distributed to projects first, ensuring projects receive expected incentive.
3. After the distribution, the scheduled 100 _mETH_ is withdrawn from the Embankment and transffered to the Mantle DAO Treasury.
4. Next round starts immediatley with decreased fund.

### 3. Decommissioning

After several rounds, Mantle DAO decides to decomission a DAM.

1. The Mantle DAO decomission the DAM with receiver set to Mantle DAO Treasury.
2. Upstream flowing is set to `false` and withdrawal of all of their fund is scheduled.
3. At the end of the ongoing round, generated yield during the round is distributed to projects first, ensuring projects receive expected incentive.
4. After the distribution, all _mETH_ tokens in Embankment is withdrawn from the Embankment and transffered to the Mantle DAO Treasury.
5. Next round will not be started unless they operate the DAM again.

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Author

- [Madiha](https://twitter.com/madiha_right)
