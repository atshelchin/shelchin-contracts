// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MinimalProxyFactory} from "../src/MinimalProxyFactory.sol";
import {Implementation} from "../src/Implementation.sol";

contract DeployMinimalProxyScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory
        MinimalProxyFactory factory = new MinimalProxyFactory();

        // Deploy the implementation contract
        Implementation implementation = new Implementation();

        // Deploy a proxy instance using the factory
        bytes32 salt = keccak256("example-proxy-1");
        bytes memory initData =
            abi.encodeWithSelector(Implementation.initialize.selector, msg.sender, "First Proxy", 100);

        address proxy = factory.deployProxyAndCall(address(implementation), salt, initData);

        vm.stopBroadcast();

        // Log the deployed addresses
        logDeployment(address(factory), address(implementation), proxy);
    }

    function logDeployment(address factory, address implementation, address proxy) internal view {
        string memory output = string(
            abi.encodePacked(
                "\n",
                "====================================\n",
                "Minimal Proxy Deployment Complete\n",
                "====================================\n",
                "Factory: ",
                vm.toString(factory),
                "\n",
                "Implementation: ",
                vm.toString(implementation),
                "\n",
                "First Proxy: ",
                vm.toString(proxy),
                "\n",
                "====================================\n"
            )
        );
        console.log(output);
    }
}
