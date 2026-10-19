// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {TorchInu} from "../src/TorchInu.sol";

/// @title DeployTorchInu
/// @notice Reviewable deployment script for TORCHINU. The token takes no constructor arguments, so
/// there is nothing to configure: whoever broadcasts `run()` becomes the holder of the whole supply.
/// @dev On an IMD launch this script is not what deploys the token: IMD's deployer launches the
/// attested bytecode through the ProjectFactory, which then holds and distributes the supply. The
/// script exists so the deployment can be reproduced and reviewed locally. `deploy()` is pure
/// deployment logic that tests call directly; `run()` only wraps it in a broadcast.
contract DeployTorchInu is Script {
    /// @notice Deploys a new TorchInu. The caller of this function receives the whole supply.
    function deploy() public returns (TorchInu token) {
        token = new TorchInu();
    }

    /// @notice Broadcasts the deployment with the configured sender.
    function run() external returns (TorchInu token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
