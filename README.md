# DAM

## Summary

```
            +------+
      +-----+ User +-------+
      |     +------+       |
      |                    |
      |                    |
      |                    |
 +----+-----+  +-----------+-----------+
 |  Dapp    |  |ERC20 Compatible Wallet|
 +----+-----+  +-----------+-----------+
      |                    |                           +----------+
      |                    |                           |Recipients|
      |                    |                           +----------+
      |                    |                                 ^
      |                    v                                 |
      |    +----------------------------------+              |
      |    |            DY-Token              |              |
      |    |----------------------------------|              |
      |    | - ERC20 compatible               |              |
      +--->| - Deposit/Withdraw               |              |
           | - Claim interest                 +--------------+
           | - "Hat"/Beneficiary system       |
           +----------------------------------+
```

`DY-Token`, or Distributable Yield Token, is an _ERC20_ token that is 1:1 redeemable to its underlying _yield-bearing token_. The underlying _yield-bearing token_ generates interest by itself, for example [_stETH_](https://stake.lido.fi/). Owners of the _DY-Tokens_ can use a definition called _hat_ to configure who is the beneficiary of the accumulated interest. _DY-Token_ can be used for community funds, charities, crowdfunding, etc.

## Features

As an example, let's pick [_stETH_](https://stake.lido.fi/) as our underlying token contract. As a result, the _DY-Token_ instantiation is conveniently called _DY-stETH_ in this example.

### 1. Hat Types

A hat defines who can keep the interest generated by the underlying _stETH_ deposited by users.
Every address can be configured with only one hat, but a hat can have multiple beneficiaries.

There are two kinds of hats:

- `Zero Hat` - It is the default hat for all addresses (even before they have a balance).
  Any interest generated by the _stETH_ tokens deposited by the user are entitled to the user himself.

- `Other Hat` - This hat can be set by the user.
  The interest generated by the _Hat_ can be withdrawn to the address of any recipient indicated in the hat definition.

### 2. Hat Definition

A _hat_ is defined by a list of recipients, and their relative proportions for splitting the _stETH_ from the owner.

For example:

```
{
    recipients: [Alice, Bob],
    proportions: [90, 10]
}
```

Above example represents that the _stETH_ tokens will be delegated to address A and address B in the relative proportions of 90:10, effectively Alice receives 90% and Bob receives 10% of the generated interest.

### 3. Deposit

The user first needs to approve the _DY-stETH_ contract to use its _stETH_ tokens,
then the user can mint as much _DY-stETH_ as they deposit _stETH_. One _DY-stETH_ is always
equal to one _stETH_.

As a result, the _stETH_ tokens transferred in order to mint new _DY-stETH_, and the recipients indicated in the user's chosen hat can withdraw any generated interest.

### 4. Withdraw

Users may withdraw the _stETH_ tokens they deposited at any time by transferring back the _DY-stETH_ tokens.

As a result, the invested _stETH_ tokens are recollected from the recipients, and given back to the user who provided the delegated amount.

### 5. Transfer

_DY-token_ contract is _ERC20_ compliant, and one should use _ERC20_ _transfer_ or _approve_ functions to transfer the _DY-stETH_ tokens between addresses.

As a result, the delegated amount of _stETH_ tokens by the `from` address relevant to the transaction is recollected, and delegated to the new recipients according to the hat of the `to` address.

### 6. Claim Interest

Recipients of delegated _stETH_ tokens are entitled to the full amount of interest earned from them.

Anyone can call the _claimInterest_ function, which converts the earned interest to new _DY-stETH_ tokens for the recipients. This mechanism allows contract addresses to also be recipients, despite not having implemented functions to call the _claimInterest_ function externally.

Just like the deposit processes, _DY-stETH_ generated in this process does delegate equal amount of _stETH_ tokens to any recipients. The recipients may choose to delegate them by trigger the hat switching process. Otherwise, generated interest directly goes to the recipients themselves.

### 7. Hat Rules

1. All addresses have the _Zero Hat_ by default.
2. During the transfer process, required amount of _stETH_ token is recollected from recipients of `from` address and delegated to the recipients of `to` address. If the `to` address has the _Zero Hat_, the recipient will be the `to` address itself.

For example: Alice deposits 100 _stETH_ to the _DY-stETH_ contract and sets Bit DAO as only recipient of her generated interest. Bob has never used _DY-stETH_, and thus has a _Zero Hat_. When Alice sends 100 _DY-stETH_ to Bob, Bob starts to get the generated interest of underlying 100 _stETH_. Bob then sends the 100 _DY-stETH_ along to Charlie. But Charlie already has a hat, so the underlying 100 _stETH_ are now delegated to Charlie's chosen recipients.

## How it works

Every address, including a contract address, is associated with only one hat.

Each hat specifies:

1. A set of recipients.
2. The proportions of the interest generated from the _yield-bearing token_ that each recipient will receive.

This is what's happening under the hood.

### Deposit Process

1. The underlying _yield-bearing token_ is transferred to the `DYToken.sol` contract.
2. Hat of `msg.sender` is changed by given recipients and proportions.
   a. This process can be omitted by passing empty `recipients` and `proportions`.
   b. To get the same affect as _Zero Hat_, a recipient and proportion must be user himself and `10000` proportion explicitly.
3. Underlying _yield-bearing token_ is delegated to the hat recipients.
   a. Each hat recipients of `receiver` adds a portion of delegated amount and its share to their `Account.delegatedAmount` and `Account.delegatedShares` accordingly.
4. Equivalent `amount` of _DY-Token_ is minted to the `receiver`.
   a. `Account.amount` adds the deposited amount of underlying tokens that is delegated to each hat recipients.

### Withdrawal Process

1. A portion of underlying _yield-bearing token_ of each hat recipients is recollected back to the `msg.sender` to cover exact same amount of _DY-Token_ that is asked.
   a. The interests are cliamed to the each hat recipients of `msg.sender`.
   b. Each hat recipients of `msg.sender` subtracts a proportion of _DY-Token_ amount that is asked and its share to their `Account.delegatedAmount` and `Account.delegatedShares` accordingly.
2. The amount of _DY-Token_ that is asked by the `msg.sender` is burned from balance of the `msg.sender`.
3. Underlying _yield-bearing token_(the exact same _DY-Token_ amount that is burned) is transferred to the `receiver`.

### Transfer Process

1. The amount of underlying _yield-bearing token_ is recollected from hat recipients of `from` address.
2. The amount of underlying _yield-bearing token_ is delegated to the hat recipients of `to` address.
3. The amount of _DY-Token_ is transferred from `from` address to `to` address.

## Example

When Alice deposits 100 _stETH_, the Alice's 100 _stETH_ is transferred to the _DY-stETH_ contract and an equivalent amount of _DY-stETH_ is minted to the Alice. Alice gets to keep that amount of _DY-stETH_ always, and can withdraw the _stETH_ at any time. The interest generated by the 100 _stETH_ is distributed to the recipients defined by the hat.

That interest is constantly accruing, but a transaction is necessary to realize it as _DY-stETH_. Any recipient can claim its proportional share of interest as _DY-stETH_ whenever they want. Note that the recipient can be the account itself.

So to simplify, here is the flow into and out of _DY-Token_:

1. _stETH_ ---> _DY-stETH_ (`deposit` function)
2. _DY-stETH_ ---> Accrues interest to recipients
3. Recipient realizes interest as _DY-stETH_ (`claimInterest` function)
4. _DY-stETH_ ---> _stETH_ (`withdraw` function)

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Author

- [Madiha](https://twitter.com/madiha_right), inspired by [rToken](https://github.com/rtoken-project/rtoken-monorepo/tree/master).