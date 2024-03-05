// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Arena {
  uint8 private feePercent;
  uint256 private betMin;
  uint8 private playersMax;
  uint8 private playersCurrent;
  mapping(address => Player) private playersList;
  mapping(uint256 => address) private playersNavList; // List used to navigate around dictionary.

  uint256 private lockedBalance;
  uint256 private winnerTicket;
  IERC20 private usdtToken; // USDT token address
  uint256 private seed;
  uint256 private rounds = 0;
  uint256 private totalPrize = 0;
  uint256 private maxWin = 0;

  struct Player {
    address playerAddress;
    uint256 bet;
    uint256 ticketStart;
    uint256 ticketEnd;
  }

  struct Winner {
    address playerAddress;
    uint256 ticket;
  }
  address public owner;


  event OwnerCashout(uint256 value);
  event SetPlayersMax(uint8 newPlayersMax);
  event SetBetMin(uint256 newBetMin);
  event SetFeePercent(uint8 newFeePercent);
  event Received(address, uint);
  event Joined(address indexed user, uint256 amount);

  constructor(
    address _owner,
    uint256 _betMin,
    uint8 _playersMax,
    address _usdtTokenAddress
  ) {
    require(_betMin > 0, 'Bet min should be greater than 0');
    require(_playersMax > 0, 'Players max should be greater than 0');
    require(_playersMax <= 100, 'Too many players');
    owner = _owner;
    feePercent = 5;
    betMin = _betMin;
    playersMax = _playersMax;
    playersCurrent = 0;
    lockedBalance = 0;
    usdtToken = IERC20(address(_usdtTokenAddress));
  }
  
  modifier onlyOwner() {
    require(msg.sender == owner, 'Only owner can call this function.');
    _;
  }

  function join(uint256 amount) public {
    require(playersCurrent < playersMax, 'Too many players');
    require(playersList[msg.sender].bet <= 0, 'Player already in game');
    require(amount >= betMin, 'Bet min should be greater than 0');

    uint256 fromTicket = (lockedBalance + 1000000000000000) / 1000000000000000;
    lockedBalance += amount;
    uint256 toTicket = (lockedBalance) / 1000000000000000;
    
    address user = msg.sender;
    require(usdtToken.balanceOf(user) >= amount, 'Not enough USDT balance');
    uint256 allowance = usdtToken.allowance(user, address(this));
    require(allowance >= amount, 'The allowance is not enough');
    require(
      usdtToken.transferFrom(user, address(this), amount),
      'Transfer failed'
    );
    Player memory newPlayer = Player(msg.sender, amount, fromTicket, toTicket);

    playersList[msg.sender] = newPlayer;
    playersNavList[playersCurrent] = msg.sender;
    playersCurrent++;

    if (playersCurrent >= playersMax) {
      raffle();
    }
    emit Joined(user, amount);
  }
  function getRandomNumber(
    uint256 minValue,
    uint256 maxValue
  ) public returns (uint256) {
    require(minValue < maxValue, 'Invalid range');

    // Pseudo-random number generation
    uint256 randomNumber = ((
      uint256(
        keccak256(
          abi.encodePacked(
            seed,
            blockhash(block.number - 1),
            block.coinbase,
            block.timestamp,
            block.difficulty,
            msg.sender
          )
        )
      )
    ) % (maxValue - minValue + 1)) + minValue;

    // Update seed for next use
    seed = randomNumber;

    return randomNumber;
  }

  function raffle() internal {
    uint256 totalTickets = lockedBalance / 1000000000000000;
    seed = uint256(
      keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))
    );
    uint256 winnerticket = getRandomNumber(1, totalTickets);
    winnerTicket = winnerticket;

    Winner memory winner = Winner(address(0), totalTickets);

    for (uint256 i = 0; i < playersMax; i++) {
      Player storage player = playersList[playersNavList[i]];
      if (
        player.ticketStart <= winnerticket && player.ticketEnd >= winnerticket
      ) {
        winner = Winner(player.playerAddress, winnerticket);
        break;
      }
    }

    Player memory playerWinner = playersList[winner.playerAddress];
    uint256 winnings = ((lockedBalance - playerWinner.bet) / 100) *
      (100 - feePercent) +
      playerWinner.bet;
    // playerWinner.playerAddress.transfer(amount);
    require(
      usdtToken.balanceOf(address(this)) >= winnings,
      'Not enough USDT balance'
    );

    // Transfer USDT to the sender
    require(
      usdtToken.transfer(playerWinner.playerAddress, winnings),
      'Transfer failed'
    );
    playerWinner.bet = 0;
    lockedBalance = 0;
    playersCurrent = 0;
    rounds++;
    totalPrize += winnings;
    if (winnings > maxWin) {
      maxWin = winnings;
    }
    for (uint256 i = 0; i < playersMax; i++) {
      delete playersList[playersNavList[i]];
      delete playersNavList[i];
    }
  }

  function cashOut(uint256 value) public onlyOwner payable {
    uint256 balance = usdtToken.balanceOf(address(this));
    require(
      (balance - lockedBalance + 500000) >= value,
      'Not enough USDT balance'
    );
    require(usdtToken.transfer(msg.sender, value), 'Transfer failed');
    emit OwnerCashout(value);
  }

  function setMaxPlayers(uint8 newPlayersMax) public onlyOwner {
    require(newPlayersMax <= 100, 'Too many players');
    require(newPlayersMax > 0, 'Too few players');
    emit SetPlayersMax(newPlayersMax);
    playersMax = newPlayersMax;
  }

  function setMinBet(uint256 newBetMin) public onlyOwner {
    require(newBetMin > 0, 'Bet min should be greater than 0');
    emit SetBetMin(newBetMin);
    betMin = newBetMin;
  }

  function setFeePercent(uint8 newFeePercent) public onlyOwner {
    require(newFeePercent <= 5, 'Too greedy');
    require(newFeePercent > 1, 'Take something from this');
    emit SetFeePercent(newFeePercent);
    feePercent = newFeePercent;
  }

  function get_bet_min() public view returns (uint256) {
    return betMin;
  }

  function get_players_max() public view returns (uint8) {
    return playersMax;
  }

  function get_players_current() public view returns (uint8) {
    return playersCurrent;
  }

  function get_locked_balance() public view returns (uint256) {
    return lockedBalance;
  }

  function get_winner_ticket() public view returns (uint256) {
    return winnerTicket;
  }

  function get_fee_percent() public view returns (uint8) {
    return feePercent;
  }
  function getStats() public view returns (uint256, uint256, uint256) {
    return (rounds, totalPrize, maxWin);
  }
}
