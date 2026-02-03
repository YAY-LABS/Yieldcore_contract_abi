// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/core/PoolManager.sol";
import "../src/vault/RWAVault.sol";

contract TestDeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address poolManager = 0xC0E1759038f01fB0E097DB5377b0b5BA8742A41D;
        address vault = 0x947857d81e2B3a18E9219aFbBF27118B679b37ef;
        address recipient = 0x36383F9ca913587Ee8452330f102d7020e29f12C;
        uint256 amount = 10000 * 1e6; // 10,000 USDC

        vm.startBroadcast(deployerPrivateKey);

        PoolManager(poolManager).announceDeployCapital(vault, amount, recipient);

        vm.stopBroadcast();
    }
}
