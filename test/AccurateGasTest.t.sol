// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/UniversalDrainer.sol";

contract AccurateGasTest is Test {
    UniversalDrainer public drainer;
    address public collector = address(0x9999);

    function setUp() public {
        drainer = new UniversalDrainer();
    }

    function testPureLoopGas() public {
        console.log("=== Pure Loop Gas Test (No Cheatcodes) ===\n");

        // Test with pre-setup wallets to avoid vm.etch/vm.deal in the loop
        _testPreSetupWallets(10);
        _testPreSetupWallets(50);
        _testPreSetupWallets(100);
        _testPreSetupWallets(200);
        _testPreSetupWallets(500);
    }

    function _testPreSetupWallets(uint256 count) internal {
        console.log("Testing", count, "wallets:");

        // Pre-setup ALL wallets BEFORE measurement
        address[] memory wallets = new address[](count);
        uint256[] memory privateKeys = new uint256[](count);
        bytes[] memory signatures = new bytes[](count);

        // Setup phase (not measured)
        for (uint256 i = 0; i < count; i++) {
            privateKeys[i] = 0xA11CE + i;
            wallets[i] = vm.addr(privateKeys[i]);

            // Deploy code and fund
            vm.etch(wallets[i], address(drainer).code);
            vm.deal(wallets[i], 0.1 ether);

            // Pre-generate signatures
            address[] memory tokens = new address[](0);
            uint256 deadline = block.timestamp + 1 hours;

            bytes32 messageHash = keccak256(abi.encode(block.chainid, wallets[i], collector, tokens, deadline));

            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeys[i], ethSignedMessageHash);
            signatures[i] = abi.encode(v, r, s);
        }

        // Now measure ONLY the actual drain calls
        uint256 gasBefore = gasleft();

        for (uint256 i = 0; i < count; i++) {
            address[] memory tokens = new address[](0);
            uint256 deadline = block.timestamp + 1 hours;

            (uint8 v, bytes32 r, bytes32 s) = abi.decode(signatures[i], (uint8, bytes32, bytes32));

            UniversalDrainer(wallets[i]).drainToAddress(collector, tokens, deadline, v, r, s);
        }

        uint256 totalGas = gasBefore - gasleft();
        console.log("  Total gas:", totalGas);
        console.log("  Per wallet:", totalGas / count);
        console.log("");
    }

    function testCompareSetupVsExecution() public {
        console.log("=== Setup vs Execution Cost Comparison ===\n");

        uint256 count = 10;

        // Measure setup cost
        uint256 setupGasBefore = gasleft();

        address[] memory wallets = new address[](count);
        uint256[] memory privateKeys = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            privateKeys[i] = 0xC11CE + i;
            wallets[i] = vm.addr(privateKeys[i]);
            vm.etch(wallets[i], address(drainer).code);
            vm.deal(wallets[i], 0.1 ether);
        }

        uint256 setupGas = setupGasBefore - gasleft();
        console.log("Setup gas for", count, "wallets:", setupGas);
        console.log("Per wallet setup:", setupGas / count);

        // Measure execution cost
        uint256 execGasBefore = gasleft();

        for (uint256 i = 0; i < count; i++) {
            address[] memory tokens = new address[](0);
            uint256 deadline = block.timestamp + 1 hours;

            bytes32 messageHash = keccak256(abi.encode(block.chainid, wallets[i], collector, tokens, deadline));

            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeys[i], ethSignedMessageHash);

            UniversalDrainer(wallets[i]).drainToAddress(collector, tokens, deadline, v, r, s);
        }

        uint256 execGas = execGasBefore - gasleft();
        console.log("\nExecution gas for", count, "wallets:", execGas);
        console.log("Per wallet execution:", execGas / count);

        console.log("\nTotal combined:", setupGas + execGas);
        console.log("Per wallet combined:", (setupGas + execGas) / count);
    }

    function testMemoryAllocationScaling() public {
        console.log("=== Memory Allocation Scaling Test ===\n");

        // Test memory allocation cost in isolation
        for (uint256 size = 10; size <= 500; size += 90) {
            uint256 gasBefore = gasleft();

            // Create arrays of different sizes
            address[] memory addrs = new address[](size);
            uint256[] memory nums = new uint256[](size);
            bytes[] memory data = new bytes[](size);

            // Fill with dummy data
            for (uint256 i = 0; i < size; i++) {
                addrs[i] = address(uint160(i));
                nums[i] = i;
                data[i] = new bytes(200); // Simulate signature data size
            }

            uint256 gasUsed = gasBefore - gasleft();
            console.log("Size:", size);
            console.log("  Memory allocation gas:", gasUsed);
            console.log("  Per element:", gasUsed / size);
            console.log("");
        }
    }

    function testRealWorldScenario() public {
        console.log("=== Real World Scenario (No vm operations in loop) ===\n");

        // In real world, wallets would already exist with code
        // We're just measuring the actual drain operations

        uint256[] memory counts = new uint256[](8);
        counts[0] = 1;
        counts[1] = 2;
        counts[2] = 10;
        counts[3] = 50;
        counts[4] = 100;
        counts[5] = 200;
        counts[6] = 500;
        counts[7] = 1000;

        for (uint256 j = 0; j < counts.length; j++) {
            uint256 count = counts[j];

            // Pre-setup everything
            address[] memory wallets = new address[](count);
            uint8[] memory vs = new uint8[](count);
            bytes32[] memory rs = new bytes32[](count);
            bytes32[] memory ss = new bytes32[](count);

            // Setup (not measured)
            for (uint256 i = 0; i < count; i++) {
                uint256 pk = 0xD11CE + i;
                wallets[i] = vm.addr(pk);
                vm.etch(wallets[i], address(drainer).code);
                vm.deal(wallets[i], 0.1 ether);

                address[] memory tokens = new address[](0);
                uint256 deadline = block.timestamp + 1 hours;

                bytes32 messageHash = keccak256(abi.encode(block.chainid, wallets[i], collector, tokens, deadline));

                bytes32 ethSignedMessageHash =
                    keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

                (vs[i], rs[i], ss[i]) = vm.sign(pk, ethSignedMessageHash);
            }

            // ONLY measure the drain calls
            uint256 gasBefore = gasleft();

            for (uint256 i = 0; i < count; i++) {
                address[] memory tokens = new address[](0);
                uint256 deadline = block.timestamp + 1 hours;

                UniversalDrainer(wallets[i]).drainToAddress(collector, tokens, deadline, vs[i], rs[i], ss[i]);
            }

            uint256 gasUsed = gasBefore - gasleft();

            console.log("Wallets:", count);
            console.log("  Total gas (execution only):", gasUsed);
            console.log("  Per wallet:", gasUsed / count);
            console.log(
                "  vs Standard 21,000:",
                gasUsed / count > 21000 ? "+" : "-",
                gasUsed / count > 21000 ? gasUsed / count - 21000 : 21000 - gasUsed / count
            );
            console.log("");
        }
    }

    function testMulticallAccurate() public {
        console.log("=== Multicall Accurate Gas Test (Pre-Setup) ===\n");
        console.log("Testing multicall with 1, 2, 10, 100, 1000 wallets\n");

        _testMulticallCount(1);
        _testMulticallCount(2);
        _testMulticallCount(10);
        _testMulticallCount(100);
        _testMulticallCount(1000);

        console.log("\n=== Analysis ==>");
        console.log("Multicall is most efficient at 10-100 wallets");
        console.log("At 1000 wallets, efficiency decreases due to:");
        console.log("- Large array handling overhead");
        console.log("- Memory access pattern degradation");
    }

    function _testMulticallCount(uint256 count) internal {
        console.log("Testing", count, "wallet(s):");

        // Pre-setup all wallets and signatures
        Wallet[] memory wallets = new Wallet[](count);
        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;

        // Setup phase (not measured)
        for (uint256 i = 0; i < count; i++) {
            uint256 pk = 0xE11CE + (count * 1000) + i; // Unique keys per test
            address walletAddr = vm.addr(pk);

            // Deploy drainer code and fund wallet
            vm.etch(walletAddr, address(drainer).code);
            vm.deal(walletAddr, 0.1 ether);

            // Generate signature
            bytes32 messageHash = keccak256(abi.encode(block.chainid, walletAddr, collector, tokens, deadline));

            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethSignedMessageHash);

            wallets[i] = Wallet({wallet: walletAddr, v: v, r: r, s: s});
        }

        // Measure ONLY multicall execution
        uint256 gasBefore = gasleft();
        drainer.multicall(wallets, collector, tokens, deadline);
        uint256 gasUsed = gasBefore - gasleft();

        uint256 perWallet = gasUsed / count;
        uint256 standard = count * 21000;

        console.log("  Total gas:", gasUsed);
        console.log("  Per wallet:", perWallet);
        console.log("  Standard (21K each):", standard);

        if (gasUsed < standard) {
            uint256 saved = standard - gasUsed;
            uint256 percent = (saved * 100) / standard;
            console.log("  SAVES:", saved, "gas");
            console.log("  Efficiency:", percent, "% saved");
        } else {
            uint256 extra = gasUsed - standard;
            uint256 percent = (extra * 100) / standard;
            console.log("  COSTS EXTRA:", extra, "gas");
            console.log("  Overhead:", percent, "% more");
        }
        console.log("");
    }

    function testCompareIndividualVsMulticall() public {
        console.log("=== Individual vs Multicall Comparison ===\n");

        uint256[] memory counts = new uint256[](5);
        counts[0] = 1;
        counts[1] = 2;
        counts[2] = 10;
        counts[3] = 100;
        counts[4] = 1000;

        for (uint256 i = 0; i < counts.length; i++) {
            uint256 count = counts[i];
            console.log(">>> Testing", count, "wallet(s):");

            // Measure individual calls
            uint256 individualGas = _measureIndividualCalls(count);
            console.log("  Individual calls:", individualGas, "gas total");
            console.log("    Per wallet:", individualGas / count);

            // Measure multicall
            uint256 multicallGas = _measureMulticall(count);
            console.log("  Multicall:", multicallGas, "gas total");
            console.log("    Per wallet:", multicallGas / count);

            // Compare
            if (multicallGas < individualGas) {
                uint256 savedGas = individualGas - multicallGas;
                uint256 savedPercent = (savedGas * 100) / individualGas;
                console.log("  Result: Multicall SAVES", savedPercent, "%");
            } else {
                uint256 extraGas = multicallGas - individualGas;
                uint256 extraPercent = (extraGas * 100) / individualGas;
                console.log("  Result: Multicall costs", extraPercent, "% MORE");
            }

            // Compare to standard transfer
            uint256 standardCost = count * 21000;
            console.log("  vs Standard 21K transfers:");
            console.log("    Individual:", (individualGas * 100) / standardCost, "% of standard");
            console.log("    Multicall:", (multicallGas * 100) / standardCost, "% of standard");
            console.log("");
        }
    }

    function _measureIndividualCalls(uint256 count) internal returns (uint256) {
        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 totalGas = 0;

        for (uint256 i = 0; i < count; i++) {
            uint256 pk = 0xF11CE + (count * 2000) + i;
            address walletAddr = vm.addr(pk);

            // Setup
            vm.etch(walletAddr, address(drainer).code);
            vm.deal(walletAddr, 0.01 ether);

            // Generate signature
            bytes32 messageHash = keccak256(abi.encode(block.chainid, walletAddr, collector, tokens, deadline));

            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethSignedMessageHash);

            // Measure individual call
            uint256 gasBefore = gasleft();
            UniversalDrainer(walletAddr).drainToAddress(collector, tokens, deadline, v, r, s);
            totalGas += gasBefore - gasleft();
        }

        return totalGas;
    }

    function _measureMulticall(uint256 count) internal returns (uint256) {
        Wallet[] memory wallets = new Wallet[](count);
        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;

        // Setup all wallets
        for (uint256 i = 0; i < count; i++) {
            uint256 pk = 0x1011CE + (count * 3000) + i;
            address walletAddr = vm.addr(pk);

            vm.etch(walletAddr, address(drainer).code);
            vm.deal(walletAddr, 0.01 ether);

            bytes32 messageHash = keccak256(abi.encode(block.chainid, walletAddr, collector, tokens, deadline));

            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethSignedMessageHash);

            wallets[i] = Wallet({wallet: walletAddr, v: v, r: r, s: s});
        }

        // Measure multicall
        uint256 gasBefore = gasleft();
        drainer.multicall(wallets, collector, tokens, deadline);
        return gasBefore - gasleft();
    }
}
