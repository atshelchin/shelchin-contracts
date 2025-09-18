// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/UniversalDrainer.sol";

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        return true;
    }
}

// Wrapper contract to simulate EIP-7702 behavior
// In EIP-7702, an EOA would have this code, but for testing we use a contract
contract EIP7702Simulator is Test {
    UniversalDrainer public implementation;
    address public eoaAddress;
    uint256 public eoaPrivateKey;

    constructor(address _implementation, uint256 _privateKey) {
        implementation = UniversalDrainer(_implementation);
        eoaPrivateKey = _privateKey;
        eoaAddress = vm.addr(_privateKey);
    }

    // Simulate the EOA calling the implementation with its own signature
    function simulateDrain(address recipient, address[] calldata tokens, uint256 deadline) external {
        // Create the message that the EOA would sign
        bytes32 messageHash = keccak256(abi.encode(block.chainid, address(this), recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Sign with the EOA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        // Call the implementation (in real EIP-7702, this would be delegatecall)
        implementation.drainToAddress(recipient, tokens, deadline, v, r, s);
    }

    // Allow receiving ETH
    receive() external payable {}
}

contract UniversalDrainerTest is Test {
    UniversalDrainer public drainer;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC20 public token3;

    address public recipient = address(0x1234);

    // EOA simulation
    uint256 public eoaPrivateKey = 0xA11CE;
    address public eoaAddress;

    function setUp() public {
        // Deploy contracts
        drainer = new UniversalDrainer();
        token1 = new MockERC20();
        token2 = new MockERC20();
        token3 = new MockERC20();

        // Setup EOA address
        eoaAddress = vm.addr(eoaPrivateKey);

        // In EIP-7702 scenario, tokens would be in the EOA's address
        // For testing, we mint to the drainer contract
        token1.mint(address(drainer), 1000e18);
        token2.mint(address(drainer), 500e18);
        token3.mint(address(drainer), 250e18);

        // Send ETH to drainer
        vm.deal(address(drainer), 10 ether);
    }

    function testEIP7702SignatureValidation() public {
        // Test proper EIP-7702 signature flow
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        uint256 deadline = block.timestamp + 1 hours;

        // Create message for drainer contract address (simulating EOA with code)
        bytes32 messageHash = keccak256(abi.encode(block.chainid, address(drainer), recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Sign with a private key where the derived address matches the contract
        // In real EIP-7702, the EOA would sign and its address would be 'this'
        // For testing, we need to use a different approach since we can't make address(drainer) == signer

        // This will fail because signer address != contract address
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        vm.expectRevert("Unauthorized caller");
        drainer.drainToAddress(recipient, tokens, deadline, v, r, s);
    }

    function testSuccessfulDrainWithMockedEIP7702() public {
        // Deploy a new drainer at a predictable address
        // Calculate the address that would result from the EOA's signature
        address predictedAddress = vm.addr(eoaPrivateKey);

        // Deploy drainer implementation
        UniversalDrainer implementation = new UniversalDrainer();

        // Create tokens and mint to the predicted address
        MockERC20 testToken = new MockERC20();
        testToken.mint(predictedAddress, 1000e18);

        // Setup for the test
        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);
        uint256 deadline = block.timestamp + 1 hours;

        // Create message hash as if signed by the EOA
        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Sign with the EOA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        // Deploy drainer at the EOA address using CREATE2 or vm.etch for testing
        vm.etch(predictedAddress, address(implementation).code);

        // Send ETH to the EOA address
        vm.deal(predictedAddress, 5 ether);

        // Check initial balances
        assertEq(testToken.balanceOf(predictedAddress), 1000e18);
        assertEq(testToken.balanceOf(recipient), 0);
        assertEq(predictedAddress.balance, 5 ether);

        // Call drainToAddress on the EOA address (which now has the drainer code)
        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);

        // Verify tokens were transferred
        assertEq(testToken.balanceOf(predictedAddress), 0);
        assertEq(testToken.balanceOf(recipient), 1000e18);

        // Verify ETH was transferred
        assertEq(predictedAddress.balance, 0);
        assertEq(recipient.balance, 5 ether);
    }

    function testDeadlineValidation() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        // Test with expired deadline
        uint256 expiredDeadline = block.timestamp - 1;

        bytes32 messageHash = keccak256(abi.encode(block.chainid, address(drainer), recipient, tokens, expiredDeadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        // Should revert due to expired deadline (assembly revert)
        vm.expectRevert();
        drainer.drainToAddress(recipient, tokens, expiredDeadline, v, r, s);
    }

    function testZeroRecipientValidation() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = keccak256(abi.encode(block.chainid, address(drainer), address(0), tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        // Should revert due to zero recipient (assembly revert)
        vm.expectRevert();
        drainer.drainToAddress(address(0), tokens, deadline, v, r, s);
    }

    function testEmptyTokenArray() public {
        // Test with empty token array - should only transfer ETH
        address predictedAddress = vm.addr(eoaPrivateKey);
        UniversalDrainer implementation = new UniversalDrainer();

        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 3 ether);

        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        uint256 initialRecipientBalance = recipient.balance;

        // Execute drain with empty token array
        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);

        // Only ETH should be transferred
        assertEq(predictedAddress.balance, 0);
        assertEq(recipient.balance, initialRecipientBalance + 3 ether);
    }

    function testTokenArrayWithZeroAddress() public {
        // Test that zero addresses in token array are skipped
        address predictedAddress = vm.addr(eoaPrivateKey);
        UniversalDrainer implementation = new UniversalDrainer();

        MockERC20 testToken = new MockERC20();
        testToken.mint(predictedAddress, 500e18);

        vm.etch(predictedAddress, address(implementation).code);

        address[] memory tokens = new address[](3);
        tokens[0] = address(testToken);
        tokens[1] = address(0); // Zero address should be skipped
        tokens[2] = address(testToken); // Duplicate, but should work

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);

        // Token should be transferred (only once, as balance is 0 after first transfer)
        assertEq(testToken.balanceOf(predictedAddress), 0);
        assertEq(testToken.balanceOf(recipient), 500e18);
    }

    function test_RevertWhen_TokenTransferFails() public {
        // Test behavior when token transfer fails
        address predictedAddress = vm.addr(eoaPrivateKey);
        UniversalDrainer implementation = new UniversalDrainer();

        vm.etch(predictedAddress, address(implementation).code);

        // Create a token that will fail on transfer
        MockERC20 failingToken = new MockERC20();
        failingToken.mint(predictedAddress, 100e18);

        // Mock the transfer to return false
        vm.mockCall(
            address(failingToken),
            abi.encodeWithSelector(failingToken.transfer.selector, recipient, 100e18),
            abi.encode(false)
        );

        address[] memory tokens = new address[](1);
        tokens[0] = address(failingToken);

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        // Should revert with "Transfer failed"
        vm.expectRevert("Transfer failed");
        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);
    }

    function testMultipleTokensDrain() public {
        // Test draining multiple different tokens
        address predictedAddress = vm.addr(eoaPrivateKey);
        UniversalDrainer implementation = new UniversalDrainer();

        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        MockERC20 tokenC = new MockERC20();

        tokenA.mint(predictedAddress, 100e18);
        tokenB.mint(predictedAddress, 200e18);
        tokenC.mint(predictedAddress, 300e18);

        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 1 ether);

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        uint256 deadline = block.timestamp + 1 hours;

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);

        // Verify all tokens were transferred
        assertEq(tokenA.balanceOf(predictedAddress), 0);
        assertEq(tokenA.balanceOf(recipient), 100e18);

        assertEq(tokenB.balanceOf(predictedAddress), 0);
        assertEq(tokenB.balanceOf(recipient), 200e18);

        assertEq(tokenC.balanceOf(predictedAddress), 0);
        assertEq(tokenC.balanceOf(recipient), 300e18);

        // Verify ETH was transferred
        assertEq(predictedAddress.balance, 0);
        assertEq(recipient.balance, 1 ether);
    }

    function testOnlyETHDrain() public {
        // Test draining only ETH without any tokens to measure gas consumption
        address predictedAddress = vm.addr(eoaPrivateKey);
        UniversalDrainer implementation = new UniversalDrainer();

        // Deploy drainer at EOA address
        vm.etch(predictedAddress, address(implementation).code);

        // Send only ETH to the EOA address (no tokens)
        vm.deal(predictedAddress, 10 ether);

        // Empty token array - only ETH will be drained
        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;

        // Create signature
        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPrivateKey, ethSignedMessageHash);

        // Record initial balances
        uint256 initialRecipientBalance = recipient.balance;
        assertEq(predictedAddress.balance, 10 ether);

        // Measure gas by recording before execution
        uint256 gasBefore = gasleft();

        // Execute drain - only ETH
        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for ETH-only drain:", gasUsed);

        // Verify only ETH was transferred
        assertEq(predictedAddress.balance, 0);
        assertEq(recipient.balance, initialRecipientBalance + 10 ether);
    }

    function testGasComparison() public {
        // Compare gas consumption between ETH-only and ETH+Tokens
        UniversalDrainer implementation = new UniversalDrainer();
        uint256 deadline = block.timestamp + 1 hours;

        // Test 1: ETH only
        uint256 gasUsedETHOnly = _testETHOnlyGas(implementation, deadline);
        console.log("Gas used - ETH only:        ", gasUsedETHOnly);

        // Test 2: ETH + 1 Token
        uint256 gasUsedWithToken = _testOneTokenGas(implementation, deadline);
        console.log("Gas used - ETH + 1 token:   ", gasUsedWithToken);
        console.log("Additional gas for 1 token: ", gasUsedWithToken - gasUsedETHOnly);

        // Test 3: ETH + 3 Tokens
        uint256 gasUsedThreeTokens = _testThreeTokensGas(implementation, deadline);
        console.log("Gas used - ETH + 3 tokens:  ", gasUsedThreeTokens);
        console.log("Additional gas for 3 tokens:", gasUsedThreeTokens - gasUsedETHOnly);
        console.log("Average gas per token:      ", (gasUsedThreeTokens - gasUsedETHOnly) / 3);

        // Test 4: ETH + 10 Tokens
        uint256 gasUsedTenTokens = _testTenTokensGas(implementation, deadline);
        console.log("Gas used - ETH + 10 tokens: ", gasUsedTenTokens);
        console.log("Additional gas for 10 tokens:", gasUsedTenTokens - gasUsedETHOnly);
        console.log("Average gas per token:       ", (gasUsedTenTokens - gasUsedETHOnly) / 10);

        // Test 5: ETH + 20 Tokens
        uint256 gasUsedTwentyTokens = _testManyTokensGas(implementation, deadline, 20);
        console.log("\nGas used - ETH + 20 tokens: ", gasUsedTwentyTokens);
        console.log("Additional gas for 20 tokens:", gasUsedTwentyTokens - gasUsedETHOnly);
        console.log("Average gas per token:       ", (gasUsedTwentyTokens - gasUsedETHOnly) / 20);

        // Test 6: ETH + 50 Tokens
        uint256 gasUsedFiftyTokens = _testManyTokensGas(implementation, deadline, 50);
        console.log("\nGas used - ETH + 50 tokens: ", gasUsedFiftyTokens);
        console.log("Additional gas for 50 tokens:", gasUsedFiftyTokens - gasUsedETHOnly);
        console.log("Average gas per token:       ", (gasUsedFiftyTokens - gasUsedETHOnly) / 50);

        // Summary
        console.log("\n=== Summary ===");
        console.log("Base ETH transfer:    ", gasUsedETHOnly);
        console.log("Per token average:");
        console.log("  1 token:  ", gasUsedWithToken - gasUsedETHOnly);
        console.log("  3 tokens: ", (gasUsedThreeTokens - gasUsedETHOnly) / 3);
        console.log("  10 tokens:", (gasUsedTenTokens - gasUsedETHOnly) / 10);
        console.log("  20 tokens:", (gasUsedTwentyTokens - gasUsedETHOnly) / 20);
        console.log("  50 tokens:", (gasUsedFiftyTokens - gasUsedETHOnly) / 50);
    }

    function _testETHOnlyGas(UniversalDrainer implementation, uint256 deadline) internal returns (uint256) {
        address predictedAddress = vm.addr(eoaPrivateKey);
        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 5 ether);

        address[] memory emptyTokens = new address[](0);

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, emptyTokens, deadline));

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(eoaPrivateKey, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)));

        uint256 gasBefore = gasleft();
        UniversalDrainer(predictedAddress).drainToAddress(recipient, emptyTokens, deadline, v, r, s);
        return gasBefore - gasleft();
    }

    function _testOneTokenGas(UniversalDrainer implementation, uint256 deadline) internal returns (uint256) {
        address predictedAddress = vm.addr(0xB0B);
        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 5 ether);

        MockERC20 testToken = new MockERC20();
        testToken.mint(predictedAddress, 1000e18);

        address[] memory oneToken = new address[](1);
        oneToken[0] = address(testToken);

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, oneToken, deadline));

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(0xB0B, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)));

        uint256 gasBefore = gasleft();
        UniversalDrainer(predictedAddress).drainToAddress(recipient, oneToken, deadline, v, r, s);
        return gasBefore - gasleft();
    }

    function _testThreeTokensGas(UniversalDrainer implementation, uint256 deadline) internal returns (uint256) {
        address predictedAddress = vm.addr(0xC0C);
        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 5 ether);

        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        MockERC20 token3 = new MockERC20();

        token1.mint(predictedAddress, 100e18);
        token2.mint(predictedAddress, 200e18);
        token3.mint(predictedAddress, 300e18);

        address[] memory threeTokens = new address[](3);
        threeTokens[0] = address(token1);
        threeTokens[1] = address(token2);
        threeTokens[2] = address(token3);

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, threeTokens, deadline));

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(0xC0C, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)));

        uint256 gasBefore = gasleft();
        UniversalDrainer(predictedAddress).drainToAddress(recipient, threeTokens, deadline, v, r, s);
        return gasBefore - gasleft();
    }

    function _testTenTokensGas(UniversalDrainer implementation, uint256 deadline) internal returns (uint256) {
        address predictedAddress = vm.addr(0xD0D);
        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 5 ether);

        // Create 10 tokens
        address[] memory tenTokens = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            MockERC20 token = new MockERC20();
            token.mint(predictedAddress, (i + 1) * 100e18);
            tenTokens[i] = address(token);
        }

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tenTokens, deadline));

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(0xD0D, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)));

        uint256 gasBefore = gasleft();
        UniversalDrainer(predictedAddress).drainToAddress(recipient, tenTokens, deadline, v, r, s);
        return gasBefore - gasleft();
    }

    function _testManyTokensGas(UniversalDrainer implementation, uint256 deadline, uint256 tokenCount)
        internal
        returns (uint256)
    {
        uint256 privateKey = 0xE0E + tokenCount;
        address predictedAddress = vm.addr(privateKey);
        vm.etch(predictedAddress, address(implementation).code);
        vm.deal(predictedAddress, 5 ether);

        // Create multiple tokens
        address[] memory tokens = new address[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            MockERC20 token = new MockERC20();
            token.mint(predictedAddress, (i + 1) * 100e18);
            tokens[i] = address(token);
        }

        bytes32 messageHash = keccak256(abi.encode(block.chainid, predictedAddress, recipient, tokens, deadline));

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(privateKey, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)));

        uint256 gasBefore = gasleft();
        UniversalDrainer(predictedAddress).drainToAddress(recipient, tokens, deadline, v, r, s);
        return gasBefore - gasleft();
    }

    function testSignatureReplayProtection() public {
        // Test that different parameters require different signatures
        address[] memory tokens1 = new address[](1);
        tokens1[0] = address(token1);

        address[] memory tokens2 = new address[](1);
        tokens2[0] = address(token2);

        uint256 deadline = block.timestamp + 1 hours;

        // Create signature for first set of parameters
        bytes32 messageHash1 = keccak256(abi.encode(block.chainid, address(drainer), recipient, tokens1, deadline));

        bytes32 ethSignedMessageHash1 = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash1));

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(eoaPrivateKey, ethSignedMessageHash1);

        // Try to use signature from tokens1 with tokens2
        vm.expectRevert("Unauthorized caller");
        drainer.drainToAddress(recipient, tokens2, deadline, v1, r1, s1);

        // Try to use signature with different recipient
        address differentRecipient = address(0x5678);
        vm.expectRevert("Unauthorized caller");
        drainer.drainToAddress(differentRecipient, tokens1, deadline, v1, r1, s1);

        // Try to use signature with different deadline
        uint256 differentDeadline = deadline + 1 hours;
        vm.expectRevert("Unauthorized caller");
        drainer.drainToAddress(recipient, tokens1, differentDeadline, v1, r1, s1);
    }
}
