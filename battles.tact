import "@stdlib/deploy";
struct Player {
    address: Address;
    bet: Int as coins; 
    fromTicket: Int as coins;
    toTicket: Int as coins;
}

struct Room {
    id: Int as uint64;
    players: map<Address, Player>;
    playersNavList: map<Int, Address>;
    capacity: Int as uint8;
    lockedBalance: Int as coins;
    playersCount: Int as uint8;
    currBet: Int as coins;
    isPrivate: Bool;
    winnerTicket: Int as uint64;
    creator: Address;
}

struct Stats {
    rounds: Int as uint64;
    totalPrize: Int as coins;
    maxWin: Int as coins;
}

struct Winner {
    address: Address;
    ticket: Int as uint64;
    amount: Int as coins;
}

message JoinRoom {
    roomIndex: Int as uint8;
}
message CreateRoom {
    capacity: Int as uint8;
    bet: Int as coins;
    isPrivate: Bool;
}
message CancelRoom {
    roomIndex: Int as uint8;
}

message OwnerCashout {
    value: Int as coins;
}
message SetMaxCapacity {
    new_players_max: Int as uint8;
}

message SetBetMin {
    new_bet_min: Int as coins;
}

message SetFeePercent {
    fee_percent: Int as uint8;
}
contract BattleRooms with Deployable {
    owner: Address;
    bet_min: Int as coins;
    max_capacity: Int as uint8;
    rooms: map<Int, Room>;
    roomsLength: Int;
    feePercent: Int as uint8 = 5;
    lastWinner: Winner;
    rounds: Int as uint64 = 0;
    totalPrize: Int as coins = 0;
    maxWin: Int as coins = 0;

    receive(msg: SetMaxCapacity) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Access denied.");
        require(msg.new_players_max <= 100, "Too many players");
        require(msg.new_players_max > 0, "Too few players");
        self.max_capacity = msg.new_players_max;
    }

    receive(msg: SetBetMin) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Access denied.");
        require(msg.new_bet_min <= ton("100"), "Too big min bet");
        require(msg.new_bet_min > 0, "Too low min bet");
        self.bet_min = msg.new_bet_min;
    }

    receive(msg: SetFeePercent) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Access denied.");
        require(msg.fee_percent <= 5, "Too greedy");
        require(msg.fee_percent > 1, "Take something from this");
        self.feePercent = msg.fee_percent;
    }


    init(owner: Address, bet_min: Int, max_capacity: Int, fee_percent: Int) {
        self.owner = owner;
        self.bet_min = bet_min;
        self.max_capacity = max_capacity;
        self.roomsLength = 0;
        self.feePercent = fee_percent;
        self.lastWinner = Winner{address: owner, ticket: 0, amount: 0};
    }

    get fun get_last_winner(): Winner {
        return self.lastWinner;
    }

    receive(msg: OwnerCashout) {
        let ctx: Context = context();
        require(ctx.sender == self.owner, "Access denied.");
        require(msg.value > 0, "Invalid cashout value");
        require(myBalance() > msg.value, "Invalid value!");

        send(SendParameters{
            to: self.owner,
            value: msg.value,
            mode: SendIgnoreErrors,
            bounce: true,
            body: "Owner cashout!".asComment()
        });
    }

    receive(msg: CreateRoom) {
        let ctx: Context = context();
        
        require(ctx.value >= self.bet_min, "Error: Value < Minimum_bet!");
        require(msg.capacity <= self.max_capacity, "Error: Capacity > Max_capacity!");
        require(msg.capacity > 1, "Error: Capacity <= 1!");

        let fromTicket: Int = (0 + ton("0.0001")) / 100000; // Example: User bets 50 TON. = 50000000000 nanoTons. / 100000 = 500000 tickets. + ton(0.001) = 500001 (so tickets wont collide on users.)
        let lockedBalance: Int = 0 + (ctx.value - ton("0.02"));
        let toTicket: Int = lockedBalance / 100000; //End ticket number.

        let player: Player = Player{
            address: ctx.sender,
            bet: ctx.value,
            fromTicket: fromTicket,
            toTicket: toTicket
        };

        let players: map<Address, Player> = emptyMap();
        players.set(ctx.sender, player);
        let playersNavList: map<Int, Address> = emptyMap();
        playersNavList.set(ctx.sender.asSlice().hash(), ctx.sender);
        self.roomsLength = self.roomsLength + 1;

        let room: Room = Room{
            id: self.roomsLength,
            players: players,
            playersNavList: playersNavList,
            capacity: msg.capacity,
            playersCount: 1,
            lockedBalance: lockedBalance,
            currBet: ctx.value,
            isPrivate: msg.isPrivate,
            creator: ctx.sender,
            winnerTicket: 0
        };
        self.rooms.set(self.roomsLength, room);
    }

    receive(msg: JoinRoom) {
        let ctx: Context = context();
        let room: Room? = self.rooms.get(msg.roomIndex);
        require(room != null, "Error: Room not found!");
        require((room!!).playersCount < (room!!).capacity, "Error: Room is full!");
        require((room!!).winnerTicket == 0, "Error: Game ended");
        let foundPlayer: Player? = (room!!).players.get(ctx.sender);
        require(foundPlayer == null, "Error: This player in game already!");
        require(ctx.value >= (room!!).currBet, "Error: Value < Minimum_bet!");
        let fromTicket: Int = ((room!!).lockedBalance + ton("0.0001")) / 100000; // Example: User bets 50 TON. = 50000000000 nanoTons. / 100000 = 500000 tickets. + ton(0.001) = 500001 (so tickets wont collide on users.)
        let toTicket: Int = ((room!!).lockedBalance + (ctx.value - ton("0.02"))) / 100000; //End ticket number.

        let player: Player = Player{
            address: ctx.sender,
            bet: ctx.value,
            fromTicket: fromTicket,
            toTicket: toTicket};
        let newPlayers: map<Address, Player>  = (room!!).players;
        newPlayers.set(ctx.sender, player);
        let newPlayersNavList: map<Int, Address> = (room!!).playersNavList;
        newPlayersNavList.set(ctx.sender.asSlice().hash(), ctx.sender);
        let newRoom: Room = Room {
            id: msg.roomIndex,
            players: newPlayers,
            playersNavList: newPlayersNavList,
            capacity: (room!!).capacity,
            lockedBalance: (room!!).lockedBalance + ctx.value,
            playersCount: (room!!).playersCount + 1,
            currBet: ctx.value,
            isPrivate: (room!!).isPrivate,
            creator: (room!!).creator,
            winnerTicket: 0
        };
        self.rooms.set(msg.roomIndex, newRoom);
        if(newRoom.playersCount == newRoom.capacity) {
            self.startGame(msg.roomIndex);
        }
    }

    fun startGame(roomIndex: Int) {
        let room: Room? = self.rooms.get(roomIndex);
        require(room != null, "Error: Room not found!");
        nativeRandomizeLt(); // May lt be with you.
        let totalTickets: Int = (room!!).lockedBalance / 100000;
        let winnerTicket: Int = random(0, totalTickets);
        let foundPair: DictPair? = DictGetMin((room!!).playersNavList);
        let winner: Winner = Winner{address: self.owner, ticket: totalTickets, amount: 0};


        while(foundPair != null){

            let player: Player? = (room!!).players.get((foundPair!!).value);
            
            let num: Int = abs(winnerTicket - (player!!).fromTicket);
            if(num < winner.ticket){
                winner.address = (player!!).address;
                winner.ticket = num;
            }

            num = abs(winnerTicket - (player!!).toTicket);
            if(num < winner.ticket){
                winner.address = (player!!).address;
                winner.ticket = num;
            }

            foundPair = DictGetNext((room!!).playersNavList, (foundPair!!).key);
        }
        let playerWinner: Player? = (room!!).players.get(winner.address);
        require(playerWinner != null, "Error: Winner not found!");

        send(SendParameters {
            to: (playerWinner!!).address,
            value: ((((room!!).lockedBalance - (playerWinner!!).bet) / 100) * (100 - self.feePercent)) + (playerWinner!!).bet, // Here we take fee_percent, only from winnings. Original bet will be returned to player. (bet + (winnings - fee))
            mode: SendIgnoreErrors,
            bounce: false,
            body: ("Winner! Congrats!").asComment()
        });
        winner.amount = ((((room!!).lockedBalance - (playerWinner!!).bet) / 100) * (100 - self.feePercent)) + (playerWinner!!).bet;
        self.lastWinner = winner;
        self.rounds = self.rounds + 1;
        self.totalPrize = self.totalPrize + winner.amount;
        if(winner.amount > self.maxWin) {
            self.maxWin = winner.amount;
        }
        let newRoom: Room = Room {
            id: roomIndex,
            players: (room!!).players,
            playersNavList: (room!!).playersNavList,
            capacity: (room!!).capacity,
            lockedBalance: (room!!).lockedBalance,
            playersCount: (room!!).playersCount,
            currBet: (room!!).currBet,
            isPrivate: (room!!).isPrivate,
            winnerTicket: winnerTicket,
            creator: (room!!).creator
        };
        self.rooms.set(roomIndex, newRoom);
    }

    receive(msg: CancelRoom) {
        let ctx: Context = context();
        let room: Room? = self.rooms.get(msg.roomIndex);
        require(room != null, "Error: Room not found!");
        require((room!!).playersCount == 1, "Error: Room has players");
        require((room!!).creator == ctx.sender, "Error: Not the creator of the room");
        require((room!!).winnerTicket == 0, "Error: Game ended");

        send(SendParameters {
            to: (room!!).creator,
            value: ((room!!).currBet / 100) * (100 - self.feePercent),
            mode: SendIgnoreErrors,
            bounce: false,
            body: ("Cancel Battle").asComment()
        });
        self.rooms.set(msg.roomIndex, null);
    }

    get fun get_rooms(): map<Int, Room> {
        return self.rooms;
    }
    get fun get_room(roomIndex: Int): Room? {
        return self.rooms.get(roomIndex);
    }
    get fun get_stats(): Stats {
        let stats: Stats = Stats {
            rounds: self.rounds,
            totalPrize: self.totalPrize,
            maxWin: self.maxWin
            };
        return stats;
    }
    get fun get_my_rooms(address: Address, take: Int, skip: Int, current: Bool): map<Int, Room> {
        let myRooms: map<Int, Room> = emptyMap();
        let totalAdded: Int = 0; // Counter for how many rooms have been added
        let currentlySkipped: Int = 0; // Counter for how many rooms have been skipped
    
        let i: Int = 1;
        while (i <= self.roomsLength && totalAdded < take) {
            let room: Room? = self.rooms.get(i);
            if (room != null && (!current || (current && (room!!).winnerTicket == 0))) {
                let player: Player? = (room!!).players.get(address);
                if (player != null) {
                    if (currentlySkipped < skip) {
                        // Increase skip counter until we reach the number of items to skip
                        currentlySkipped = currentlySkipped + 1;
                    } else {
                        // Start adding rooms once we've skipped enough
                        myRooms.set(totalAdded + 1, room!!); // Adjusted key to be 1-index based on totalAdded
                        totalAdded = totalAdded + 1;
                    }
                }
            }
            i = i + 1;
        }
    
        return myRooms;
    }
}



struct NativePair {
    key: Int?;
    value: Address?;
    flag: Bool;
}

struct DictPair {
    key: Int;
    value: Address;
}

@name(idict_get_min?)
native native_dict_get_min(dict: map<Int, Address>, length: Int): NativePair;

fun DictGetMin(dict: map<Int, Address>): DictPair? {
    let pair: NativePair = native_dict_get_min(dict, 257);
    if (pair.flag) {
        return DictPair{key: pair.key!!, value: pair.value!!};
    }
    else {
        return null;
    }
}

@name(idict_get_next?)
native native_dict_get_next(dict: map<Int, Address>, length: Int, pivot: Int): NativePair;

fun DictGetNext(dict: map<Int, Address>, pivot: Int): DictPair? {
    let pair: NativePair = native_dict_get_next(dict, 257, pivot);
    if (pair.flag) {
        return DictPair{key: pair.key!!, value: pair.value!!};
    }
    else {
        return null;
    }
}
