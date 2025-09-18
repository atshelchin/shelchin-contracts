// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Delegator} from "../src/Delegator.sol";
import {Counter} from "../src/Counter.sol";

contract DelegatorTest is Test {
    Delegator public delegator;
    Counter public counter;

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    event CallExecuted(address indexed to, uint256 value, bool success);
    event BatchCallExecuted(uint256 callsCount, uint256 successCount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Initialized(address indexed owner);

    receive() external payable {}

    function setUp() public {
        delegator = new Delegator();
        delegator.initialize(owner);
        counter = new Counter();

        vm.deal(owner, 10 ether);
        vm.deal(alice, 10 ether);
    }

    function test_SingleExecute() public {
        bytes memory data = abi.encodeWithSelector(Counter.setNumber.selector, 42);

        (bool success, bytes memory result) = delegator.execute(address(counter), data, 0);

        assertTrue(success);
        assertEq(counter.number(), 42);
    }

    function test_ExecuteWithValue() public {
        address recipient = makeAddr("recipient");
        uint256 initialBalance = recipient.balance;

        (bool success,) = delegator.execute{value: 1 ether}(recipient, "", 1 ether);

        assertTrue(success);
        assertEq(recipient.balance, initialBalance + 1 ether);
    }

    function test_BatchExecute() public {
        Delegator.Call[] memory calls = new Delegator.Call[](3);

        calls[0] = Delegator.Call({
            to: address(counter),
            data: abi.encodeWithSelector(Counter.setNumber.selector, 10),
            value: 0
        });

        calls[1] =
            Delegator.Call({to: address(counter), data: abi.encodeWithSelector(Counter.increment.selector), value: 0});

        calls[2] =
            Delegator.Call({to: address(counter), data: abi.encodeWithSelector(Counter.increment.selector), value: 0});

        delegator.executeBatch(calls);

        assertEq(counter.number(), 12);
    }

    function test_TryExecuteBatch() public {
        Counter counter2 = new Counter();

        Delegator.Call[] memory calls = new Delegator.Call[](4);

        calls[0] = Delegator.Call({
            to: address(counter),
            data: abi.encodeWithSelector(Counter.setNumber.selector, 5),
            value: 0
        });

        calls[1] = Delegator.Call({
            to: address(counter2),
            data: abi.encodeWithSelector(Counter.setNumber.selector, 10),
            value: 0
        });

        calls[2] = Delegator.Call({to: address(0), data: "", value: 0});

        calls[3] =
            Delegator.Call({to: address(counter), data: abi.encodeWithSelector(Counter.increment.selector), value: 0});

        bool[] memory results = delegator.tryExecuteBatch(calls);

        assertTrue(results[0]);
        assertTrue(results[1]);
        assertFalse(results[2]);
        assertTrue(results[3]);

        assertEq(counter.number(), 6);
        assertEq(counter2.number(), 10);
    }

    function test_BatchWithETH() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        Delegator.Call[] memory calls = new Delegator.Call[](2);

        calls[0] = Delegator.Call({to: recipient1, data: "", value: 0.5 ether});

        calls[1] = Delegator.Call({to: recipient2, data: "", value: 0.3 ether});

        delegator.executeBatch{value: 0.8 ether}(calls);

        assertEq(recipient1.balance, 0.5 ether);
        assertEq(recipient2.balance, 0.3 ether);
    }

    function test_OnlyOwnerCanExecute() public {
        vm.prank(alice);
        vm.expectRevert(Delegator.NotOwner.selector);
        delegator.execute(address(counter), "", 0);
    }

    function test_OnlyOwnerCanExecuteBatch() public {
        Delegator.Call[] memory calls = new Delegator.Call[](1);
        calls[0] = Delegator.Call({to: address(counter), data: "", value: 0});

        vm.prank(alice);
        vm.expectRevert(Delegator.NotOwner.selector);
        delegator.executeBatch(calls);
    }

    function test_TransferOwnership() public {
        assertEq(delegator.owner(), owner);

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(owner, alice);

        delegator.transferOwnership(alice);
        assertEq(delegator.owner(), alice);

        vm.expectRevert(Delegator.NotOwner.selector);
        delegator.transferOwnership(bob);

        vm.prank(alice);
        delegator.transferOwnership(bob);
        assertEq(delegator.owner(), bob);
    }

    function test_WithdrawETH() public {
        vm.deal(address(delegator), 2 ether);
        assertEq(address(delegator).balance, 2 ether);

        uint256 ownerBalanceBefore = owner.balance;
        delegator.withdrawETH();

        assertEq(address(delegator).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 2 ether);
    }

    function test_RevertOnFailedCall() public {
        bytes memory data = abi.encodeWithSignature("nonExistentFunction()");

        vm.expectRevert();
        delegator.execute(address(counter), data, 0);
    }

    function test_RevertOnInsufficientETH() public {
        vm.expectRevert(Delegator.InsufficientETH.selector);
        delegator.execute{value: 0.5 ether}(alice, "", 1 ether);
    }

    function test_ReceiveETH() public {
        payable(address(delegator)).transfer(1 ether);
        assertEq(address(delegator).balance, 1 ether);
    }

    function test_Initialize() public {
        Delegator newDelegator = new Delegator();

        vm.expectEmit(true, false, false, true);
        emit Initialized(alice);

        newDelegator.initialize(alice);
        assertEq(newDelegator.owner(), alice);

        vm.expectRevert(Delegator.AlreadyInitialized.selector);
        newDelegator.initialize(bob);
    }

    function test_RevertInvalidNewOwner() public {
        Delegator newDelegator = new Delegator();

        vm.expectRevert(Delegator.InvalidNewOwner.selector);
        newDelegator.initialize(address(0));
    }

    function test_SupportsInterfaces() public {
        assertTrue(delegator.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(delegator.supportsInterface(0x150b7a02)); // ERC721Receiver
        assertTrue(delegator.supportsInterface(0x4e2312e0)); // ERC1155Receiver-single
        assertTrue(delegator.supportsInterface(0xbc197c81)); // ERC1155Receiver-batch
    }

    function testFuzz_Execute(uint256 value) public {
        vm.assume(value < 100);

        bytes memory data = abi.encodeWithSelector(Counter.setNumber.selector, value);

        delegator.execute(address(counter), data, 0);

        assertEq(counter.number(), value);
    }
}
