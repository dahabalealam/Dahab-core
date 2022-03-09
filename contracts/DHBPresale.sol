/***********************************************
        __ _.--..--._ _
     .-' _/   _/\_   \_'-.
    |__ /   _/\__/\_   \__|
       |___/\_\__/  \___|
              \__/
              \__/
               \__/
                \__/
             ____\__/___
       . - '             ' -.
      /                      \
~~~~~~~  ~~~~~ ~~~~~  ~~~ ~~~  ~~~~~
  ~~~   ~~~~~   ~!~~   ~~ ~  ~ ~ ~

***********************************************
DahabAlealam.com
***********************************************/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.2;

import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/utils/Address.sol';
import '@pancakeswap/pancake-swap-lib/contracts/utils/ReentrancyGuard.sol';
import '@pancakeswap/pancake-swap-lib/contracts/GSN/Context.sol';
pragma experimental ABIEncoderV2;

contract DHBPresale is ReentrancyGuard, Context {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using Address for address payable;

    struct lockInfo {
        uint256 amount;
        uint256 releaseDate;
    }

    // The token being sold
    IBEP20 public DHB;

    // address where funds are collected
    address payable public wallet;
    uint256 public startRate;
    uint256 public start;
    uint256 public step;
    uint256 public stepDuration;
    uint256 public lockDuration;

    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public totalsByTokens;
    uint256 public totalsSold;
    uint256 public totalLocked;

    mapping(address => lockInfo[]) private _balances;
    /**
     * event for token purchase logging
     * @param purchaser who paid & got for the tokens
     * @param valueToken address of token for value amount
     * @param value amount paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(address indexed purchaser, address indexed valueToken, uint256 value, uint256 amount);

    /**
     * event for token purchase logging
     * @param purchaser who paid & got for the tokens
     * @param valueToken address of token for value amount
     * @param value amount paid for purchase
     * @param amount amount of tokens purchased
     * @param endDate end date to unlock
     */
    event TokenPurchaseLock(
        address indexed purchaser,
        address indexed valueToken,
        uint256 value,
        uint256 amount,
        uint256 endDate
    );

    event Unlocked(address indexed purchaser, uint256 amount);

    constructor(
        address _dhb,
        address payable _wallet,
        uint256 _start,
        uint256 _startRate,
        uint256 _step,
        uint256 _lockDuration,
        uint256 _stepDuration,
        address[] memory _supportedTokens
    ) public {
        require(address(_dhb) != address(0));
        require(address(_wallet) != address(0));
        require(_start > 0);
        require(_step > 0);
        require(_stepDuration > 0);
        require(_lockDuration > 0);

        DHB = IBEP20(_dhb);
        wallet = _wallet;
        startRate = _startRate;
        start = _start;
        step = _step;
        stepDuration = _stepDuration;
        lockDuration = _lockDuration;

        for (uint256 index = 0; index < _supportedTokens.length; index++) {
            supportedTokens[_supportedTokens[index]] = true;
        }
    }

    function getCurrentRate() public view returns (uint256) {
        uint256 tdiff = block.timestamp.sub(start).div(stepDuration);
        return startRate.add(step.mul(tdiff));
    }

    function availableBalance() public view returns (uint256 balance) {
        balance = DHB.balanceOf(address(this)).sub(totalLocked);
    }

    function _buy(
        uint256 _value,
        address _token,
        uint256 rateMul
    ) internal returns (uint256) {
        require(validPurchase(_value, _token), 'not valid purchase');
        IBEP20 token = IBEP20(_token);

        uint256 dhbdec = uint256(10)**uint256(DHB.decimals());

        uint256 val = _value.div(uint256(10)**uint256(token.decimals())).mul(dhbdec);
        uint256 r = getCurrentRate().mul(rateMul);
        uint256 amount = val.div(r).mul(dhbdec);

        require(availableBalance() >= amount, 'insufficient tokens balance');

        token.safeTransferFrom(_msgSender(), wallet, _value);
        totalsByTokens[_token] = totalsByTokens[_token].add(_value);
        totalsSold = totalsSold.add((amount));
        return amount;
    }

    function buyTokens(uint256 _value, address _token) external nonReentrant {
        uint256 amount = _buy(_value, _token, 2);
        DHB.safeTransfer(_msgSender(), amount);
        emit TokenPurchase(_msgSender(), _token, _value, amount);
    }

    function buyAndLockTokens(uint256 _value, address _token) external nonReentrant {
        uint256 amount = _buy(_value, _token, 1);
        uint256 lockEnd = block.timestamp + lockDuration;
        _balances[_msgSender()].push(lockInfo(amount, lockEnd));
        totalLocked = totalLocked.add(amount);
        emit TokenPurchaseLock(_msgSender(), _token, _value, amount, lockEnd);
    }

    function unlock() public nonReentrant {
        uint256 amount = this.unlockedBalanceOf(_msgSender());
        address account = _msgSender();
        require(amount > 0, 'Can not unlock 0');
        for (uint256 i = 0; i < _balances[account].length; i++) {
            if (block.timestamp > _balances[account][i].releaseDate && _balances[account][i].amount > 0) {
                delete _balances[account][i];
            }
        }
        DHB.safeTransfer(_msgSender(), amount);
        totalLocked = totalLocked.sub(amount);
        emit Unlocked(msg.sender, amount);
    }

    function lockedInfos(address account) external view returns (lockInfo[] memory) {
        return _balances[account];
    }

    // return total balance of locked tokens
    function balanceOf(address account) external view returns (uint256 balance) {
        for (uint256 i = 0; i < _balances[account].length; i++) {
            balance = balance.add(_balances[account][i].amount);
        }
    }

    // return total unlocked amount of tokens
    function unlockedBalanceOf(address account) external view returns (uint256 balance) {
        for (uint256 i = 0; i < _balances[account].length; i++) {
            if (block.timestamp > _balances[account][i].releaseDate && _balances[account][i].amount > 0) {
                balance = balance.add(_balances[account][i].amount);
            }
        }
    }

    // return nearest date for unlock
    function nearestUnlockDate(address account) external view returns (uint256) {
        for (uint256 i = 0; i < _balances[account].length; i++) {
            if (_balances[account][i].amount > 0) {
                return _balances[account][i].releaseDate;
            }
        }
    }

    // return true if the transaction can buy tokens
    function validPurchase(uint256 value, address token) internal view returns (bool) {
        bool notSmallAmount = value > 0;
        return (notSmallAmount && supportedTokens[token] && block.timestamp > start);
    }
}
