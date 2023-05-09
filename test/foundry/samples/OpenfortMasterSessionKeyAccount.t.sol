// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EntryPoint, UserOperation} from "account-abstraction/core/EntryPoint.sol";
import {TestCounter} from "account-abstraction/test/TestCounter.sol";
import {OpenfortMasterSessionKeyAccount} from "contracts/samples/OpenfortMasterSessionKeyAccount.sol";

contract OpenfortMasterSessionKeyAccountTest is Test {
    using ECDSA for bytes32;

    EntryPoint public entryPoint;
    OpenfortMasterSessionKeyAccount public openfortMasterSessionKeyAccount;
    TestCounter public testCounter;

    // Key pair to simulate Openfort's master key
    address public openfort;
    uint256 public openfortPrivKey;

    // Address to simulate the bundler
    address payable public bundler;

    // Key pair that the user would generate and ask Openfort to register for a
    // limited time as session key
    address public sessionKey;
    uint256 public sessionKeyPrivKey;
    
    /**
     * @notice Initialize the OpenfortMasterSessionKeyAccountTest testing contract.
     * Scenario:
     * - openfort is the deployer (and owner) of the OpenfortMasterSessionKeyAccount
     * - OpenfortMasterSessionKeyAccount is the smart contract wallet 
     * - testCounter is the counter used to test userOps
     */
    function setUp() public {
        entryPoint = new EntryPoint();
        (openfort, openfortPrivKey) = makeAddrAndKey("openfort");
        bundler = payable(makeAddr("bundler"));
        testCounter = new TestCounter();

        // Simulate the next TX (creation of an OpenfortMasterSessionKeyAccount) is sent by openfort
        vm.prank(openfort);
        openfortMasterSessionKeyAccount = new OpenfortMasterSessionKeyAccount(entryPoint);

        entryPoint.depositTo{value: 1000000000000000000}(address(openfortMasterSessionKeyAccount));

        // Generate a new key pair as session key
        (sessionKey, sessionKeyPrivKey) = makeAddrAndKey("sessionKey");

        // Openfort register the new session key
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.registerSessionKey(sessionKey, 0, 2**48 - 1);
    }

    /**
     * Test that the owner (openfort) can withdraw.
     * Useful to verify that the deployer/owner can still directly call it.
     */
    function testwithdrawDepositTo() public {
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.withdrawDepositTo(bundler, 50000);
    }

    /**
     * Test that the default account cannot register a new session key.
     * It should fail!
     */
    function testFailregisterSessionKeyNotOwner() public {
        address sessionKey2;
        uint256 sessionKeyPrivKey2;
        // Generate a new key pair as session key
        (sessionKey2, sessionKeyPrivKey2) = makeAddrAndKey("sessionKey2");

        // Try to register the new session key
        openfortMasterSessionKeyAccount.registerSessionKey(sessionKey2, 0, 2**48 - 1);
    }

    /**
     * Test that Openfort can register a new session key.
     */
    function testregisterSessionKey() public {
        address sessionKey2;
        uint256 sessionKeyPrivKey2;
        // Generate a new key pair as session key
        (sessionKey2, sessionKeyPrivKey2) = makeAddrAndKey("sessionKey2");

        // Openfort register the new session key
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.registerSessionKey(sessionKey2, 0, 2**48 - 1);
    }

    /**
     * Auxiliary function to sign user ops.
     */
    function signUserOp(UserOperation memory op, address addr, uint256 key)
        public
        view
        returns (bytes memory signature)
    {
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash.toEthSignedMessageHash());
        // Check that the address can be retrieved from the signature values (v,r,s)
        require(addr == ECDSA.recover(hash.toEthSignedMessageHash(), v, r, s), "Invalid signature");
        signature = abi.encodePacked(r, s, v);
        // Check that the address can be retrieved from the signature as it will be received by the user (one string value)
        require(addr == ECDSA.recover(hash.toEthSignedMessageHash(), signature), "Invalid signature");
    }

    /**
     * Send a userOp to the deployed OpenfortMasterSessionKeyAccount signed by the
     * registered session key.
     */
    function testOpenfortMasterSessionKeyAccountCounter() public {
        address openfortMasterSessionKeyAccountAddress = address(openfortMasterSessionKeyAccount);
        uint nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should be 0");
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey, sessionKeyPrivKey);
        
        uint256 count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 0, "Counter is not 0");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should still be 0");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should have increased");

        // Perform a second user operation

        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should be 1");
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey, sessionKeyPrivKey);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter is not 1");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should still be 1");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 2, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 2, "Nonce should have increased");
    }

    /**
     * Send a userOp to the deployed OpenfortMasterSessionKeyAccount signed by a
     * revoked session key. It should fail!
     */
    function testFailOpenfortMasterSessionKeyAccountCounter() public {
        address openfortMasterSessionKeyAccountAddress = address(openfortMasterSessionKeyAccount);
        uint nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should be 0");
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey, sessionKeyPrivKey);
        
        uint256 count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 0, "Counter is not 0");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should still be 0");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should have increased");

        // Perform a second user operation. This time lets revoke last session key
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.revokeSessionKey(sessionKey);

        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should be 1");
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey, sessionKeyPrivKey);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter is not 1");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should still be 1");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 2, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 2, "Nonce should have increased");
    }

    /**
     * Send a userOp to the deployed OpenfortMasterSessionKeyAccount signed by a
     * registered session key. Then register a second session key and use it.
     */
    function testOpenfortMasterSessionKeyAccountCounterSecondSessionKey() public {
        address openfortMasterSessionKeyAccountAddress = address(openfortMasterSessionKeyAccount);
        uint nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should be 0");
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey, sessionKeyPrivKey);
        
        uint256 count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 0, "Counter is not 0");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should still be 0");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should have increased");

        // Perform a second user operation using a second session key
        // First, let's revoke last session key (actually not needed)
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.revokeSessionKey(sessionKey);
        
        // Then, let's create a new session key
        address sessionKey2;
        uint256 sessionKeyPrivKey2;
        // Generate a new key pair as session key
        (sessionKey2, sessionKeyPrivKey2) = makeAddrAndKey("sessionKey2");

        // Ask Openfort to register the new session key
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.registerSessionKey(sessionKey2, 0, 2**48 - 1);

        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should be 1");
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey2, sessionKeyPrivKey2);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter is not 1");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should still be 1");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 2, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 2, "Nonce should have increased");
    }

    /**
     * Send a userOp to the deployed OpenfortMasterSessionKeyAccount signed by a
     * registered session key. Then register a second session key, let it expire and use it.
     *  It should fail!
     */
    function testFailOpenfortMasterSessionKeyAccountCounterExpiredSessionKey() public {
        address openfortMasterSessionKeyAccountAddress = address(openfortMasterSessionKeyAccount);
        uint nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should be 0");
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey, sessionKeyPrivKey);
        
        uint256 count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 0, "Counter is not 0");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 0, "Nonce should still be 0");

        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should have increased");

        // Perform a second user operation using a second session key
        // First, let's revoke last session key (actually not needed)
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.revokeSessionKey(sessionKey);
        
        // Then, let's create a new session key
        address sessionKey2;
        uint256 sessionKeyPrivKey2;
        // Generate a new key pair as session key
        (sessionKey2, sessionKeyPrivKey2) = makeAddrAndKey("sessionKey2");

        // Ask Openfort to register the new session key
        // This time, it should be expired already
        vm.warp(100);
        vm.prank(openfort);
        openfortMasterSessionKeyAccount.registerSessionKey(sessionKey2, uint48(block.timestamp), uint48(block.timestamp));
        vm.warp(200);

        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should be 1");
        ops[0] = UserOperation({
            sender: openfortMasterSessionKeyAccountAddress, // Contract address that will receive the UserOp
            nonce: nonce,
            initCode: hex"",
            callData: abi.encodeCall(   // Function that the OpenfortMasterSessionKeyAccount will execute
                openfortMasterSessionKeyAccount.execute, (address(testCounter), 0, abi.encodeCall(TestCounter.count, ()))
                ),
            callGasLimit: 100000,
            verificationGasLimit: 200000,
            preVerificationGas: 200000,
            maxFeePerGas: 100000,
            maxPriorityFeePerGas: 100000,
            paymasterAndData: hex"",
            signature: hex""
        });
        ops[0].signature = signUserOp(ops[0], sessionKey2, sessionKeyPrivKey2);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 1, "Counter is not 1");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 1, "Nonce should still be 1");
        
        entryPoint.handleOps(ops, bundler);

        count = testCounter.counters(openfortMasterSessionKeyAccountAddress);
        require(count == 2, "Counter has not been updated!");
        nonce = entryPoint.getNonce(openfortMasterSessionKeyAccountAddress, 0);
        require(nonce == 2, "Nonce should have increased");
    }
}
