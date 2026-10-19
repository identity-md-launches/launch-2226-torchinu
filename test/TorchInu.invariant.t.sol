// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TorchInu} from "../src/TorchInu.sol";

/// @notice Drives TorchInu with bounded random calls from a fixed set of actors. Every recipient is
/// an actor, so the actors' balances must always account for the whole supply. Ghost balances and
/// allowances are updated only from the documented ERC-20 semantics (amounts in, amounts out), and
/// every call that must revert is attempted and counted if it does not.
contract TorchInuHandler is Test {
    TorchInu public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    /// @dev Calls that should have reverted but succeeded, or should have succeeded but reverted.
    uint256 public ghostViolations;
    /// @dev Calls that changed anything other than what they should have.
    uint256 public ghostSideEffects;
    uint256 public ghostTransfers;
    uint256 public ghostTransferFroms;
    uint256 public ghostRejected;

    constructor(TorchInu token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        ghostBalance[actors_[0]] = token_.TOTAL_SUPPLY();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok) ghostViolations++;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ghostTransfers++;
        } catch {
            ghostViolations++;
        }
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        excess = bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        try token.transfer(to, held + excess) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientBalance.selector, from, held, held + excess
                        )
                    )
            ) ghostViolations++;
            ghostRejected++;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(address(0), amount) {
            ghostViolations++;
        } catch {
            ghostRejected++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Mix exact edges in with arbitrary values: zero, one and the infinite allowance.
        uint256 pick = amount % 4;
        if (pick == 0) amount = 0;
        else if (pick == 1) amount = type(uint256).max;
        else if (pick == 2) amount = bound(amount, 0, token.TOTAL_SUPPLY());

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) ghostViolations++;
            ghostAllowance[owner][spender] = amount;
        } catch {
            ghostViolations++;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 held = ghostBalance[from];
        amount = bound(amount, 0, allowed < held ? allowed : held);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok) ghostViolations++;
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ghostTransferFroms++;
        } catch {
            ghostViolations++;
        }
    }

    function transferFromBeyondAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        excess = bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        try token.transferFrom(from, to, allowed + excess) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + excess
                        )
                    )
            ) ghostViolations++;
            ghostRejected++;
        }
    }

    function transferFromBeyondBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        excess = bound(excess, 1, token.TOTAL_SUPPLY());
        uint256 amount = held + excess;

        // Grant enough allowance that only the balance can be what stops it.
        vm.prank(from);
        token.approve(spender, amount);
        ghostAllowance[from][spender] = amount;

        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
                    )
            ) ghostViolations++;
            ghostRejected++;
        }
        // A reverted transferFrom must not have consumed the allowance.
        if (token.allowance(from, spender) != amount) ghostSideEffects++;
    }

    /// @notice A stranger (not an actor) tries privileged-looking calls; none may change anything.
    function strangerPokes(uint256 selectorSeed, uint256 victimSeed, uint256 amount) external {
        address victim = _actor(victimSeed);
        address stranger = address(0xBEEF);
        bytes[6] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", stranger, amount),
            abi.encodeWithSignature("burn(uint256)", amount),
            abi.encodeWithSignature("burnFrom(address,uint256)", victim, amount),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", victim, stranger, bound(amount, 1, 1e30)),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", victim)
        ];
        uint256 supplyBefore = token.totalSupply();
        uint256 victimBefore = token.balanceOf(victim);

        vm.prank(stranger);
        (bool ok,) = address(token).call(calls[selectorSeed % calls.length]);
        if (ok) ghostViolations++;
        if (token.totalSupply() != supplyBefore || token.balanceOf(victim) != victimBefore) ghostSideEffects++;
        if (token.balanceOf(stranger) != 0) ghostSideEffects++;
    }
}

contract TorchInuInvariantTest is StdInvariant, Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    TorchInu internal token;
    TorchInuHandler internal handler;
    address[] internal actors;

    function setUp() public {
        actors.push(address(0xFAC7)); // deployer, holds the whole supply at the start
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA401));
        actors.push(address(0xD157));

        vm.prank(actors[0]);
        token = new TorchInu();

        handler = new TorchInuHandler(token, actors);
        targetContract(address(handler));
        excludeSender(address(0));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_actorsHoldTheWholeSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchGhosts() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchGhosts() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everyCallBehavedAsSpecified() public view {
        assertEq(handler.ghostViolations(), 0, "a call that should revert succeeded, or the reverse");
        assertEq(handler.ghostSideEffects(), 0, "a call changed state it must not touch");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_tokenHoldsNoEther() public view {
        assertEq(address(token).balance, 0);
    }
}
