// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGYakDen.sol";
import "./interfaces/IUGFClubAlley.sol";
import "./interfaces/IRaidEntry.sol";

interface iugWeapons {
    function burn(
        address _from,
        uint256 _id,
        uint256 _amount
    ) external;

    function mint(
        address _from,
        uint256 _id,
        uint256 _amount,
        bytes calldata data
    ) external;
}

interface iugRaid {
    function addIfRaidersInQueue(uint256[] memory tokenIds) external;

    function addTicketsToRaiderQueue(uint256[] memory packedTickets) external;

    function sweatRoundActive() external view returns (bool);

    function viewIfRaiderIsInQueue(uint256 tokenId)
        external
        view
        returns (bool);

    function getRaidCost(uint256, uint256) external view returns (uint256);
}

contract RaidEntry is IRaidEntry, ReentrancyGuard, Ownable {
    constructor(
        address _ugFYakuza,
        address _blood,
        address _ugArena,
        address _ugWeapons,
        address _ugRaid,
        address _ugYakDen,
        address _fclubAlley,
        address _devWallet
    ) {
        ugFYakuza = IUGFYakuza(_ugFYakuza);
        uBlood = IUBlood(_blood);
        ugArena = IUGArena(_ugArena);
        ugWeapons = iugWeapons(_ugWeapons);
        ugRaid = iugRaid(_ugRaid);
        ugYakDen = IUGYakDen(_ugYakDen);
        fclubAlley = IUGFClubAlley(_fclubAlley);
        devWallet = _devWallet;
    }

    //////////////////////////////////
    //          CONTRACTS          //
    /////////////////////////////////
    IUGFYakuza private ugFYakuza;
    IUGArena private ugArena;
    IUBlood private uBlood;
    iugWeapons private ugWeapons;
    iugRaid private ugRaid;
    IUGYakDen private ugYakDen;
    IUGFClubAlley private fclubAlley;

    //////////////////////////////////
    //          ERRORS             //
    /////////////////////////////////
    error MismatchArrays();
    //error InvalidTokens(uint256 tokenId);
    error InvalidOwner();
    error InvalidAddress();
    error InvalidTokenId();
    error StillUnstakeCoolDown();
    error Unauthorized();
    error OnlyEOA();
    error InvalidSize();
    error AlreadyInQueue(uint256 tokenId);

    uint8 constant SWEAT = 56;
    uint16 constant MAX_SIZE_TIER = 4;
    uint8 public TRAIN_MULTIPLIER = 2;
    uint8 public FIGHTCLUB_CUT = 10;
    uint8 public YAKUZA_CUT = 10;

    //Modifiers//
    modifier onlyAdmin() {
        if (!_admins[msg.sender]) revert Unauthorized();
        _;
    }

    modifier onlyEOA() {
        if (tx.origin != msg.sender) revert OnlyEOA();
        _;
    }

    mapping(address => bool) private _admins;
    address private devWallet;

    //player function for entering Raids, enter fighter id, size raid to enter, sweat to allocate, yakuza pick
    function enterRaid(
        uint256[] calldata tokenIds,
        RaiderEntry[] calldata raiderEntries
    ) external onlyEOA nonReentrant returns (uint256 ttlBloodEntryFee) {
        uint256 ttlSweat;
        uint256 bloodEntryFee;
        uint256 raidSize;
        uint256 size4Raids;

        //make sure tokens staked in arena by sender by claiming
        ugArena.claimManyFromArena(tokenIds, false);

        if (tokenIds.length != raiderEntries.length) revert MismatchArrays();

        //get fighters
        uint256[] memory packedFighters = ugFYakuza.getPackedFighters(tokenIds);
        uint256[] memory packedTickets = new uint256[](packedFighters.length);

        for (uint256 i; i < packedFighters.length; i++) {
            //make sure its a fighter not yakuza
            if (!unPackFighter(packedFighters[i]).isFighter) continue;
            raidSize = raiderEntries[i].size;

            //make sure raider not already in queue
            if (ugRaid.viewIfRaiderIsInQueue(tokenIds[i]))
                revert AlreadyInQueue(tokenIds[i]);
            if (raidSize == 0 || raidSize > MAX_SIZE_TIER) revert InvalidSize();
            if (raidSize == 4) size4Raids++;

            ttlSweat += raiderEntries[i].sweat;
            (packedTickets[i], bloodEntryFee) = packTicketForEntry(
                unPackFighter(packedFighters[i]),
                raidSize,
                raiderEntries[i].sweat,
                tokenIds[i],
                raiderEntries[i].yakFamily
            );

            ttlBloodEntryFee += bloodEntryFee;
        }

        if (size4Raids > 0) {
            //update raid timer for size 4 raids
            uint256 count;
            uint256[] memory packedSize4Raiders = new uint256[](size4Raids);
            for (
                uint256 i;
                i < raiderEntries.length && count < size4Raids;
                i++
            ) {
                if (raiderEntries[i].size == 4) {
                    packedSize4Raiders[count++] = packedTickets[i];
                }
            }
            ugFYakuza.setRaidTraitsFromPacked(packedSize4Raiders);
        }

        //burn sweat (ID = 56)
        if (ugRaid.sweatRoundActive() && ttlSweat > 0)
            ugWeapons.burn(msg.sender, SWEAT, ttlSweat);
        //burn blood entry fee
        burnBlood(msg.sender, ttlBloodEntryFee);

        //add raid tickets to Raid Queue
        ugRaid.addTicketsToRaiderQueue(packedTickets);
        ugRaid.addIfRaidersInQueue(tokenIds);
    }

    function enterTrain(
        uint256[] calldata tokenIds,
        RaiderEntry[] calldata raiderEntries
    ) external onlyEOA nonReentrant returns (uint256 ttlBloodEntryFee) {
        uint256 ttlSweat;
        uint256 bloodEntryFee;

        //make sure tokens staked in arena by sender by claiming
        ugArena.claimManyFromArena(tokenIds, false);

        if (tokenIds.length != raiderEntries.length) revert MismatchArrays();

        //get fighters
        uint256[] memory packedFighters = ugFYakuza.getPackedFighters(tokenIds);
        uint256[] memory packedTickets = new uint256[](packedFighters.length);

        for (uint256 i; i < packedFighters.length; i++) {
            //make sure its a fighter not yakuza
            if (!unPackFighter(packedFighters[i]).isFighter) continue;

            ttlSweat += raiderEntries[i].sweat;
            (packedTickets[i], bloodEntryFee) = packTicketForEntry(
                unPackFighter(packedFighters[i]),
                raiderEntries[i].size,
                raiderEntries[i].sweat,
                tokenIds[i],
                raiderEntries[i].yakFamily
            );

            ttlBloodEntryFee += bloodEntryFee;
        }

        ttlBloodEntryFee *= TRAIN_MULTIPLIER;

        //burn sweat (ID = 56)
        if (ugRaid.sweatRoundActive() && ttlSweat > 0)
            ugWeapons.burn(msg.sender, SWEAT, ttlSweat);
        //burn blood entry fee
        burnBlood(msg.sender, ttlBloodEntryFee);
        //pay fight clubs
        fclubAlley.payRevenueToFightClubs(
            (ttlBloodEntryFee * FIGHTCLUB_CUT) / 100
        );
        //pay yakuza
        ugYakDen.payRevenueToYakuza((ttlBloodEntryFee * YAKUZA_CUT) / 100);

        ugFYakuza.setRaidTraitsFromPacked(packedTickets);
    }

    function burnBlood(address account, uint256 amount) private {
        uBlood.burn(account, amount * 1 ether);
        //allocate 10% of all burned blood to dev wallet for continued development
        uBlood.mint(devWallet, (amount * 1 ether) / 10);
    }

    function setDevWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) revert InvalidAddress();
        devWallet = newWallet;
    }

    function setTrainMultilpier(uint8 multiplier) external onlyOwner {
        TRAIN_MULTIPLIER = multiplier;
    }

    function setFightClubCut(uint8 cut) external onlyOwner {
        FIGHTCLUB_CUT = cut;
    }

    function setYakuzaCut(uint8 cut) external onlyOwner {
        YAKUZA_CUT = cut;
    }

    function addAdmin(address addr) external onlyOwner {
        _admins[addr] = true;
    }

    function removeAdmin(address addr) external onlyOwner {
        delete _admins[addr];
    }

    function packTicketForEntry(
        IUGFYakuza.FighterYakuza memory fighter,
        uint256 sizeTier,
        uint256 sweat,
        uint256 tokenId,
        uint256 yakFamily
    ) private view returns (uint256, uint256 bloodEntryFee) {
        uint256 ticket = sizeTier;
        uint256 nextVal = fighter.level;
        ticket |= nextVal << 8;
        nextVal = yakFamily;
        ticket |= nextVal << 16;
        nextVal = fighter.courage;
        ticket |= nextVal << 24;
        nextVal = fighter.brutality;
        ticket |= nextVal << 32;
        nextVal = fighter.cunning;
        ticket |= nextVal << 40;
        nextVal = fighter.knuckles;
        ticket |= nextVal << 48;
        nextVal = fighter.chains;
        ticket |= nextVal << 56;
        nextVal = fighter.butterfly;
        ticket |= nextVal << 64;
        nextVal = fighter.machete;
        ticket |= nextVal << 72;
        nextVal = fighter.katana;
        ticket |= nextVal << 80;
        nextVal = fighter.scars;
        ticket |= nextVal << 96;
        nextVal = sweat;
        ticket |= nextVal << 128;
        //fighterId
        nextVal = tokenId;
        ticket |= nextVal << 160;
        //entryFee
        nextVal = ugRaid.getRaidCost((fighter.level - 1) / 3 + 1, sizeTier);
        bloodEntryFee = nextVal;
        ticket |= nextVal << 192;

        return (ticket, bloodEntryFee);
    }

    function unPackFighter(uint256 packedFighter)
        private
        pure
        returns (IUGFYakuza.FighterYakuza memory)
    {
        IUGFYakuza.FighterYakuza memory fighter;
        fighter.isFighter = uint8(packedFighter) % 2 == 1 ? true : false;
        fighter.Gen = uint8(packedFighter >> 1) % 2;
        fighter.level = uint8(packedFighter >> 2);
        fighter.rank = uint8(packedFighter >> 10);
        fighter.courage = uint8(packedFighter >> 18);
        fighter.cunning = uint8(packedFighter >> 26);
        fighter.brutality = uint8(packedFighter >> 34);
        fighter.knuckles = uint8(packedFighter >> 42);
        fighter.chains = uint8(packedFighter >> 50);
        fighter.butterfly = uint8(packedFighter >> 58);
        fighter.machete = uint8(packedFighter >> 66);
        fighter.katana = uint8(packedFighter >> 74);
        fighter.scars = uint16(packedFighter >> 90);
        fighter.imageId = uint16(packedFighter >> 106);
        fighter.lastLevelUpgradeTime = uint32(packedFighter >> 138);
        fighter.lastRankUpgradeTime = uint32(packedFighter >> 170);
        fighter.lastRaidTime = uint32(packedFighter >> 202);

        return fighter;
    }
}
