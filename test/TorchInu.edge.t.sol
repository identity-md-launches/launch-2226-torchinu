// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TorchInu} from "../src/TorchInu.sol";

/// @notice Edge cases the main suite leaves open: the full supply, one wei, zero amounts, allowance
/// overwrites, receivers and spenders at the zero address on every path, and event shapes.
contract TorchInuEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    TorchInu internal token;
    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant HOLDER = address(0x401D);
    address internal constant OTHER = address(0x07E5);
    address internal constant SPENDER = address(0x5BE4);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new TorchInu();
    }

    function _fund(address to, uint256 amount) internal {
        vm.prank(DEPLOYER);
        token.transfer(to, amount);
    }

    // ---------------------------------------------------------------------------------------------
    // Extremes of amount
    // ---------------------------------------------------------------------------------------------

    function test_fullSupplyTransferAndBack() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(HOLDER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(HOLDER), SUPPLY);

        vm.prank(DEPLOYER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, 0, 1));
        token.transfer(HOLDER, 1);

        vm.prank(HOLDER);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_oneWeiMovesExactly() public {
        _fund(HOLDER, 1);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, 1));
        assertEq(token.balanceOf(HOLDER), 0);
        assertEq(token.balanceOf(OTHER), 1);
    }

    function test_revert_transferMaxUint() public {
        vm.prank(DEPLOYER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        token.transfer(HOLDER, type(uint256).max);
    }

    function test_revert_transferFromMaxUintWithInfiniteAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        token.transferFrom(DEPLOYER, OTHER, type(uint256).max);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_zeroAmountTransferEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(HOLDER, OTHER, 0);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, 0));
    }

    function test_zeroAmountTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, OTHER, 0));
        assertEq(token.allowance(HOLDER, SPENDER), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Zero-address paths
    // ---------------------------------------------------------------------------------------------

    function test_revert_zeroAmountTransferToZeroAddress() public {
        vm.prank(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_revert_transferFromToZeroAddress() public {
        _fund(HOLDER, 10 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(HOLDER, address(0), 1 ether);
        // The revert rolls back the allowance spend as well.
        assertEq(token.allowance(HOLDER, SPENDER), 10 ether);
        assertEq(token.balanceOf(HOLDER), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revert_transferFromTheZeroAddress() public {
        // Nobody can hold an allowance from address(0), so the allowance check stops it first.
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(0), OTHER, 1);
    }

    function test_revert_zeroAddressCannotApproveOrSend() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(SPENDER, 1);

        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(OTHER, 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowances
    // ---------------------------------------------------------------------------------------------

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(HOLDER);
        token.approve(SPENDER, 100);
        token.approve(SPENDER, 40);
        assertEq(token.allowance(HOLDER, SPENDER), 40);
        token.approve(SPENDER, 0);
        assertEq(token.allowance(HOLDER, SPENDER), 0);
        vm.stopPrank();
    }

    function test_ownerNeedsAllowanceToTransferFromSelf() public {
        _fund(HOLDER, 5 ether);
        vm.prank(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, HOLDER, 0, 1));
        token.transferFrom(HOLDER, OTHER, 1);
    }

    function test_allowanceIsPerSpenderAndPerOwner() public {
        _fund(HOLDER, 5 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, 5 ether);
        assertEq(token.allowance(SPENDER, HOLDER), 0);
        assertEq(token.allowance(HOLDER, OTHER), 0);

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OTHER, 0, 1));
        token.transferFrom(HOLDER, OTHER, 1);
    }

    function test_allowanceSpentExactlyToZeroThenRefused() public {
        _fund(HOLDER, 5 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, 2 ether);
        vm.startPrank(SPENDER);
        token.transferFrom(HOLDER, OTHER, 1 ether);
        token.transferFrom(HOLDER, OTHER, 1 ether);
        assertEq(token.allowance(HOLDER, SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(HOLDER, OTHER, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(HOLDER), 3 ether);
    }

    function test_transferFromEmitsTransferButNoApproval() public {
        _fund(HOLDER, 5 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, 5 ether);

        vm.recordLogs();
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, OTHER, 2 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(HOLDER))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OTHER))));
        assertEq(abi.decode(logs[0].data, (uint256)), 2 ether);
    }

    function test_approveToSelfIsAllowed() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(HOLDER, HOLDER, 7);
        vm.prank(HOLDER);
        assertTrue(token.approve(HOLDER, 7));
        assertEq(token.allowance(HOLDER, HOLDER), 7);
    }

    // ---------------------------------------------------------------------------------------------
    // Each deployment is independent; the constructor mints exactly once
    // ---------------------------------------------------------------------------------------------

    function test_secondDeploymentDoesNotTouchTheFirst() public {
        vm.prank(OTHER);
        TorchInu second = new TorchInu();
        assertEq(second.balanceOf(OTHER), SUPPLY);
        assertEq(token.balanceOf(OTHER), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_constructorEmitsExactlyTwoEvents() public {
        vm.recordLogs();
        vm.prank(HOLDER);
        new TorchInu();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[1].topics[0], keccak256("SupplyMinted(address,uint256)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(HOLDER))));
        assertEq(abi.decode(logs[1].data, (uint256)), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveStoresAnyValue(address owner, address spender, uint256 amount) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        spender = address(uint160(bound(uint160(spender), 1, type(uint160).max)));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(owner, spender, amount);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromNeverExceedsAllowanceOrBalance(uint256 funded, uint256 allowed, uint256 amount)
        public
    {
        funded = bound(funded, 0, SUPPLY);
        allowed = bound(allowed, 0, type(uint256).max);
        amount = bound(amount, 0, type(uint256).max);
        _fund(HOLDER, funded);
        vm.prank(HOLDER);
        token.approve(SPENDER, allowed);

        vm.prank(SPENDER);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (HOLDER, OTHER, amount)));

        assertEq(ok, amount <= allowed && amount <= funded);
        if (ok) {
            assertEq(token.balanceOf(OTHER), amount);
            assertEq(token.balanceOf(HOLDER), funded - amount);
            assertEq(token.allowance(HOLDER, SPENDER), allowed == type(uint256).max ? allowed : allowed - amount);
        } else {
            assertEq(token.balanceOf(OTHER), 0);
            assertEq(token.balanceOf(HOLDER), funded);
            assertEq(token.allowance(HOLDER, SPENDER), allowed);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
