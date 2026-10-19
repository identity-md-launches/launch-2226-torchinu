// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title TORCHINU
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 TORCHINU (18 decimals) is minted
/// once, in the constructor, to the deployer (`msg.sender`). There is no owner, no mint, no pause,
/// no blacklist, no fee and no burn hook: after deployment the token is plain ERC-20 and nobody,
/// including the deployer, holds any privilege over it.
/// @dev The contract identifier is `TorchInu`; the token's `name()` and `symbol()` are both
/// "TORCHINU". On an IMD launch the deployer is the ProjectFactory, which receives the supply
/// and pays all of it out (swarm share, pool seed, requester remainder).
contract TorchInu is ERC20 {
    /// @notice The token name, as returned by `name()`.
    string public constant TOKEN_NAME = "TORCHINU";

    /// @notice The token symbol, as returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "TORCHINU";

    /// @notice Decimals, as returned by `decimals()`.
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply, fixed forever: 1,000,000,000 tokens in minor units.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Emitted once, when the constructor mints the whole supply to the deployer.
    /// @param recipient The deployer that received the full supply.
    /// @param amount The supply minted, in minor units.
    event SupplyMinted(address indexed recipient, uint256 amount);

    /// @notice Mints the entire fixed supply to the deployer.
    /// @dev Takes no arguments, calls no other contract and requires no address to have code, so it
    /// deploys on an empty chain and stays within the launch manifest's constructor-argument limit.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }
}
