// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MinimalProxyFactory} from "../src/MinimalProxyFactory.sol";
import {Implementation} from "../src/Implementation.sol";

contract MinimalProxyFactoryTest is Test {
    MinimalProxyFactory public factory;
    Implementation public implementation;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    event ProxyDeployed(address indexed implementation, address proxy, bytes32 salt);

    function setUp() public {
        factory = new MinimalProxyFactory();
        implementation = new Implementation();
    }

    function test_DeployProxy() public {
        bytes32 salt = keccak256("test1");

        address expectedProxy = factory.computeProxyAddress(address(implementation), salt);

        vm.expectEmit(true, false, false, true);
        emit ProxyDeployed(address(implementation), expectedProxy, salt);

        address proxy = factory.deployProxy(address(implementation), salt);

        assertEq(proxy, expectedProxy);
        assertTrue(proxy.code.length > 0);
    }

    function test_DeployProxyAndCall() public {
        bytes32 salt = keccak256("test2");

        bytes memory initData = abi.encodeWithSelector(Implementation.initialize.selector, alice, "Proxy1", 100);

        address proxy = factory.deployProxyAndCall(address(implementation), salt, initData);

        Implementation proxyInstance = Implementation(proxy);

        assertEq(proxyInstance.owner(), alice);
        assertEq(proxyInstance.name(), "Proxy1");
        assertEq(proxyInstance.value(), 100);
    }

    function test_MultipleProxies() public {
        bytes32 salt1 = keccak256("proxy1");
        bytes32 salt2 = keccak256("proxy2");

        address proxy1 = factory.deployProxyAndCall(
            address(implementation),
            salt1,
            abi.encodeWithSelector(Implementation.initialize.selector, alice, "Alice's Proxy", 50)
        );

        address proxy2 = factory.deployProxyAndCall(
            address(implementation),
            salt2,
            abi.encodeWithSelector(Implementation.initialize.selector, bob, "Bob's Proxy", 200)
        );

        assertNotEq(proxy1, proxy2);

        Implementation aliceProxy = Implementation(proxy1);
        Implementation bobProxy = Implementation(proxy2);

        assertEq(aliceProxy.owner(), alice);
        assertEq(aliceProxy.name(), "Alice's Proxy");
        assertEq(aliceProxy.value(), 50);

        assertEq(bobProxy.owner(), bob);
        assertEq(bobProxy.name(), "Bob's Proxy");
        assertEq(bobProxy.value(), 200);
    }

    function test_ProxyFunctionality() public {
        bytes32 salt = keccak256("functional");

        address proxy = factory.deployProxyAndCall(
            address(implementation),
            salt,
            abi.encodeWithSelector(Implementation.initialize.selector, alice, "Test Proxy", 10)
        );

        Implementation proxyInstance = Implementation(proxy);

        vm.prank(alice);
        proxyInstance.setValue(42);
        assertEq(proxyInstance.value(), 42);

        vm.prank(alice);
        proxyInstance.increment();
        assertEq(proxyInstance.value(), 43);

        (address owner, string memory name, uint256 value) = proxyInstance.getData();
        assertEq(owner, alice);
        assertEq(name, "Test Proxy");
        assertEq(value, 43);
    }

    function test_RevertDeployWithSameSalt() public {
        bytes32 salt = keccak256("duplicate");

        factory.deployProxy(address(implementation), salt);

        vm.expectRevert();
        factory.deployProxy(address(implementation), salt);
    }

    function test_RevertInvalidImplementation() public {
        bytes32 salt = keccak256("invalid");

        vm.expectRevert("Invalid implementation");
        factory.deployProxy(address(0), salt);
    }

    function test_RevertAlreadyInitialized() public {
        bytes32 salt = keccak256("reinit");

        address proxy = factory.deployProxyAndCall(
            address(implementation),
            salt,
            abi.encodeWithSelector(Implementation.initialize.selector, alice, "Test", 100)
        );

        Implementation proxyInstance = Implementation(proxy);

        vm.expectRevert("Already initialized");
        proxyInstance.initialize(bob, "New Name", 200);
    }

    function testFuzz_DeployWithDifferentSalts(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        address proxy1 = factory.deployProxy(address(implementation), salt1);
        address proxy2 = factory.deployProxy(address(implementation), salt2);

        assertNotEq(proxy1, proxy2);
        assertTrue(proxy1.code.length > 0);
        assertTrue(proxy2.code.length > 0);
    }
}
