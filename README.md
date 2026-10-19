# TORCHINU

A fixed-supply ERC-20 token for an IMD custom token launch on Ethereum.

| Item | Value |
| --- | --- |
| Solidity contract | `TorchInu` (`src/TorchInu.sol`) |
| Token name | `TORCHINU` |
| Token symbol | `TORCHINU` |
| Decimals | 18 |
| Total supply | 1,000,000,000 TORCHINU = `1000000000000000000000000000` minor units |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Constructor arguments | none |
| Owner / admin | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"`, no CBOR metadata |

## What the token does

`TorchInu` inherits OpenZeppelin's audited `ERC20` (v5.4.0, vendored under `lib/`) and adds nothing
but constants and a one-shot mint. The constructor mints the whole supply to the deployer and emits
`Transfer(0x0, deployer, supply)` plus a `SupplyMinted(deployer, supply)` event. After that the
token is plain ERC-20:

- `transfer` and `transferFrom` move exactly the amount requested. No fee, no tax, no burn on transfer.
- There is no `mint`, `burn`, `burnFrom`, `pause`, blacklist, freeze, seize, owner, upgrade path or
  initializer. The supply can never grow, and nobody can move or freeze a holder's balance.
- The contract has no `receive` or `fallback`, so it cannot be sent ether and unknown selectors revert.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` (checked in the test suite).
- Every library the token uses is inherited or internal, so the bytecode has no link placeholders.

## Assumptions

- **The deployer is the launch factory.** On an IMD launch, `ProjectFactory.launchCustom` deploys the
  token, so the factory is `msg.sender` in the constructor and receives all 1,000,000,000 TORCHINU.
  The factory then pays the supply out: 10% to the launch's MerkleDistributor (the swarm's share),
  85% (`poolBps = 8500`) seeds the single-sided Uniswap v4 pool, and the remaining 5% is forwarded
  to the requester's `remainderTo` address `0xd6302976e590b9b947da8774b7f1246164e0ce98`. None of these
  flows is taxed, so each arrives whole.
- **No exemptions are needed.** Because ordinary transfers already move exact amounts, the token does
  not need the factory, PoolManager or distributor addresses and takes no constructor arguments.
- **No owner is needed.** The brief asks for nothing administrative, so the contract has no owner at
  all. This sidesteps the launch's "factory must not own a contract" rule by construction.
- **The supply is final.** 1,000,000,000 × 10^18 minor units, fixed as `TOTAL_SUPPLY`. The manifest's
  `token.totalSupply` must be exactly `1000000000000000000000000000`.
- **The contract name is not the token name.** The launch records the Solidity identifier `TorchInu`
  (8 characters, within the 32-character limit); `name()` and `symbol()` return `TORCHINU`.

## Deployment parameters

These are the launch's values, decided by the launch policy, and are recorded here for reference.
The manifest step writes `launch.json` after this work is accepted; this repository deliberately
does not contain one.

| Parameter | Value |
| --- | --- |
| Chain | Ethereum mainnet (chain id 1) |
| `token.contract` | `TorchInu` |
| `token.name` / `token.symbol` | `TORCHINU` / `TORCHINU` |
| `token.decimals` | `18` |
| `token.constructorArgs` | `[]` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `contracts` | `[]` (no application contracts) |
| `pool.pairedCurrency` | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| `pool.fee` | `12500` (1.25%) |
| `pool.tickSpacing` | `60` |
| `pool.initialPrice` | `79228162514264337593543950336` (provenance only; the deployer derives the real opening price) |
| `economics.poolBps` | `8500` |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD for the whole supply) |
| `economics.remainderTo` | `0xd6302976e590b9b947da8774b7f1246164e0ce98` |

There are no numbers the brief left open: name, symbol, supply and decimals were all given.

### Reproducing the deployment locally

`script/DeployTorchInu.s.sol` is a reviewable script. Its `deploy()` function contains the whole
deployment (one `new TorchInu()`), is covered by a test, and reads no environment. `run()` only
wraps it in a broadcast for whoever chooses to run it outside the IMD launch:

```sh
forge script script/DeployTorchInu.s.sol:DeployTorchInu --rpc-url <RPC> --broadcast --sender <ADDRESS> --account <KEYSTORE>
```

The IMD launch does not use this script. IMD's deployer launches the attested creation code through
the factory. Nobody in this repository holds a key or signs a transaction.

## Operational responsibilities

- **Nothing to configure after launch.** There is no owner and no setter, so there is no
  "After launch" checklist: the token works as soon as it is deployed.
- **The deployer holds the supply at the moment of deployment.** Whoever deploys outside the IMD
  launch is responsible for the entire supply and for distributing it. In the IMD launch that is the
  factory, which pays everything out in the same transaction.
- **Verification.** Source verification on the block explorer (`forge verify-contract` with
  compiler 0.8.26, optimizer 200 runs, `bytecode_hash = none`, `cbor_metadata = false`,
  evm version `cancun`) is the deployer's job after the launch and cannot be done from this task.
- **Lost tokens are lost.** Transfers to the zero address revert, but transfers to any other wrong
  address are irreversible, as with every ERC-20. There is no recovery function by design.
- **No upgrade path.** A bug would require deploying a new token; there is no proxy.

## Security notes

Checked against the `eth-security` reference (ethskills `security` guide):

- Access control: there are no privileged functions, so nothing to restrict.
- Reentrancy: the contract makes no external calls.
- Decimals: 18, fixed, declared in `DECIMALS` and returned by `decimals()`.
- Integer math: none beyond OpenZeppelin's balance accounting (Solidity 0.8 checked arithmetic).
- Input validation: inherited from OpenZeppelin ERC20 (zero-address sender/receiver/spender and
  insufficient balance/allowance all revert with typed ERC-6093 errors).
- Events: `Transfer` and `Approval` on every balance or allowance change, `SupplyMinted` once.
- Proxies, delegatecall, selfdestruct, signatures, oracles: not used.

Tools run: `forge build`, `forge test` (28 tests, including fuzz tests at 256 runs with the
verifier's seed), `forge fmt --check`. Slither and Mythril were not available on this machine and
did not run. Passing tests are not a security audit; an independent adversarial review is still
appropriate before the launch holds anybody's funds.

## Layout

```
foundry.toml                  compiler pins and project settings (solc 0.8.26, bytecode_hash none)
remappings.txt                forge-std/ and @openzeppelin/contracts/ remappings
src/TorchInu.sol              the token
script/DeployTorchInu.s.sol   reviewable deployment script (deploy() is tested directly)
test/TorchInu.t.sol           success, failure, admin-surface, bytecode and fuzz tests
lib/forge-std/                forge-std 1.17.0 (src only), MIT/Apache-2.0, vendored as plain files
lib/openzeppelin-contracts/   OpenZeppelin Contracts 5.4.0, only the ERC20 files used, MIT
```

## Checks

```sh
forge build
forge test
forge fmt --check
```
