// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGRaid.sol";
import "./interfaces/IRandomizer.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface iUGWeapons {
  function burn(address _from, uint256 _id, uint256 _amount) external;  
  function mint(address _from, uint256 _id, uint256 _amount, bytes memory _data) external;
  function batchMint(address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) external;  
}

contract UGRaid is IUGRaid, Ownable, ReentrancyGuard {

  struct Queue {
    uint128 start;
    uint128 end;
    mapping(uint256 => uint256) ids;
  }

  constructor(
    address _ugnft, 
    address _ugFYakuza, 
    address _blood, 
    address _ugArena, 
    address _ugWeapons, 
    address _randomizer,
    address _devWallet,
    uint256 _devFclubId
  ) {
    ierc1155FY = IERC1155(_ugFYakuza);
    ugNFT = IUGNFT(_ugnft);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    uBlood = IUBlood(_blood);
    ugArena = IUGArena(_ugArena);
    ugWeapons = iUGWeapons(_ugWeapons);
    randomizer = IRandomizer(_randomizer);    
    devWallet = _devWallet;
    devFightClubId = _devFclubId;

    attackScoreToWeaponIndex[BRONZE_ATTACK_SCORE] = BRONZE;
    attackScoreToWeaponIndex[GOLD_ATTACK_SCORE] = GOLD_WEAPON;
    attackScoreToWeaponIndex[PLATINUM_DURABILITY_SCORE] = PLATINUM;
    attackScoreToWeaponIndex[TITANIUM_ATTACK_SCORE] = TITANIUM;
    attackScoreToWeaponIndex[DIAMOND_ATTACK_SCORE] = DIAMOND;
  }
  mapping (uint256 => uint256) attackScoreToWeaponIndex;
  //////////////////////////////////
  //          CONTRACTS          //
  /////////////////////////////////
  IERC1155 private ierc1155FY;
  IUGNFT private ugNFT;
  IUGFYakuza private ugFYakuza;
  IUGArena private ugArena;
  IUBlood private uBlood;
  iUGWeapons private ugWeapons;
  IRandomizer private randomizer; 

  //////////////////////////////////
  //          EVENTS             //
  /////////////////////////////////
  event RaidCreated(uint256 indexed raidId, Raid raid);
  event RaidersAssignedToRaid(RaidEntryTicket[] raidTickets, uint256 indexed raidId);
  event RaidResults(uint256 indexed raidId, RaidEntryTicket[] raidTickets, uint256[] scores);
  event RefereeRewardsPaid(address indexed referee, uint256 rewards);
  event YakuzaTaxPaidFromRaids(uint256 amount, uint256 indexed timestamp);
  event YakuzaFamilyWinner(uint256 indexed raidId, uint256 yakFamily);
  event YakuzaRaidShareStolen(uint256 indexed fighterId, uint256 indexed raidId);
  event RaiderOwnerBloodRewardClaimed(address indexed user);
  event FightClubOwnerBloodRewardClaimed(address indexed user);

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

  /*///////////////////////////////////////////////////////////////
                      WEAPON METALS BIT INDEXes
  //////////////////////////////////////////////////////////////*/
  //lowerweapons (0 - 14)
  uint8 constant STEEL = 0;
  uint8 constant BRONZE = 5;
  uint8 constant GOLD_WEAPON = 10;
  //upper weapons (15 - 29)
  uint8 constant PLATINUM = 15;
  uint8 constant TITANIUM = 20;
  uint8 constant DIAMOND = 25;

  //weapons bit indexes (metal + weapon = bit index (tokenId)
  uint8 constant KNUCKLES = 1;
  uint8 constant CHAINS = 2;
  uint8 constant BUTTERFLY = 3;
  uint8 constant MACHETE = 4;
  uint8 constant KATANA = 5;
  //////////////////////////////////////////
  uint8 constant SWEAT = 56;
  uint256 constant FIGHT_CLUB = 20000;
  uint256 constant BASE_RAID_SIZE = 5;  

  //weapons constants
  uint256 constant STEEL_DURABILITY_SCORE = 75;
  uint256 constant BRONZE_DURABILITY_SCORE = 80;
  uint256 constant GOLD_DURABILITY_SCORE = 85;
  uint256 constant PLATINUM_DURABILITY_SCORE = 90;
  uint256 constant TITANIUM_DURABILITY_SCORE = 95;
  uint256 constant DIAMOND_DURABILITY_SCORE = 100;

  uint256 constant STEEL_ATTACK_SCORE = 10;
  uint256 constant BRONZE_ATTACK_SCORE = 20;
  uint256 constant GOLD_ATTACK_SCORE = 40;
  uint256 constant PLATINUM_ATTACK_SCORE = 60;
  uint256 constant TITANIUM_ATTACK_SCORE = 80;
  uint256 constant DIAMOND_ATTACK_SCORE = 100;
  //Weapons only allowed starting at their respective tier
  //tier 1 = levels 1-3, tier 2 = levels 4-6, etc
  //tier = (level-1)/3  +  1  scrap the remainder
  //example tier for level 6 = (6-1)/3 (no remainder) + 1 = 2 (tier 2)
  //weapons start being used when knuckles are allowed at tier 4 (level 10)
  uint16 constant KNUCKLES_TIER = 4; //levels 10 and up
  uint16 constant CHAINS_TIER = 7; //levels 19 and up
  uint16 constant BUTTERFLY_TIER = 10;//levels 28 and up
  uint16 constant MACHETE_TIER = 14;//levels 40 and up
  uint16 constant KATANA_TIER = 18;//levels 52 and up
  
  uint16 constant MAX_SIZE_TIER = 4;

  uint256 constant BRUTALITY_WEIGHT = 40;
  uint256 constant YAKUZA_INTIMIDATION_WEIGHT = 5;
  
  uint256 constant WEAPONS_WEIGHT = 30;
  
  uint256 constant SWEAT_WEIGHT = 20;
  uint256 constant SCARS_WEIGHT = 5;
  uint256 constant UNSTAKE_COOLDOWN = 48 hours;
  uint256 private FIGHT_CLUB_BASE_CUT_PCT = 25;
  uint256 private YAKUZA_BASE_CUT_PCT = 5;
  uint256 private REFEREE_BASE_CUT_PCT = 10;
  uint256 public BASE_RAID_FEE = 100;

  bool public yakuzaRoundActive;
  bool public weaponsRoundActive;
  bool public sweatRoundActive;

  uint256 private MAX_RAIDERS_PER_REF = 100;
  uint256 private maxRaiderQueueLevelTier;
  uint256 private maxStakedFightClubRaidSizeTier;
  uint256 private maxStakedFightClubLevelTier;
  uint256 public ttlRaids;
  uint256 public totalFightClubsStaked;
  uint256 private devFightClubId;
  address private devWallet;
  

  mapping(address => bool) private _admins;
  //maps level => size => fightclub queue
  mapping(uint256 => mapping(uint256 => Queue)) public fightClubQueue;
  //maps level => size => Raider token Ids queue
  mapping(uint256 => mapping(uint256 => Queue)) public RaiderQueue;
  //maps fightclub id => owner address
  mapping(uint256 => address) public stakedFightclubOwners;
  //maps owner => number of staked fightclubs
  mapping(address => uint256) public ownerTotalStakedFightClubs;
  //maps address => weapon => metal score => value
  mapping(address => mapping(uint256 => mapping(uint256 => uint256 ))) public weaponsToMint;
  //maps tokenId to packed uint (bools) is in raider que
  mapping(uint256 => uint256) private raiderInQue;
  //maps Raider owner => blood rewards
  mapping(address => uint256) public raiderOwnerBloodRewards;
  //maps FightClub owner => blood rewards
  mapping(address => uint256) public fightClubOwnerBloodRewards;
  
  //Modifiers//
  modifier onlyAdmin() {
    if(!_admins[msg.sender]) revert Unauthorized();
    _;
  }

  modifier onlyEOA() {
    if(tx.origin != msg.sender) revert OnlyEOA();
    _;
  }

  //////////////////////////////////
  //     EXTERNAL FUNCTIONS      //
  /////////////////////////////////
  
  function referee(uint maxRaiders) external nonReentrant onlyEOA {  
    //this function gathers all raiders and matches them with raids
    uint256 raidSize;
    uint256 tempVal;    
    uint256 numRaiders;
    uint256 weaponsScore;
    uint256 yakuzaFamilyWinner;
    uint256 _yakRewards;
    uint256 refRewards;

    Raid memory raid;    
    RaidEntryTicket[] memory raidTickets ;
    uint256[] memory scores;
    //i = levelTier , j = sizeTier start from highest and we need to limit fighters
     for(uint8 i=uint8(maxRaiderQueueLevelTier); i >= 1; i--){
      for(uint8 j=uint8(maxStakedFightClubRaidSizeTier); j >= 1; j--){
        //BEGINNING OF EACH FIGHTER QUEUE
        raidSize = j*5;        
        tempVal = getRaiderQueueLength( i, j);//tempVal is queuelength here
        if(tempVal >= raidSize){                    
          tempVal = tempVal/raidSize;//tempval is now numRaids for this queue   
          //make sure we limit fighters per referee session
          if( tempVal > 2*(5-j)) tempVal = 2*(5-j);
          while(tempVal*raidSize + numRaiders > maxRaiders) {
            tempVal--;    
          }   
          numRaiders += tempVal * raidSize;
          //loop through multiples of raidsize to create multiple raids at once
          for(uint8 k; k < tempVal; k++){
            //BEGINNING OF RAID
            //create raid
            raid = _createRaid(i, j);            
            //get yakuza family for raid
            //yakuzaFamilyWinner is a random number between 0-2
            if(yakuzaRoundActive) yakuzaFamilyWinner = randomizer.getSeeds(tempVal, raid.id,1)[0]%3;
            emit YakuzaFamilyWinner(raid.id, yakuzaFamilyWinner);
            //fill with fighters and get raid tickets
            (raidTickets, raid) = _assignRaidersToRaid(raid, uint8(yakuzaFamilyWinner));
            
            //loop through to get scores/determine winner
            scores = new uint256[](raidSize);
            for(uint n=0; n<raidSize; n++){
             
              //only do following rounds if survive yakuza intimidation round   
              if(!yakuzaRoundActive || raidTickets[n].yakuzaFamily > 0){

                //weapons round
                if(weaponsRoundActive){
                  //get weapons scores
                  (weaponsScore, raidTickets[n] )= _getWeaponsScore(raid, raidTickets[n]);
                } else weaponsScore = 0;

                //sweat round
                if(!sweatRoundActive ){
                  raid.maxSweat = 1;
                  raidTickets[n].sweat = 0;                
                } 
                
                //safety check to make sure no division by 0
                if(raid.maxScars == 0) raid.maxScars = 1;
                if(raid.maxSweat == 0) raid.maxSweat = 1;
          
                //calculate scores
                scores[n] = (BRUTALITY_WEIGHT * raidTickets[n].fighterLevel * raidTickets[n].brutality)/(i*3) + 
                WEAPONS_WEIGHT * weaponsScore  +
                (SWEAT_WEIGHT * 100 * raidTickets[n].sweat )/ raid.maxSweat +
                (SCARS_WEIGHT * 100 * raidTickets[n].scars) / raid.maxScars + 
                YAKUZA_INTIMIDATION_WEIGHT * raidTickets[n].yakuzaFamily;
              }
              
              //if lost in yakuza round set score to 0
              if(yakuzaRoundActive && raidTickets[n].yakuzaFamily == 0){
                scores[n] = 0;
              }
             
              raid.revenue += raidTickets[n].entryFee;
            }
            
            // sort raidTickets by score
            _quickSort(scores, raidTickets, int(0), int(raidTickets.length - 1));

            bool isYakShareStolen;
            (raidTickets, isYakShareStolen) = _calculateRaiderRewards(scores, raidTickets, raid);
            if (!isYakShareStolen) _yakRewards += (YAKUZA_BASE_CUT_PCT * raid.revenue) / 100 ;
            //tally yakuza rewards
            else emit YakuzaRaidShareStolen(raidTickets[0].fighterId, raid.id);
            
            //fight club owner rewards
            fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += FIGHT_CLUB_BASE_CUT_PCT * raid.revenue/100; 
  
            //referee rewards
            refRewards += (REFEREE_BASE_CUT_PCT * raid.revenue) / 100 ;

            //emit events
            emit RaidResults(raid.id, raidTickets, scores);  
          }            
        }
      }
    }
    
    //get reward weapon for referee
    uint256 weapon; 
    uint256 weaponMetal; 
    if(weaponsRoundActive) {
      weaponMetal = randomizer.getSeeds(tempVal, refRewards,1)[0]%100;
      weapon = randomizer.getSeeds(tempVal, _yakRewards,1)[0]%100;
      if (weaponMetal <= 60) weaponMetal = 0;
      if (weaponMetal > 97) weaponMetal = 25;
      if (weaponMetal > 95) weaponMetal = 20;
      if (weaponMetal > 90) weaponMetal = 15;
      if (weaponMetal > 85) weaponMetal = 10;
      if (weaponMetal > 60) weaponMetal = 5;

      if (weapon <= 60) weapon = 1;
      if (weapon > 95) weapon = 5;
      if (weapon > 90) weapon = 4;
      if (weapon > 85) weapon = 3;
      if (weapon > 60) weapon = 2;

      weapon = weapon + weaponMetal;

    }
    
    
    
    ugArena.payRaidRevenueToYakuza( _yakRewards);
    //send ref rewards
    uBlood.mint(msg.sender,refRewards * 1 ether);
    ugWeapons.mint(msg.sender, weapon, numRaiders/5, "");

    emit RefereeRewardsPaid(msg.sender, refRewards);
    emit YakuzaTaxPaidFromRaids(_yakRewards, block.timestamp);
  }

  function getRaidCost(uint256 levelTier, uint256 sizeTier) public view returns (uint256 price) {
      return (BASE_RAID_FEE * (2 + sizeTier-1) * levelTier * 3);
  }

  function getRaiderQueueLength(uint8 level, uint8 sizeTier) public view returns (uint16){
   return _getQueueLength(RaiderQueue[level][sizeTier]);
  }

  function stakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
    //make sure is owned by sender
    if(!ugNFT.checkUserBatchBalance(msg.sender, tokenIds)) revert InvalidTokenId();    
    IUGNFT.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    if(tokenIds.length != fightclubs.length) revert MismatchArrays();
    
    _stakeFightclubs(msg.sender, tokenIds, fightclubs);
  }

  function unstakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    for(uint i; i < tokenIds.length;i++){
      //make sure sender is ringowner
      if(stakedFightclubOwners[tokenIds[i]] != msg.sender) revert InvalidTokenId();
      //Update unstake time
      ugNFT.setFightClubUnstakeTime(tokenIds[i], true);
      delete stakedFightclubOwners[tokenIds[i]];
      amounts[i] = 1;
    }

    totalFightClubsStaked -= tokenIds.length;
    ownerTotalStakedFightClubs[msg.sender] -= tokenIds.length;

    ugNFT.safeBatchTransferFrom(address(this), msg.sender, tokenIds, amounts, "");
    //emit TokenUnStaked(msg.sender, tokenIds);
  }
   
  function getStakedFightClubIDsForUser(address user) external view returns (uint256[] memory){
    //get balance of fight clubs
    uint256 numStakedFightClubs = ownerTotalStakedFightClubs[user];
    uint256[] memory _tokenIds = new uint256[](numStakedFightClubs);
    //loop through user balances until we find all the fighters
    uint count;
    uint ttl = ugNFT.ttlFightClubs();
    for(uint i = 1; count<numStakedFightClubs && i <= FIGHT_CLUB + ttl; i++){
      if(stakedFightclubOwners[FIGHT_CLUB + i] == user){
        _tokenIds[count] = FIGHT_CLUB + i;
        count++;
      }
    }
    return _tokenIds;
  }

  function claimRaiderBloodRewards() external nonReentrant {
    uint256 payout =  raiderOwnerBloodRewards[msg.sender];
    delete raiderOwnerBloodRewards[msg.sender];
    uBlood.mint(msg.sender, payout * 1 ether);
    emit RaiderOwnerBloodRewardClaimed(msg.sender);
  }

  function claimFightClubBloodRewards() external nonReentrant {
    uint256 payout =  fightClubOwnerBloodRewards[msg.sender];
    delete fightClubOwnerBloodRewards[msg.sender];
    uBlood.mint(msg.sender, payout * 1 ether);
    emit FightClubOwnerBloodRewardClaimed(msg.sender);
  }

  function getYakuzaRoundScore(uint256 yakuzaFamily, uint256 rand) private pure returns (uint8 _yakScore){
    //get Yakuza initimdation result
    if(rand == 0){
      if(yakuzaFamily == 0) return 1;//survive
      if(yakuzaFamily == 1) return 0;//lose
      if(yakuzaFamily == 2) return 100;//win
    }
    if(rand == 1){
      if(yakuzaFamily == 0) return 100;//win
      if(yakuzaFamily == 1) return 1;//survive
      if(yakuzaFamily == 2) return 0;//lose
    }
    if(rand == 2){
      if(yakuzaFamily == 0) return 0;//lose
      if(yakuzaFamily == 1) return 100;//win
      if(yakuzaFamily == 2) return 1;//survive
    }
    return 0;
  }

  function _weaponScore(uint256 attackScore, uint256 seed) private pure returns(uint score, bool _isBroken){
    if (attackScore == 0 || attackScore%10 != 0) return (0, false);
    //get metal if fighter is equipped with an unbroken weapon
    if (attackScore == 10){
      if ((seed <<= 8)%100 > 100 - STEEL_DURABILITY_SCORE) return (attackScore, false); 
      else return (0, true);
    }
    if (attackScore == 20){
      if ((seed <<= 8)%100 > 100 - BRONZE_DURABILITY_SCORE) return (attackScore, false); 
      else return (0, true);
    }
    if (attackScore == 40){
      if ((seed <<= 8)%100 > 100 - GOLD_DURABILITY_SCORE) return (attackScore, false); 
      else return (0, true);
    }
    if (attackScore == 60){
      if ((seed <<= 8)%100 > 100 - PLATINUM_DURABILITY_SCORE) return (attackScore, false); 
      else return (0, true);
    }
    if (attackScore == 80){
      if ((seed <<= 8)%100 > 100 - TITANIUM_DURABILITY_SCORE) return (attackScore, false); 
      else return (0, true);
    }
    if (attackScore == 100){
      return (attackScore, false); 
    }
  }

  function _getWeaponsScore(Raid memory raid, RaidEntryTicket memory ticket) private view returns (uint256 weaponsScore, RaidEntryTicket memory){
      uint256 _maxWeapons;
      //check if weapon breaks
      uint256[] memory seeds = randomizer.getSeeds(raid.maxScars, ticket.fighterId, 5);
      
      //calculate weapons score
      if(raid.levelTier >= KNUCKLES_TIER) {
        
        _maxWeapons++;
        (uint tempScore, bool _isBroken) = _weaponScore(ticket.knuckles, seeds[0]);
       
        weaponsScore += tempScore;
        //add 1 to score if broken -  memory instance will record to storage after raid calcs are made    
         if(_isBroken) ticket.knuckles += 1;
      }

      if(raid.levelTier >= CHAINS_TIER){
         
        _maxWeapons++;
        (uint tempScore, bool _isBroken) = _weaponScore(ticket.chains, seeds[1]);
        weaponsScore += tempScore;
        //add 1 to score if broken -  memory instance will record to storage after raid calcs are made    
         if(_isBroken) ticket.chains += 1;
      } 

      if(raid.levelTier >= BUTTERFLY_TIER){
        _maxWeapons++;
        (uint tempScore, bool _isBroken) = _weaponScore(ticket.butterfly, seeds[2]);
        weaponsScore += tempScore;
        //add 1 to score if broken -  memory instance will record to storage after raid calcs are made    
         if(_isBroken) ticket.butterfly += 1;
      } 

      if(raid.levelTier >= MACHETE_TIER){
        _maxWeapons++;
       (uint tempScore, bool _isBroken) = _weaponScore(ticket.machete, seeds[3]);
        weaponsScore += tempScore;
        //add 1 to score if broken -  memory instance will record to storage after raid calcs are made    
         if(_isBroken) ticket.machete += 1;
      } 

      if(raid.levelTier >= KATANA_TIER){
        _maxWeapons++;
        (uint tempScore, bool _isBroken) = _weaponScore(ticket.katana, seeds[4]);
        weaponsScore += tempScore;
        //add 1 to score if broken -  memory instance will record to storage after raid calcs are made    
         if(_isBroken) ticket.katana += 1;
      } 
      weaponsScore = _maxWeapons > 0 ? weaponsScore / _maxWeapons : 0;
      
      return (weaponsScore, ticket);
  }

  function _calculateRaiderRewards(uint256[] memory scores, RaidEntryTicket[] memory raidTickets, Raid memory raid) private returns (RaidEntryTicket[] memory, bool yakShareStolen) {
    address raiderOwner;
    //collect stats to permanently upgrade fighters
    uint256[] memory raidStatsPacked = new uint256[](raidTickets.length);
    //assign resulting scars and weapons scores to fighters and pay out blood rewards
    for(uint o; o<raidTickets.length;o++){
      raiderOwner = ugArena.getStakeOwner(raidTickets[o].fighterId);
      //1st
      if(o == 0){
        //1st place blood reward is raid revenue * 1st place base pct + size tier
        raidTickets[o].winnings = raid.revenue * 25 / 100;

        //cunning gives cunning/2 pct chance of taking yakuza cut
        if(randomizer.getSeeds(ttlRaids, raidTickets[o].fighterId, 1)[0]%100 <= raidTickets[o].cunning/2){
          raidTickets[o].winnings += uint32(raid.revenue * YAKUZA_BASE_CUT_PCT / 100);
          yakShareStolen = true;
         }
      }
        if(o == 0 || o == 1 || o == 2){
        //weapon rewards (if over a certain size tier)
        if(raid.sizeTier >= 2) {
          if(raid.levelTier >= KNUCKLES_TIER && raid.levelTier < CHAINS_TIER)
             if(o == 0) weaponsToMint[raiderOwner][0][20*(raid.sizeTier)]++;
             if(o == 1 && raid.sizeTier == 4) weaponsToMint[raiderOwner][0][PLATINUM_ATTACK_SCORE]++;
             if(o == 2 && raid.sizeTier == 4) weaponsToMint[raiderOwner][0][GOLD_ATTACK_SCORE]++;
          if(raid.levelTier >= CHAINS_TIER && raid.levelTier < BUTTERFLY_TIER)
             if(o == 0) weaponsToMint[raiderOwner][1][20*(raid.sizeTier)]++;
             if(o == 1 && raid.sizeTier == 4) weaponsToMint[raiderOwner][1][PLATINUM_ATTACK_SCORE]++;
             if(o == 2 && raid.sizeTier == 4) weaponsToMint[raiderOwner][1][GOLD_ATTACK_SCORE]++;
          if(raid.levelTier >= BUTTERFLY_TIER && raid.levelTier < MACHETE_TIER)
             if(o == 0) weaponsToMint[raiderOwner][2][20*(raid.sizeTier)]++;
             if(o == 1 && raid.sizeTier == 4) weaponsToMint[raiderOwner][2][PLATINUM_ATTACK_SCORE]++;
             if(o == 2 && raid.sizeTier == 4) weaponsToMint[raiderOwner][2][GOLD_ATTACK_SCORE]++;
          if(raid.levelTier >= MACHETE_TIER && raid.levelTier < KATANA_TIER)
             if(o == 0) weaponsToMint[raiderOwner][3][20*(raid.sizeTier)]++;
             if(o == 1 && raid.sizeTier == 4) weaponsToMint[raiderOwner][3][PLATINUM_ATTACK_SCORE]++;
             if(o == 2 && raid.sizeTier == 4) weaponsToMint[raiderOwner][3][GOLD_ATTACK_SCORE]++;
          if(raid.levelTier >= KATANA_TIER)
             if(o == 0) weaponsToMint[raiderOwner][4][20*(raid.sizeTier)]++;
             if(o == 1 && raid.sizeTier == 4) weaponsToMint[raiderOwner][4][PLATINUM_ATTACK_SCORE]++;
             if(o == 2 && raid.sizeTier == 4) weaponsToMint[raiderOwner][4][GOLD_ATTACK_SCORE]++;
        }
      }
      //2nd place blood reward is raid revenue * 2nd place base pct - size tier
      if(o == 1) raidTickets[o].winnings = raid.revenue * 15 / 100;
    
      //3rd place blood reward is raid revenue * 3rd place base pct
      if(o == 2 && raidTickets[o].sizeTier > 1) raidTickets[o].winnings = raid.revenue * 5 / 100;
    
      //4th place blood reward is raid revenue * 4th place base pct
      if(o == 3 && raidTickets[o].sizeTier > 2) raidTickets[o].winnings = raid.revenue * 5 / 100;
      
      //5th place blood reward is raid revenue * 5th place base pct
      if(o == 4 && raidTickets[o].sizeTier > 3) raidTickets[o].winnings = raid.revenue * 5 / 100;

      //scars if not kicked out of yakuzaa round
      if (scores[o] > 0) raidTickets[o].scars += uint16(o + 1);

      //pack ticket to prepare for sendoff to ugNFT contract for permanent write
      raidStatsPacked[o] = packTicket(raidTickets[o]);

      //pay out blood rewards
      raiderOwnerBloodRewards[raiderOwner] += raidTickets[o].winnings;
      //mint weapon rewards
    }
    //WRITE RESULTS PERMANENTLY TO FIGHTERS
    ugFYakuza.setRaidTraitsFromPacked( raidStatsPacked);
    return (raidTickets, yakShareStolen);
  }

  function claimWeapons() external nonReentrant onlyEOA {   
    (,uint256 ttlWeaponTypes) = getUnclaimedWeaponsCount(msg.sender);
    require(ttlWeaponTypes > 0,"NO WEAPONS TO MINT");
    uint amt;
    uint256 count;    
    uint256[] memory ids = new uint256[](ttlWeaponTypes);
    uint256[] memory amounts = new uint256[](ttlWeaponTypes);    
    for(uint i; i<=4;i++){
      //i is weapon and attack score is metal(20*j)
      for(uint j=1; j<=4 && count < ttlWeaponTypes; j++){
        amt = weaponsToMint[msg.sender][i][20*j];
        if(amt > 0) {
          amounts[count] = amt;
          ids[count] = attackScoreToWeaponIndex[20*j] + i + 1;
          count++;
          delete weaponsToMint[msg.sender][i][20*j];
        }
      }
    } 
    ugWeapons.batchMint(msg.sender, ids, amounts, "");
  }

  function getUnclaimedWeaponsCount(address user) public view returns (uint256 numWeapons, uint256 numWeaponTypes) {
    uint amt;
    for(uint i; i<5;i++){
      //i is weapon and attack score is metal(20*j)
      for(uint j=1; j<=4; j++){
        amt = weaponsToMint[user][i][20*j];
        if(amt > 0){
          numWeapons += weaponsToMint[user][i][20*j];
          numWeaponTypes++;
        }
       
      }
    } 
  }

  function _assignRaidersToRaid(Raid memory raid, uint8 yakuzaFamilyWinner) private returns (RaidEntryTicket[] memory, Raid memory) {
    require(raid.sizeTier > 0, "raid error");
    uint8 _raidSize = raid.sizeTier * 5;
    RaidEntryTicket[] memory tickets = new RaidEntryTicket[](_raidSize);
    uint8 _yakScore;

    for(uint i; i < _raidSize; i++){
     tickets[i] = getTicketInQueue(raid.levelTier,raid.sizeTier);
      //mark that fighter has been removed from que if it hasnt already been marked as removed
      if(viewIfRaiderIsInQueue(tickets[i].fighterId)) _updateIfRaiderIsInQueue(tickets[i].fighterId, Operations.Sub);
      if(yakuzaRoundActive){
        //returns 0 if lost yakuza intimidation round, 1 if survived, 100 if gets boost
        _yakScore = getYakuzaRoundScore(tickets[i].yakuzaFamily, yakuzaFamilyWinner);
        if(_yakScore ==0){
          uint roll = randomizer.getSeeds(raid.id, tickets[i].fighterId, 1)[0]%100;
          if(roll < tickets[i].courage ) _yakScore = 1;
        }
       
      } else _yakScore = 0;
      //record yak result to the yakuzaFamily ticket memory slot
      tickets[i].yakuzaFamily = _yakScore;
      //if fighter survives yakuza round
      if(!yakuzaRoundActive || _yakScore > 0){
        //check if fighter has max sweat or max scars
        raid.maxScars = raid.maxScars >= tickets[i].scars ? raid.maxScars : tickets[i].scars;
        raid.maxSweat = raid.maxSweat >= tickets[i].sweat ? raid.maxSweat : tickets[i].sweat;              
      }
    }
    emit RaidersAssignedToRaid(tickets, raid.id);
    return (tickets, raid);
  }

  //this function creates a raid with next availble fightclub
  function _createRaid(uint8 levelTier, uint8 _raidSizeTier) private returns (Raid memory){
    Raid memory raid; 
    //get queue length for fightclubs
    uint16 queuelength = _getQueueLength(fightClubQueue[levelTier][_raidSizeTier]);
    uint256 fclubId;
    
    //loop through fight clubs to find next eligible
    for(uint i; i < queuelength; i++){
      //packed id with size 
      fclubId = getFightClubInQueueAndRecycle( levelTier, _raidSizeTier) ;
      //if we find an elible one, break out of for loop
      if(fclubId > 0) break;
    }

    //if no eligible fight clubs are in queue
    if(fclubId == 0) {
      //get house/dev fight club to hold raid
      fclubId = devFightClubId ;
    }
    
    raid.levelTier = levelTier;
    raid.sizeTier = _raidSizeTier; 
    raid.id = uint32(++ttlRaids);
    raid.fightClubId = uint16(fclubId );
    raid.timestamp = uint32(block.timestamp);
    emit RaidCreated(raid.id, raid);
  
    return raid;
  }

   //returns 0 if token is no longer eligible for que (did not level up/ maintain or not staked)
  function getFightClubInQueueAndRecycle( uint8 _levelTier, uint8 _raidSizeTier) private returns (uint256) {
    //get packed value: id with fightclub size
    uint256 id = removeFromQueue(fightClubQueue[_levelTier][_raidSizeTier], IDS_BITS_SIZE);
    //uint256 unpackedId = id%2 ** 11;
    //do not re-enter queue if has been unstaked since getting in queue
    if(stakedFightclubOwners[id] == address(0)) return 0;
    IUGNFT.ForgeFightClub memory fightclub = ugNFT.getForgeFightClub(id);
    //and is right level and size, do not re-enter queue if fails this check
    if(fightclub.size < _raidSizeTier || fightclub.level < _levelTier) return 0;
    //if fight club has not been leveled up at least once in last week + 1 day auto unstake fightclub
    if(fightclub.lastLevelUpgradeTime + 8 days < block.timestamp) {
      //auto unstake if hasnt been already
      _autoUnstakeFightClub(id);
      return 0;
    }

    //add back to queue with current size
    //unpackedId |= fightclub.size<<11;
    addToQueue(fightClubQueue[_levelTier][_raidSizeTier], id, IDS_BITS_SIZE);
    //check to see fight club has been leveled up at least once in last week
    if(fightclub.lastLevelUpgradeTime + 7 days < block.timestamp) return 0;
    return id;
  }

  function getTicketInQueue( uint256 _levelTier, uint256 _raidSizeTier) private returns (RaidEntryTicket memory) {
    RaidEntryTicket memory ticket;
    //get queue length for raiders
    uint256 queuelength = _getQueueLength(RaiderQueue[_levelTier][_raidSizeTier]);
    //loop through raiders to find next eligible
    uint256 packedTicket;
    for(uint i; i < queuelength; i++){
      //get paked ticket
      packedTicket = removeFromQueueFullUint(RaiderQueue[_levelTier][_raidSizeTier]);
      //unpack ticket
      ticket = unpackTicket(packedTicket);
      //if we find an eligible one, return id
      if(ticket.fighterId > 0 && ierc1155FY.balanceOf(address(ugArena),ticket.fighterId) == 1) return ticket;
    }
    //if we fail to find one send an empty
    ticket = RaidEntryTicket(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    return ticket;
  }

  function addTicketsToRaiderQueue(uint256[] memory packedTickets) external onlyAdmin {
    uint8 levelTier;
    for(uint i; i < packedTickets.length; i++){
      levelTier = uint8(packedTickets[i]>>8);
      if(levelTier > 0) {
        levelTier = (levelTier-1)/3 + 1;
      }
      //add to queue and convert fighterid to raider id to use a smaller storage slot
      addToQueueFullUint(RaiderQueue[levelTier][uint8(packedTickets[i])], packedTickets[i]);
      maxRaiderQueueLevelTier = levelTier  > maxRaiderQueueLevelTier ? levelTier  : maxRaiderQueueLevelTier;    
    }
  }    

  function _stakeFightclubs(address account, uint256[] calldata tokenIds, IUGNFT.ForgeFightClub[] memory fightclubs) private {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    for(uint i; i < tokenIds.length; i++){
      //make sure it has been unstaked for 48 hours to clear the fightclub que 
      //so fclub owner cant game by continually staking and unstaking
      if(fightclubs[i].lastUnstakeTime > 1662170673 && fightclubs[i].lastUnstakeTime + UNSTAKE_COOLDOWN > block.timestamp) revert StillUnstakeCoolDown();
      
      stakedFightclubOwners[tokenIds[i]] = account;
      amounts[i] = 1;
      //add fightclub to queue, use (1 , 1) for (startSizeTier, startlevelTier)
       _addFightClubToQueues(tokenIds[i], 1, 1, fightclubs[i]);
       //set unstake time to 0
      ugNFT.setFightClubUnstakeTime(tokenIds[i], false);
    }
    totalFightClubsStaked += tokenIds.length;
    ownerTotalStakedFightClubs[account] += tokenIds.length;

    ugNFT.safeBatchTransferFrom(account, address(this), tokenIds, amounts, "");
    //emit TokenStaked(account, tokenId);
  }

  function addFightClubToQueueAfterLevelSizeUp(
    uint256 tokenId, 
    uint8 sizeTiersToUpgrade, 
    uint8 levelTiersToUpgrade, 
    IUGNFT.ForgeFightClub calldata fightclub
  ) external onlyAdmin {

    if(levelTiersToUpgrade > 0){
      _addFightClubToQueues(tokenId,  1,  fightclub.level, fightclub);
    }

    if(sizeTiersToUpgrade > 0){
      _addFightClubToQueues(tokenId,  fightclub.size,  1, fightclub);
    }
   
  }

  function _addFightClubToQueues(uint256 tokenId, uint8 startSizeTier, uint8 startLevelTier, IUGNFT.ForgeFightClub memory fightclub) private {
    //check to see fight club has been leveled up at least once in last week
    if(fightclub.lastLevelUpgradeTime + 7 days > block.timestamp) 
    {
      uint8 maxLevelTier = fightclub.level;  
      uint8 maxSizeTier = fightclub.size; 
     
      for(uint8 j=startLevelTier; j <= maxLevelTier; j++){
        for(uint8 k=startSizeTier; k <= maxSizeTier; k++){
          addToQueue(fightClubQueue[j][k], tokenId, IDS_BITS_SIZE);
          maxStakedFightClubRaidSizeTier = k  > maxStakedFightClubRaidSizeTier ? k  : maxStakedFightClubRaidSizeTier;
          maxStakedFightClubLevelTier = maxLevelTier  > maxStakedFightClubLevelTier ? maxLevelTier  : maxStakedFightClubLevelTier;
        }
      }
    }
  }

  function _autoUnstakeFightClub(uint256 tokenId) private {
    address account = stakedFightclubOwners[tokenId];
    delete stakedFightclubOwners[tokenId];
    ugNFT.setFightClubUnstakeTime(tokenId, true);
     totalFightClubsStaked--;
    ownerTotalStakedFightClubs[account]--;
    ugNFT.safeTransferFrom(address(this), account, tokenId, 1, "");
  }

  function _getQueueLength(Queue storage queue) private view returns (uint16){
    return uint16(queue.end - queue.start);
  }

  function burnBlood(address account, uint256 amount) private {
    uBlood.burn(account , amount * 1 ether);
    //allocate 10% of all burned blood to dev wallet for continued development
    uBlood.mint(devWallet, amount * 1 ether /10);
  }

  function addToQueueFullUint(Queue storage queue, uint256 packedUint) private {
    queue.ids[queue.end++] = packedUint;
  }

  function removeFromQueueFullUint(Queue storage queue) private returns (uint256) {    
    //get first in line
    uint256 packedUint = queue.ids[queue.start];

    // remove first in line id from queue
    queue.ids[queue.start++] = 0;
    
    //return first in line
    return packedUint;
  }

  //queue functions
  function addToQueue(Queue storage queue, uint256 _id, uint256 bitsize) private {
    uint256 bin;
    uint256 index;

    // Get bin and index of end index, then increment end
    (bin, index) = getIDBinIndex(queue.end++);

    // Update id in bin/index
    queue.ids[bin] = _viewUpdateBinValue(queue.ids[bin], bitsize, index, _id, Operations.Add);

  }

  //get next in queue and remove
  function removeFromQueue(Queue storage queue, uint256 bitsize) private returns (uint256) {
    uint256 bin;
    uint256 index;
    // Get bin and index of start index, then increment start
    (bin, index) = getIDBinIndex(queue.start++);
    
    //get first in line
    uint256 _id = getValueInBin(queue.ids[bin], bitsize, index);

    // remove first in line id from bin/index
    queue.ids[bin] = _viewUpdateBinValue(queue.ids[bin], bitsize, index, _id, Operations.Sub);
    
    //return first in line
    return _id;
  }

  /** OWNER ONLY FUNCTIONS */

  function setContracts(
    address _ugArena, 
    address _ugFYakuza, 
    address _ugNFT, 
    address _uBlood,
    address _ugWeapons, 
    address _randomizer
  ) external onlyOwner {
    ierc1155FY = IERC1155(_ugFYakuza);
    ugNFT = IUGNFT(_ugNFT);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    uBlood = IUBlood(_uBlood);
    ugArena = IUGArena(_ugArena);
    ugWeapons = iUGWeapons(_ugWeapons);
    randomizer = IRandomizer(_randomizer);
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setWeaponsRound(bool active) external onlyOwner {
    weaponsRoundActive = active;
  }

  function setYakuzaRound(bool active) external onlyOwner {
    yakuzaRoundActive = active;
  }
  
  function setSweatRound(bool active) external onlyOwner {
    sweatRoundActive = active;
  }

  function setDevWallet(address newWallet) external onlyOwner {
    if(newWallet == address(0)) revert InvalidAddress();
    devWallet = newWallet;
  }

  function setDevFightClubId(uint256 id) external onlyOwner {
    devFightClubId = id;
  }

  function setMaxRaidersPerRef(uint256 numRaiders) external onlyOwner {
    MAX_RAIDERS_PER_REF = numRaiders;
  }

  function setRefereeBasePct(uint256 pct) external onlyOwner {
    REFEREE_BASE_CUT_PCT = pct;
  }
  
  function setBaseRaidFee(uint256 newBaseFee) external onlyOwner {    
    BASE_RAID_FEE = newBaseFee;
  }

  function _quickSort(uint256[] memory keyArr, RaidEntryTicket[] memory dataArr, int left, int right) private pure {
    int i = left;
    int j = right;
    if (i == j) return;
    uint pivot = keyArr[uint(left + (right - left) / 2)];
    while (i <= j) {
        while (keyArr[uint(i)] > pivot) i++;
        while (pivot > keyArr[uint(j)]) j--;
        if (i <= j) {
            (keyArr[uint(i)], keyArr[uint(j)]) = (keyArr[uint(j)], keyArr[uint(i)]);
            (dataArr[uint(i)], dataArr[uint(j)]) = (dataArr[uint(j)], dataArr[uint(i)]);
            i++;
            j--;
        }
    }
    if (left < j)
        _quickSort(keyArr, dataArr, left, j);
    if (i < right)
        _quickSort(keyArr, dataArr, i, right);
  }

  //////////////////////////////////////
  //     Packed Balance Functions     //
  //////////////////////////////////////
  // Operations for _updateIDBalance
  enum Operations { Add, Sub }
  //map raidId => raiders packed uint 16 bits
  mapping(uint256 => uint256) internal raiders;
  uint256 constant IDS_BITS_SIZE =16;
  uint256 constant IDS_PER_UINT256 = 16;
  uint256 constant RAID_IDS_BIT_SIZE = 32;

  function _viewUpdateBinValue(
    uint256 _binValues, 
    uint256 bitsize, 
    uint256 _index, 
    uint256 _amount, 
    Operations _operation
  ) internal pure returns (uint256 newBinValues) {

    uint256 shift = bitsize * _index;
    uint256 mask = (uint256(1) << bitsize) - 1;
    
    if (_operation == Operations.Add) {
      newBinValues = _binValues + (_amount << shift);
      require(newBinValues >= _binValues, " OVERFLOW2");
      require(
        ((_binValues >> shift) & mask) + _amount < 2**bitsize, // Checks that no other id changed
        "OVERFLOW1"
      );
  
    } else if (_operation == Operations.Sub) {
      
      newBinValues = _binValues - (_amount << shift);
      require(newBinValues <= _binValues, " UNDERFLOW");
      require(
        ((_binValues >> shift) & mask) >= _amount, // Checks that no other id changed
        "viewUpdtBinVal: UNDERFLOW"
      );

    } else {
      revert("viewUpdtBV: INVALID_WRITE"); // Bad operation
    }

    return newBinValues;
  }

  function getIDBinIndex(uint256 _id) private pure returns (uint256 bin, uint256 index) {
    bin = _id / IDS_PER_UINT256;
    index = _id % IDS_PER_UINT256;
    return (bin, index);
  }

  function getValueInBin(uint256 _binValues, uint256 bitsize, uint256 _index)
    public pure returns (uint256)
  {
    // Mask to retrieve data for a given binData
    uint256 mask = (uint256(1) << bitsize) - 1;
    
    // Shift amount
    uint256 rightShift = bitsize * _index;
    return (_binValues >> rightShift) & mask;
  }

  function viewIfRaiderIsInQueue( uint256 tokenId) public view returns(bool) {
    uint id = tokenId;
    // Get bin and index of _id
    uint256 bin = id / 256;
    uint256 index = id % 256;
    uint256 _binValue = raiderInQue[bin];

    _binValue = _binValue & (1 << index);
    // return balance
    return _binValue > 0;
  }  


  function packTicket(RaidEntryTicket memory _ticket) 
    private pure returns (uint256)
  {
      uint256 ticket = uint256(_ticket.sizeTier);
      uint256 nextVal = _ticket.fighterLevel;
      ticket |= nextVal<<8;
      nextVal = _ticket.yakuzaFamily;
      ticket |= nextVal<<16;
      nextVal = _ticket.courage;
      ticket |= nextVal<<24;
      nextVal = _ticket.brutality;
      ticket |= nextVal<<32;
      nextVal = _ticket.cunning;
      ticket |= nextVal<<40;
      nextVal = _ticket.knuckles;
      ticket |= nextVal<<48;
      nextVal = _ticket.chains;
      ticket |= nextVal<<56;
      nextVal = _ticket.butterfly;
      ticket |= nextVal<<64;
      nextVal = _ticket.machete;
      ticket |= nextVal<<72;
      nextVal = _ticket.katana;
      ticket |= nextVal<<80;
      nextVal = _ticket.scars;
      ticket |= nextVal<<96;
      nextVal = _ticket.sweat;
      ticket |= nextVal<<128;
      nextVal = _ticket.fighterId;
      ticket |= nextVal<<160;
      nextVal = _ticket.entryFee;
      ticket |= nextVal<<192;
      return ticket;
  }

  function unpackTicket(uint256 packedTicket) 
    private pure returns (RaidEntryTicket memory _ticket)
  {
      _ticket.sizeTier = uint8(packedTicket);
      _ticket.fighterLevel = uint8(packedTicket>>8);
      _ticket.yakuzaFamily = uint8(packedTicket>>16);
      _ticket.courage = uint8(packedTicket>>24);
      _ticket.brutality = uint8(packedTicket>>32);
      _ticket.cunning = uint8(packedTicket>>40);
      _ticket.knuckles = uint8(packedTicket>>48);
      _ticket.chains = uint8(packedTicket>>56);
      _ticket.butterfly = uint8(packedTicket>>64);
      _ticket.machete = uint8(packedTicket>>72);
      _ticket.katana = uint8(packedTicket>>80);
      _ticket.scars = uint16(packedTicket>>96);
      _ticket.sweat = uint32(packedTicket>>128);
      _ticket.fighterId = uint32(packedTicket>>160);
      _ticket.entryFee = uint32(packedTicket>>192);
      return _ticket;
  }

  function addIfRaidersInQueue(uint256[] memory tokenIds) external onlyAdmin {
    for(uint i; i<tokenIds.length; i++){
      _updateIfRaiderIsInQueue(tokenIds[i], Operations.Add);
    }
  }

  function _updateIfRaiderIsInQueue( uint256 tokenId, Operations _operation) internal {
    uint id = tokenId;
    // Get bin and index of _id
    uint256 bin = id / 256;
    uint256 index = id % 256;
    uint256 _binValue = raiderInQue[bin];

    if (_operation == Operations.Add){
      _binValue = _binValue | (1 << index);
    }

    if (_operation == Operations.Sub){
      _binValue = _binValue - (1 << index);
    }

    raiderInQue[bin] = _binValue;
  }

  /////////////////////////////////////////////////
  //emergency functions if raids get stuck
  //first clear any level/size queues then remove any fighters one by one 
  //that are still showing up as being in raids
  function clearRaiderQueue(uint8 level, uint8 size) external onlyOwner {
    delete RaiderQueue[level][size];
  }
  function removeIfRaiderIsInQueue (uint256 tokenId) external onlyOwner {
    _updateIfRaiderIsInQueue(  tokenId, Operations.Sub);
  }
  ////////////////////////////////////////////////

  /** ONLY ADMIN FUNCTIONS */
  function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}