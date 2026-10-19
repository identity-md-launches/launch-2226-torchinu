// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TorchInu} from "../src/TorchInu.sol";
import {DeployTorchInu} from "../script/DeployTorchInu.s.sol";

/// @notice Stands in for the launch factory: a contract that deploys the token and so becomes
/// `msg.sender` in its constructor, holds the supply, and forwards it on command.
contract FactoryStub {
    TorchInu public token;

    function deployToken() external returns (TorchInu) {
        token = new TorchInu();
        return token;
    }

    function move(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract TorchInuTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    FactoryStub internal factory;
    TorchInu internal token;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant HOLDER = address(0x401D);
    address internal constant OTHER = address(0x07E5);
    address internal constant SPENDER = address(0x5BE4);
    address internal constant ATTACKER = address(0xBEEF);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed recipient, uint256 amount);

    function setUp() public {
        factory = new FactoryStub();
        token = factory.deployToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "TORCHINU");
        assertEq(token.symbol(), "TORCHINU");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "TORCHINU");
        assertEq(token.TOKEN_SYMBOL(), "TORCHINU");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstantMatchesBrief() public view {
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
    }

    function test_mintsWholeSupplyToDeployerOnce() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsTransferFromZeroAndSupplyMinted() public {
        address deployer = address(0xDE91);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), deployer, EXPECTED_SUPPLY);
        vm.expectEmit(true, false, false, true);
        emit SupplyMinted(deployer, EXPECTED_SUPPLY);
        vm.prank(deployer);
        TorchInu fresh = new TorchInu();
        assertEq(fresh.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_deployScriptMintsToTheCallerOfDeploy() public {
        DeployTorchInu deployer = new DeployTorchInu();
        TorchInu deployed = deployer.deploy();
        // `deploy()` creates the token from inside the script contract, so the script is `msg.sender`.
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(address(deployer)), EXPECTED_SUPPLY);
        assertEq(deployed.name(), "TORCHINU");
        assertEq(deployed.symbol(), "TORCHINU");
    }

    function test_constructorTakesNoArgumentsAndCallsNoContract() public {
        // Deploy on an otherwise empty address space: a constructor that called another contract
        // would revert here, as it would in the launch's empty-chain check.
        vm.prank(address(0xA11CE));
        TorchInu fresh = new TorchInu();
        assertEq(fresh.balanceOf(address(0xA11CE)), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Launch flows: whole amounts leave the factory and arrive whole
    // ---------------------------------------------------------------------------------------------

    function test_swarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (EXPECTED_SUPPLY * 1_000) / 10_000;
        assertTrue(factory.move(DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(address(factory)), EXPECTED_SUPPLY - swarm);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(HOLDER, swarm));
        assertEq(token.balanceOf(HOLDER), swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_factoryCanPayOutTheEntireSupply() public {
        uint256 swarm = (EXPECTED_SUPPLY * 1_000) / 10_000;
        uint256 pool = (EXPECTED_SUPPLY * 8_500) / 10_000;
        uint256 remainder = EXPECTED_SUPPLY - swarm - pool;
        assertTrue(factory.move(DISTRIBUTOR, swarm));
        assertTrue(factory.move(HOLDER, pool));
        assertTrue(factory.move(OTHER, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(DISTRIBUTOR) + token.balanceOf(HOLDER) + token.balanceOf(OTHER), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Ordinary ERC-20 behaviour: successes
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        factory.move(HOLDER, 1_000 ether);
        vm.expectEmit(true, true, false, true);
        emit Transfer(HOLDER, OTHER, 400 ether);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, 400 ether));
        assertEq(token.balanceOf(HOLDER), 600 ether);
        assertEq(token.balanceOf(OTHER), 400 ether);
    }

    function test_transferOfZeroSucceeds() public {
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, 0));
        assertEq(token.balanceOf(OTHER), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        factory.move(HOLDER, 5 ether);
        vm.prank(HOLDER);
        assertTrue(token.transfer(HOLDER, 5 ether));
        assertEq(token.balanceOf(HOLDER), 5 ether);
    }

    function test_approveAndTransferFrom() public {
        factory.move(HOLDER, 1_000 ether);
        vm.expectEmit(true, true, false, true);
        emit Approval(HOLDER, SPENDER, 300 ether);
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, 300 ether));
        assertEq(token.allowance(HOLDER, SPENDER), 300 ether);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, OTHER, 200 ether));
        assertEq(token.balanceOf(HOLDER), 800 ether);
        assertEq(token.balanceOf(OTHER), 200 ether);
        assertEq(token.allowance(HOLDER, SPENDER), 100 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        factory.move(HOLDER, 10 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, OTHER, 10 ether);
        assertEq(token.allowance(HOLDER, SPENDER), type(uint256).max);
    }

    function test_supportsIERC20Interface() public view {
        IERC20 erc20 = IERC20(address(token));
        assertEq(erc20.totalSupply(), EXPECTED_SUPPLY);
        assertEq(erc20.balanceOf(address(factory)), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Ordinary ERC-20 behaviour: failures
    // ---------------------------------------------------------------------------------------------

    function test_revert_transferMoreThanBalance() public {
        factory.move(HOLDER, 1 ether);
        vm.prank(HOLDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 1 ether, 1 ether + 1)
        );
        token.transfer(OTHER, 1 ether + 1);
    }

    function test_revert_transferFromEmptyAccount() public {
        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ATTACKER, 0, 1));
        token.transfer(OTHER, 1);
    }

    function test_revert_transferToZeroAddress() public {
        factory.move(HOLDER, 1 ether);
        vm.prank(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
    }

    function test_revert_transferFromWithoutAllowance() public {
        factory.move(HOLDER, 1 ether);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1 ether));
        token.transferFrom(HOLDER, OTHER, 1 ether);
    }

    function test_revert_transferFromBeyondAllowance() public {
        factory.move(HOLDER, 1 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, 0.5 ether);
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0.5 ether, 1 ether)
        );
        token.transferFrom(HOLDER, OTHER, 1 ether);
    }

    function test_revert_transferFromBeyondBalanceEvenWithAllowance() public {
        factory.move(HOLDER, 1 ether);
        vm.prank(HOLDER);
        token.approve(SPENDER, 2 ether);
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 1 ether, 2 ether)
        );
        token.transferFrom(HOLDER, OTHER, 2 ether);
    }

    function test_revert_approveZeroAddressSpender() public {
        vm.prank(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // No admin surface: nothing mints, nothing freezes, nothing seizes
    // ---------------------------------------------------------------------------------------------

    function test_noCommonAdminCallIncreasesSupply() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ATTACKER, type(uint128).max);
            vm.prank(ATTACKER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(factory));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
            assertEq(token.balanceOf(ATTACKER), 0, signatures[i]);
        }
    }

    function test_noPrivilegedHandMovesOrFreezesAHolder() public {
        factory.move(HOLDER, EXPECTED_SUPPLY / 1_000);
        uint256 held = token.balanceOf(HOLDER);
        string[13] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "burn(uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], HOLDER, true);
            vm.prank(address(factory));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        // The deployer has no allowance, so it cannot pull from the holder either.
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        token.transferFrom(HOLDER, address(factory), 1);

        assertEq(token.balanceOf(HOLDER), held);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, held / 2));
        assertEq(token.balanceOf(OTHER), held / 2);
    }

    function test_unknownSelectorsRevertAndTokenHoldsNoEther() public {
        (bool ok,) = address(token).call{value: 0}("");
        assertFalse(ok, "plain call should revert: no receive/fallback");
        vm.deal(address(this), 1 ether);
        (ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok, "the token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
            assertTrue(op != 0xF2, "runtime code contains CALLCODE");
            assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: conservation and exactness on ordinary transfers
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupplyAndMovesExactly(address from, address to, uint256 funded, uint256 amount)
        public
    {
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != address(factory) && to != address(factory));
        funded = bound(funded, 0, EXPECTED_SUPPLY);
        amount = bound(amount, 0, funded);
        factory.move(from, funded);

        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));

        if (from == to) {
            assertEq(token.balanceOf(from), funded);
        } else {
            assertEq(token.balanceOf(from), funded - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(
            token.balanceOf(address(factory)) + token.balanceOf(from) + (from == to ? 0 : token.balanceOf(to)),
            EXPECTED_SUPPLY
        );
    }

    function testFuzz_transferAboveBalanceReverts(address from, uint256 funded, uint256 excess) public {
        vm.assume(from != address(0) && from != address(factory));
        funded = bound(funded, 0, EXPECTED_SUPPLY - 1);
        excess = bound(excess, 1, EXPECTED_SUPPLY - funded);
        factory.move(from, funded);
        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, funded, funded + excess)
        );
        token.transfer(OTHER, funded + excess);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 funded, uint256 allowed, uint256 amount) public {
        funded = bound(funded, 1, EXPECTED_SUPPLY);
        allowed = bound(allowed, 0, funded);
        amount = bound(amount, 0, funded);
        factory.move(HOLDER, funded);
        vm.prank(HOLDER);
        token.approve(SPENDER, allowed);

        vm.prank(SPENDER);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowed, amount)
            );
            token.transferFrom(HOLDER, OTHER, amount);
            assertEq(token.balanceOf(HOLDER), funded);
        } else {
            assertTrue(token.transferFrom(HOLDER, OTHER, amount));
            assertEq(token.balanceOf(OTHER), amount);
            assertEq(token.balanceOf(HOLDER), funded - amount);
            assertEq(token.allowance(HOLDER, SPENDER), allowed - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }
}
