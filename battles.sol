// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Lobby {
  struct Player {
    address addr;
    uint256 bet;
    uint256 fromTicket;
    uint256 toTicket;
  }

  struct Room {
    uint256 id;
    mapping(address => Player) players;
    mapping(uint256 => address) playersNavList;
    address creator;
    uint8 capacity;
    uint256 lockedBalance;
    uint8 playersCount;
    uint256 currBet;
    bool isPrivate;
    uint256 winnerTicket;
  }
  struct SimpleRoom {
    uint256 id;
    uint8 capacity;
    uint256 lockedBalance;
    uint8 playersCount;
    uint256 currBet;
    bool isPrivate;
    address creator;
    uint256 winnerTicket;
  }

  struct Winner {
    address addr;
    uint256 ticket;
    uint256 bet;
  }

  address public owner;
  uint256 public bet_min;
  uint8 public max_capacity;
  mapping(uint256 => Room) public rooms;
  uint256 public roomsLength;
  uint256 public roomHistoryLength;
  uint8 public feePercent = 5;
  uint256 private seed;
  IERC20 public usdtToken; // USDT token address
  uint256 public rounds = 0;
  uint256 public totalPrize = 0;
  uint256 public maxWin = 0;

  constructor(
    address _owner,
    uint256 _bet_min,
    uint8 _max_capacity,
    uint8 _fee_percent,
    address _usdtTokenAddress
  ) {
    owner = _owner;
    bet_min = _bet_min;
    max_capacity = _max_capacity;
    roomsLength = 0;
    feePercent = _fee_percent;
    usdtToken = IERC20(_usdtTokenAddress);
  }

  event RoomCreated(uint256 roomIndex, uint8 capacity, uint256 bet);
  event PlayerJoined(uint256 roomIndex, address player);
  event GameStarted(uint256 roomIndex);
  event WinnerAnnounced(address winner, uint256 prize);
  event OwnerCashout(uint256 value);

  modifier onlyOwner() {
    require(msg.sender == owner, 'Only owner can call this function.');
    _;
  }

  function createRoom(
    uint8 _capacity,
    uint256 _bet,
    bool _isPrivate
  ) external payable {
    require(_bet >= bet_min, 'Error: Value < Minimum_bet!');
    require(_capacity <= max_capacity, 'Error: Capacity > Max_capacity!');
    require(_capacity > 1, 'Error: Capacity <= 1!');

    address user = msg.sender;
    require(user != address(0), 'Invalid address');
    require(usdtToken.balanceOf(user) >= _bet, 'Not enough USDT balance');
    uint256 allowance = usdtToken.allowance(user, address(this));
    require(allowance >= _bet, 'The allowance is not enough');
    require(
      usdtToken.transferFrom(user, address(this), _bet),
      'Transfer failed'
    );
    Room storage room = rooms[roomsLength++];
    room.id = roomsLength;
    room.capacity = _capacity;
    room.currBet = _bet;
    room.isPrivate = _isPrivate;
    room.creator = msg.sender;
    uint256 fromTicket = (room.lockedBalance + 1000000000000000) / 1000000000000000;
    room.lockedBalance += _bet;
    uint256 toTicket = (room.lockedBalance) / 1000000000000000;

    room.players[msg.sender] = Player(
      msg.sender,
      room.currBet,
      fromTicket,
      toTicket
    ); // Adjust ticket calculation as needed
    room.playersNavList[room.playersCount] = msg.sender;
    room.playersCount++;

    emit RoomCreated(roomsLength - 1, _capacity, _bet);
  }

  function joinRoom(uint256 roomId) external payable {
    Room storage room = rooms[roomId];
    require(room.winnerTicket == 0, 'Error: Game already finished!');
    require(room.playersCount < room.capacity, 'Error: Room is full!');
    require(
      room.players[msg.sender].addr == address(0),
      'Error: This player in game already!'
    );

    address user = msg.sender;
    require(
      usdtToken.balanceOf(user) >= room.currBet,
      'Not enough USDT balance'
    );
    uint256 allowance = usdtToken.allowance(user, address(this));
    require(allowance >= room.currBet, 'The allowance is not enough');
    require(
      usdtToken.transferFrom(user, address(this), room.currBet),
      'Transfer failed'
    );

    uint256 fromTicket = (room.lockedBalance + 1000000000000000) / 1000000000000000;
    room.lockedBalance += room.currBet;
    uint256 toTicket = (room.lockedBalance) / 1000000000000000;

    room.players[msg.sender] = Player(
      msg.sender,
      room.currBet,
      fromTicket,
      toTicket
    ); // Adjust ticket calculation as needed
    room.playersNavList[room.playersCount] = msg.sender;
    room.playersCount++;

    emit PlayerJoined(roomId, msg.sender);

    if (room.playersCount == room.capacity) {
      startGame(roomId);
    }
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

  function startGame(uint256 roomId) internal {
    emit GameStarted(roomId);
    Room storage room = rooms[roomId];
    // Game logic to determine winner and distribute prize
    seed = uint256(
      keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))
    );

    uint256 totalTickets = room.lockedBalance / 1000000000000000;
    uint256 winnerTicket = getRandomNumber(1, totalTickets);
    Winner memory winner = Winner(address(0), totalTickets, 0);

    for (uint256 i = 0; i < room.playersCount; i++) {
      Player storage player = room.players[room.playersNavList[i]];
      if (
        player.fromTicket <= winnerTicket && player.toTicket >= winnerTicket
      ) {
        winner = Winner(player.addr, winnerTicket, player.bet);
        break;
      }
    }
    // Simplified logic to select a winner and calculate prize
    // winner.addr = owner; // Placeholder for the winner's calculation
    uint256 winnings = ((room.lockedBalance - winner.bet) / 100) *
      (100 - feePercent) +
      winner.bet;
    // playerWinner.playerAddress.transfer(amount);
    require(
      usdtToken.balanceOf(address(this)) >= winnings,
      'Not enough USDT balance'
    );

    // Transfer USDT to the sender
    require(usdtToken.transfer(winner.addr, winnings), 'Transfer failed');
    if (winnings > maxWin) {
      maxWin = winnings;
    }
    totalPrize += winnings;
    rounds++;
    // Reset or delete room data as needed
    rooms[roomId].winnerTicket = winnerTicket;

    emit WinnerAnnounced(winner.addr, winnings);
  }

  function cashOut(uint256 value) public onlyOwner payable {
    uint256 balance = usdtToken.balanceOf(address(this));
    require(balance >= value, 'Not enough USDT balance');
    require(usdtToken.transfer(msg.sender, value), 'Transfer failed');
    emit OwnerCashout(value);
  }

  function getAllRooms() public view returns (SimpleRoom[] memory) {
    SimpleRoom[] memory tempRooms = new SimpleRoom[](roomsLength);
    for (uint i = 0; i < roomsLength; i++) {
      tempRooms[i] = SimpleRoom(
        rooms[i].id,
        rooms[i].capacity,
        rooms[i].lockedBalance,
        rooms[i].playersCount,
        rooms[i].currBet,
        rooms[i].isPrivate,
        rooms[i].creator,
        rooms[i].winnerTicket
      );
    }
    return tempRooms;
  }

  function getRoom(uint256 roomId) public view returns (SimpleRoom memory) {
    Room storage room = rooms[roomId];
    return
      SimpleRoom(
        room.id,
        room.capacity,
        room.lockedBalance,
        room.playersCount,
        room.currBet,
        room.isPrivate,
        room.creator,
        room.winnerTicket
      );
  }
  function getRoomPlayers(
    uint256 roomId
  ) public view returns (Player[] memory) {
    Room storage room = rooms[roomId];
    Player[] memory tempPlayers = new Player[](room.playersCount);
    for (uint i = 0; i < room.playersCount; i++) {
      tempPlayers[i] = room.players[room.playersNavList[i]];
    }
    return tempPlayers;
  }

  function getStats() public view returns (uint256, uint256, uint256) {
    return (rounds, totalPrize, maxWin);
  }

  function getMyRooms(
    address player,
    uint256 take,
    uint256 skip,
    bool current
  ) public view returns (SimpleRoom[] memory) {
    uint256 count = 0;

    // First pass to count relevant rooms
    if (skip >= roomsLength) {
      return new SimpleRoom[](0); // Return an empty array
    }
    uint itemsToReturn = take;
    if (skip + take > roomsLength) {
      itemsToReturn = roomsLength - skip;
    }
    for (uint i = 0; i < itemsToReturn; i++) {
      if (
        rooms[skip + i].players[player].addr != address(0) &&
        (current ? rooms[skip + i].winnerTicket == 0 : true)
      ) {
        count++;
      }
    }

    // Allocate memory array based on count
    SimpleRoom[] memory tempRooms = new SimpleRoom[](count);

    // Second pass to populate the array
    uint256 index = 0;
    for (uint i = 0; i < itemsToReturn; i++) {
      if (
        rooms[skip + i].players[player].addr != address(0) &&
        (current ? rooms[skip + i].winnerTicket == 0 : true)
      ) {
        tempRooms[index] = SimpleRoom(
          rooms[skip + i].id,
          rooms[skip + i].capacity,
          rooms[skip + i].lockedBalance,
          rooms[skip + i].playersCount,
          rooms[skip + i].currBet,
          rooms[skip + i].isPrivate,
          rooms[skip + i].creator,
          rooms[skip + i].winnerTicket
        );
        index++;
      }
    }
    return tempRooms;
  }

  function cancelRoom(uint256 roomId) external payable {
    Room storage room = rooms[roomId];
    require(room.winnerTicket == 0, 'Error: Game already finished!');
    require(room.creator == msg.sender, "Error: You're not the owner");
    require(room.playersCount == 1, 'Error: Game has players');

    uint256 returnValue = (room.currBet / 100) * (100 - feePercent);

    require(
      usdtToken.balanceOf(address(this)) >= returnValue,
      'Not enough USDT balance'
    );

    // Transfer USDT to the sender
    require(usdtToken.transfer(room.creator, returnValue), 'Transfer failed');

    rooms[roomId].winnerTicket = 99999;
  }

  event setMaxCapacityEv(uint8 newPlayersMax);
  event SetBetMin(uint256 newBetMin);
  event SetFeePercent(uint8 newFeePercent);
  function setMaxCapacity(uint8 newCapacity) public onlyOwner {
    require(newCapacity <= 100, 'Too many players');
    require(newCapacity > 0, 'Too few players');
    emit setMaxCapacityEv(newCapacity);
    max_capacity = newCapacity;
  }

  function setMinBet(uint256 newBetMin) public onlyOwner {
    require(newBetMin > 0, 'Bet min should be greater than 0');
    emit SetBetMin(newBetMin);
    bet_min = newBetMin;
  }

  function setFeePercent(uint8 newFeePercent) public onlyOwner {
    require(newFeePercent <= 5, 'Too greedy');
    require(newFeePercent > 1, 'Take something from this');
    emit SetFeePercent(newFeePercent);
    feePercent = newFeePercent;
  }
}
