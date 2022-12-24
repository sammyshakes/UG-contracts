// SPDX-License-Identifier: MIT LICENSE

pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "./ERC1155/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

//import "./Randomizer.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGRaid.sol";
//for testing only
import "./test/console.sol";


contract UGRaid is IUGRaid, Ownable, ReentrancyGuard, Pausable {

  struct Queue {
    uint128 start;
    uint128 end;
    mapping(uint256 => uint256) ids;
  }
  
  bool constant TEST_PRINTS = false;

  constructor(address _ugnft, address _blood, address _ugArena) {
    ierc1155 = IERC1155(_ugnft);
    ugNFT = IUGNFTs(_ugnft);
    uBlood = IUBlood(_blood);
    ugArena = IUGArena(_ugArena);

    //_pause();
  }

  //////////////////////////////////
  //          CONTRACTS          //
  /////////////////////////////////
  IERC1155 public ierc1155;
  IUGNFTs public ugNFT;
  IUGArena public ugArena;
  IUBlood public uBlood;
 

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

  //////////////////////////////////
  //          ERRORS             //
  /////////////////////////////////
  error MismatchArrays();
  error InvalidTokens(uint256 tokenId);
  error InvalidLevel();
  error InvalidOwner();
  error InvalidAddress();
  error InvalidTokenId();
  error StillUnstakeCoolDown();
  error Unauthorized();
  error OnlyEOA(address txorigin, address sender);
  error InvalidSize(uint8 size, uint32 sweat, uint8 yak, uint i);
  error AlreadyInQueue();

  uint256 constant BASE_RAID_SIZE = 5;
  uint16 constant FIGHT_CLUB = 20000;
  uint32 constant FIGHTER = 100000;

  //weapons constants
  uint8 constant STEEL_DURABILITY_SCORE = 75;
  uint8 constant BRONZE_DURABILITY_SCORE = 80;
  uint8 constant GOLD_DURABILITY_SCORE = 85;
  uint8 constant PLATINUM_DURABILITY_SCORE = 90;
  uint8 constant TITANIUM_DURABILITY_SCORE = 95;
  uint8 constant DIAMOND_DURABILITY_SCORE = 100;

  uint8 constant STEEL_ATTACK_SCORE = 10;
  uint8 constant BRONZE_ATTACK_SCORE = 20;
  uint8 constant GOLD_ATTACK_SCORE = 30;
  uint8 constant PLATINUM_ATTACK_SCORE = 50;
  uint8 constant TITANIUM_ATTACK_SCORE = 80;
  uint8 constant DIAMOND_ATTACK_SCORE = 100;
  //Weapons only allowed starting at their respective tier
  //tier 1 = levels 1-3, tier 2 = levels 4-6, etc
  //tier = (level-1)/3  +  1  scrap the remainder
  //example tier for level 6 = (6-1)/3 (no remainder) + 1 = 2 (tier 2)
  //weapons start being used when knuckles are allowed at tier 4 (level 10)
  uint8 public KNUCKLES_TIER = 4; //levels 10 and up
  uint8 public CHAINS_TIER = 7; //levels 19 and up
  uint8 public SWITCHBLADE_TIER = 10;//levels 28 and up
  uint8 public MACHETE_TIER = 14;//levels 40 and up
  uint8 public KATANA_TIER = 18;//levels 52 and up

  uint256 public BRUTALITY_WEIGHT = 50;
  uint256 public WEAPONS_WEIGHT = 25;
  uint256 public SWEAT_WEIGHT = 15;
  uint256 public SCARS_WEIGHT = 5;
  uint256 public YAKUZA_INTIMIDATION_WEIGHT = 5;

  uint256 public FIGHT_CLUB_BASE_CUT_PCT = 5;
  uint256 public YAKUZA_BASE_CUT_PCT = 10;
  uint256 public REFEREE_BASE_CUT_PCT = 5;
  uint256 public BASE_RAID_FEE = 100;

  uint256 public UNSTAKE_COOLDOWN = 48 hours;

  
  uint256 constant MAX_SIZE_TIER = 4;

  bool public yakuzaRoundActive;
  bool public weaponsRoundActive;
  bool public sweatRoundActive;

  address private devWallet;
  uint256 private devFightClubId;
  
  mapping(address => bool) private _admins;
  //maps level => size => fightclub queue
  mapping(uint256 => mapping(uint256 => Queue)) public  fightClubQueue;
  //maps level => size => Raider token Ids queue
  mapping(uint256 => mapping(uint256 => Queue)) private RaiderQueue;
  //maps Raider owner => blood rewards
  mapping(address => uint256) public raiderOwnerBloodRewards;
  //maps FightClub owner => blood rewards
  mapping(address => uint256) public fightClubOwnerBloodRewards;
  //maps fightclub id => owner address
  mapping(uint256 => address) public stakedFightclubOwners;
  //maps owner => number of staked fightclubs
  mapping(address => uint256) public ownerTotalStakedFightClubs;
  //maps address => weapon => metal score => value
  mapping(address => mapping(uint256 => mapping(uint256 => uint256 ))) private weaponsToMint;
  //maps tokenId to packed uint (bools) is in raider que
  mapping(uint256 => uint256) public raiderInQue;

  uint256 public _totalFightClubsStaked;
  uint256 public ttlRaids;
  uint256 public maxStakedFightClubRaidSizeTier;
  uint256 public maxStakedFightClubLevelTier;
  uint256 public maxRaiderQueueLevelTier;

  //Modifiers//
  modifier onlyAdmin() {
    if(!_admins[_msgSender()]) revert Unauthorized();
    _;
  }

  modifier onlyEOA() {
    if(tx.origin != _msgSender()) revert OnlyEOA({txorigin: tx.origin, sender: _msgSender()});
    _;
  }
  
  function referee() external nonReentrant onlyEOA {  
    //this function gathers all raiders and matches them with raids
    uint8 raidSize;
    uint8 numRaids;
    uint8 queueLength;
    uint256 weaponsScore;
    uint256 yakuzaFamilyWinner;
    uint256 scarsScore;
    uint256 _yakRewards;
    uint256 refRewards;

    Raid memory raid;    
    RaidEntryTicket[] memory raidTickets ;
    uint256[] memory scores;

    for(uint8 i=1; i <= maxRaiderQueueLevelTier; i++){
      for(uint8 j=1; j <= maxStakedFightClubRaidSizeTier; j++){
        
        //BEGINNING OF EACH FIGHTER QUE
        raidSize = j*5;
        queueLength = getRaiderQueueLength( i, j);
        if(queueLength >= raidSize){
          numRaids = queueLength/raidSize;
          //loop through multiples of raidsize to create multiple raids at once
          for(uint k; k < numRaids; k++){
            //BEGINNING OF RAID
            //create raid
            raid = _createRaid(i, j);

            if(TEST_PRINTS){
              console.log("+-------------------+");
              console.log("RAID ID",raid.id);
              console.log("raidLevelTier:",raid.levelTier);
              console.log("raid sizeTier:",raid.sizeTier);
              console.log("raid size:",raidSize);
            }
            
            //get yakuza family for raid
            //yakuzaFamilyWinner is a random number between 0-2
            if(yakuzaRoundActive) yakuzaFamilyWinner = getSeeds(numRaids, raid.id,1)[0]%3;
            emit YakuzaFamilyWinner(raid.id, yakuzaFamilyWinner);
            //fill with fighters and get raid tickets
            (raidTickets, raid) = _assignRaidersToRaid(raid, uint8(yakuzaFamilyWinner));
            //loop through to get scores/determine winner
            scores = new uint256[](raidSize);
            for(uint n=0; n<raidSize; n++){
              if(TEST_PRINTS) console.log("+-------------------+");
              if(TEST_PRINTS) console.log("fighter id:",raidTickets[n].fighterId);

              //only do following rounds if survive yakuza intimidation round   
              if(!yakuzaRoundActive || raidTickets[n].yakuzaFamily > 0){

                //weapons round
                if(weaponsRoundActive){
                  //get weapons scores
                  (weaponsScore, raidTickets[n] )= _getWeaponsScore(raid, raidTickets[n]);
                } else weaponsScore = 0;

                //sweat round
                if(!sweatRoundActive){
                  raid.maxSweat = 1;
                  raidTickets[n].sweat = 0;                
                } 

                //if fighter has 0 scars
                if(raidTickets[n].scars == 0){
                  scarsScore = 0;
                } else {
                  //safety check to make sure no division by 0
                  if(raid.maxScars == 0) raid.maxScars = raidTickets[n].scars;
                  scarsScore = SCARS_WEIGHT * 100 * raidTickets[n].scars / raid.maxScars;
                }

                //calculate scores
                scores[n] = BRUTALITY_WEIGHT * raidTickets[n].fighterLevel * raidTickets[n].brutality/(i*3) + 
                WEAPONS_WEIGHT * weaponsScore  +
                SWEAT_WEIGHT * 100 * raidTickets[n].sweat / raid.maxSweat +
                scarsScore + 
                YAKUZA_INTIMIDATION_WEIGHT * raidTickets[n].yakuzaFamily;
              }
              
              //if lost in yakuza round set score to 0
              if(yakuzaRoundActive && raidTickets[n].yakuzaFamily == 0){
                scores[n] = 0;
              }
              if(TEST_PRINTS) console.log("score for fighter", scores[n]);

              raid.revenue += raidTickets[n].entryFee;
            }
            
            // sort raidTickets by score
            _quickSort(scores, raidTickets, int(0), int(raidTickets.length - 1));

            bool isYakShareStolen;
            (raidTickets,  isYakShareStolen) = _calculateRaiderRewards(scores, raidTickets, raid);
            emit YakuzaRaidShareStolen(raidTickets[0].fighterId, raid.id);
            //tally yakuza rewards
            if(!isYakShareStolen) _yakRewards += YAKUZA_BASE_CUT_PCT * raid.revenue / 100 ;

            //fight club owner
            if(raid.fightClubSize/5 == raid.sizeTier ){
              if((raid.fightClubLevel - 1)/3 + 1 == raid.levelTier){
                if(raid.fightClubLevel%3 == 1){
                  //fight club gets half rewards if just reached level
                  fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/200;
                   //dev cut
                  fightClubOwnerBloodRewards[devWallet] += 25*raid.revenue/100 -(FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/200;
                }
                if(raid.fightClubLevel%3 == 2){
                  //fight club gets 3/4 rewards if 1 level past minimum for tier
                  fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue*3/400;
                   //dev cut
                  fightClubOwnerBloodRewards[devWallet] += 25*raid.revenue/100 -(FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue*3/400;
                }
                if(raid.fightClubLevel%3 == 0){
                  //fight club gets full rewards if at max level for tier
                  fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/100;
                   //dev cut
                  fightClubOwnerBloodRewards[devWallet] += (25 - FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/100;
                }
              } else {
                //fight club gets full rewards if at max level for tier
                fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/100;
                  //dev cut
                fightClubOwnerBloodRewards[devWallet] += (25 - FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/100;
              }

            } else {//if fightclub sizetier is > raid size tier we ignore fightclub modulo
              if((raid.fightClubLevel - 1)/3 + 1 == raid.levelTier){
                if(raid.fightClubLevel%3 == 1){
                  //fight club gets half rewards if just reached level
                  fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*4)*raid.revenue/200;
                   //dev cut
                  fightClubOwnerBloodRewards[devWallet] += 25*raid.revenue/100 -(FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue/200;
                }
                if(raid.fightClubLevel%3 == 2){
                  //fight club gets 3/4 rewards if 1 level past minimum for tier
                  fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*4)*raid.revenue*3/400;
                   //dev cut
                  fightClubOwnerBloodRewards[devWallet] += 25*raid.revenue/100 -(FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*(raid.fightClubSize%5))*raid.revenue*3/400;
                }
                if(raid.fightClubLevel%3 == 0){
                  //fight club gets full rewards if at max level for tier
                  fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*4)*raid.revenue/100;
                }
              } else {
                //fight club gets full rewards if at max level for tier
                fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] += (FIGHT_CLUB_BASE_CUT_PCT + FIGHT_CLUB_BASE_CUT_PCT*4)*raid.revenue/100;
              }
            }

            //referee rewards
            refRewards += REFEREE_BASE_CUT_PCT * raid.revenue / 100 ;

            //bloodburn DONT NEED TO ACTUALLY BURN BLOOD BECAUSE IT WAS BURNED WHEN ENTRY FEE WAS PAID
            
            //emit events
            emit RaidResults(raid.id, raidTickets, scores);

            //TEST PRINTS
            if(TEST_PRINTS){
              console.log("fclub owner ", stakedFightclubOwners[raid.fightClubId]);
              console.log("fclub owner cut", fightClubOwnerBloodRewards[stakedFightclubOwners[raid.fightClubId]] );
              console.log("dev cut", fightClubOwnerBloodRewards[devWallet] );
              console.log("fclub id", raid.fightClubId);
              console.log("+-------+");
              console.log("Rankings Raid ID",raid.id);
              
              for(uint o; o<raidTickets.length;o++){
                console.log("+---+");
                console.log("place",o+1);
                console.log("score",scores[o]);
                console.log("fighter",raidTickets[o].fighterId);
                if(scores[o] > 0) {
                  console.log("scars earned",o+1);
                  console.log("new scars for fighter",raidTickets[o].scars);
                }
                  else console.log("scars earned",0);
              }
              console.log("+-------------------------+");
            }             
          }            
        }
      }
    }
    ugArena.payRaidRevenueToYakuza( _yakRewards);
    console.log("yakrewards",_yakRewards);
    //send ref rewards
    uBlood.mint(_msgSender(),refRewards * 1 ether);

    emit RefereeRewardsPaid(_msgSender(), refRewards);
    emit YakuzaTaxPaidFromRaids(_yakRewards, block.timestamp);
  }

  uint256 TEST_PRINTS = true;

  function getYakuzaRoundScore(uint8 yakuzaFamily, uint256 rand) private pure returns (uint8 _yakScore){
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

  function isBrokenWeapon(uint256 attackScore, uint256 seed) private pure returns(bool isBroken){
    //get metal
    if (attackScore == 10){
      if ((seed <<= 8)%100 > 100 - STEEL_DURABILITY_SCORE) return false; 
      else return true;
    }
    if (attackScore == 20){
      if ((seed <<= 8)%100 > 100 - BRONZE_DURABILITY_SCORE) return false; 
      else return true;
    }
    if (attackScore == 30){
      if ((seed <<= 8)%100 > 100 - GOLD_DURABILITY_SCORE) return false; 
      else return true;
    }
    if (attackScore == 50){
      if ((seed <<= 8)%100 > 100 - PLATINUM_DURABILITY_SCORE) return false; 
      else return true;
    }
    if (attackScore == 75){
      if ((seed <<= 8)%100 > 100 - TITANIUM_DURABILITY_SCORE) return false; 
      else return true;
    }
    if (attackScore == 100){
      return false; 
    }
  }

  function _getWeaponsScore(Raid memory raid, RaidEntryTicket memory ticket) private view returns (uint256 weaponsScore, RaidEntryTicket memory){
      uint256 _maxWeapons;
      //check if weapon breaks
      uint256[] memory seeds = getSeeds(raid.maxScars, ticket.fighterId, 5);
      //calculate weapons score
      if(raid.levelTier >= KNUCKLES_TIER) {
        _maxWeapons++;
        //if fighter is equipped with an unbroken weapon
        if (ticket.knuckles > 0 && ticket.knuckles%5 == 0){
          if(!isBrokenWeapon(ticket.knuckles,  seeds[0])){
            weaponsScore += ticket.knuckles;
          } else {//weapon breaks
            if(TEST_PRINTS) console.log("knuckles broken, score:",ticket.knuckles);
            //set new score to 1 if broken -  memory instance will record to storage after raid calcs are made
            ticket.knuckles += 1;
          }
        }
        
      }
      if(raid.levelTier >= CHAINS_TIER){
        _maxWeapons++;
         //if fighter is equipped
        if (ticket.chains > 0 && ticket.chains%5 == 0){
          if(!isBrokenWeapon(ticket.chains,  seeds[1])){
            weaponsScore += ticket.chains;
          } else {//weapon breaks
            if(TEST_PRINTS) console.log("chains broken, score:",ticket.chains);
            ticket.chains += 1;
          }
        }
      } 
      if(raid.levelTier >= SWITCHBLADE_TIER){
        _maxWeapons++;
         //if fighter is equipped
        if (ticket.switchblade > 0 && ticket.switchblade%5 == 0){
          if(!isBrokenWeapon(ticket.switchblade,  seeds[2])){
            weaponsScore += ticket.switchblade;
          } else {//weapon breaks
            if(TEST_PRINTS) console.log("switchblade broken, score:",ticket.switchblade);
            ticket.switchblade += 1;
          }
        }
      } 
      if(raid.levelTier >= MACHETE_TIER){
        _maxWeapons++;
         //if fighter is equipped
        if (ticket.machete > 0 && ticket.machete%5 == 0){
          if(!isBrokenWeapon(ticket.machete,  seeds[3])){
            weaponsScore += ticket.machete;
          } else {//weapon breaks
            if(TEST_PRINTS) console.log("machete broken, score:",ticket.machete);
            ticket.machete += 1;
          }
        }
      } 
      if(raid.levelTier >= KATANA_TIER){
        _maxWeapons++;
         //if fighter is equipped
        if (ticket.katana > 0 && ticket.katana%5 == 0){
          if(!isBrokenWeapon(ticket.katana,  seeds[4])){
            weaponsScore += ticket.katana;
          } else {//weapon breaks
          if(TEST_PRINTS) console.log("katana broken, score:",ticket.katana);
            ticket.katana += 1;
          }
        }
      } 
      weaponsScore = _maxWeapons > 0 ? weaponsScore / _maxWeapons : weaponsScore;

      return (weaponsScore, ticket);
  }

  function _calculateRaiderRewards(uint256[] memory scores, RaidEntryTicket[] memory raidTickets, Raid memory raid) private returns (RaidEntryTicket[] memory, bool yakShareStolen) {
    address raiderOwner;
    //collect stats to permanently upgrade fighters
    //IUGNFTs.RaidStats[] memory raidStats = new IUGNFTs.RaidStats[](raidTickets.length);
    uint256[] memory raidStatsPacked = new uint256[](raidTickets.length);
    //assign resulting scars and weapons scores to fighters and pay out blood rewards
    for(uint o; o<raidTickets.length;o++){
      raiderOwner = ugArena.getStakeOwner(raidTickets[o].fighterId);
      //1st
      if(o == 0){
        if(TEST_PRINTS) console.log("+------------+");
        if(TEST_PRINTS) console.log("1st cunning score", raidTickets[o].cunning);

        //1st place blood reward is raid revenue * 1st place base pct + size tier
        raidTickets[o].winnings = raid.revenue * (24 + raid.sizeTier) / 100;

        //cunning gives cunning/2 pct chance of taking yakuza cut
        if(getSeeds(ttlRaids, raidTickets[o].fighterId, 1)[0]%100 <= raidTickets[o].cunning/2){
          raidTickets[o].winnings += uint32(raid.revenue * YAKUZA_BASE_CUT_PCT / 100);
          yakShareStolen = true;
          if(TEST_PRINTS) console.log("is YakShareStolen", yakShareStolen);
        }
        
        if(TEST_PRINTS) console.log("1st winnings", raidTickets[o].winnings);
        if(TEST_PRINTS) console.log("entry fee", raidTickets[o].entryFee);
        //weapon rewards (if over a certain size tier)
        if(raid.sizeTier > 2) {
          if(raid.levelTier >= KNUCKLES_TIER && raid.levelTier < CHAINS_TIER)
             weaponsToMint[raiderOwner][0][25*(raid.sizeTier-1)]++;
          if(raid.levelTier >= CHAINS_TIER && raid.levelTier < SWITCHBLADE_TIER)
             weaponsToMint[raiderOwner][1][25*(raid.sizeTier-1)]++;
          if(raid.levelTier >= SWITCHBLADE_TIER && raid.levelTier < MACHETE_TIER)
             weaponsToMint[raiderOwner][2][25*(raid.sizeTier-1)]++;
          if(raid.levelTier >= MACHETE_TIER && raid.levelTier < KATANA_TIER)
             weaponsToMint[raiderOwner][3][25*(raid.sizeTier-1)]++;
          if(raid.levelTier >= KATANA_TIER)
             weaponsToMint[raiderOwner][4][25*(raid.sizeTier-1)]++;
        }
        if(raid.sizeTier == 2) {
          if(raid.levelTier >= KNUCKLES_TIER && raid.levelTier < CHAINS_TIER)
             weaponsToMint[raiderOwner][0][30]++;
          if(raid.levelTier >= CHAINS_TIER && raid.levelTier < SWITCHBLADE_TIER)
             weaponsToMint[raiderOwner][1][30]++;
          if(raid.levelTier >= SWITCHBLADE_TIER && raid.levelTier < MACHETE_TIER)
             weaponsToMint[raiderOwner][2][30]++;
          if(raid.levelTier >= MACHETE_TIER && raid.levelTier < KATANA_TIER)
             weaponsToMint[raiderOwner][3][30]++;
          if(raid.levelTier >= KATANA_TIER)
             weaponsToMint[raiderOwner][4][30]++;
        }
      }
      //2nd
      if(o == 1){
        //2nd place blood reward is raid revenue * 2nd place base pct - size tier
        raidTickets[o].winnings = raid.revenue * (16 - raidTickets[o].sizeTier) / 100;

        if(TEST_PRINTS) console.log("2nd winnings", raidTickets[o].winnings);        
        if(TEST_PRINTS) console.log("entry fee", raidTickets[o].entryFee);
        //weapon rewards (if over a certain size tier)
        if(raid.sizeTier > 3) {
          if(raid.levelTier >= KNUCKLES_TIER && raid.levelTier < CHAINS_TIER)
             weaponsToMint[raiderOwner][0][50]++;
          if(raid.levelTier >= CHAINS_TIER && raid.levelTier < SWITCHBLADE_TIER)
             weaponsToMint[raiderOwner][1][50]++;
          if(raid.levelTier >= SWITCHBLADE_TIER && raid.levelTier < MACHETE_TIER)
             weaponsToMint[raiderOwner][2][50]++;
          if(raid.levelTier >= MACHETE_TIER && raid.levelTier < KATANA_TIER)
             weaponsToMint[raiderOwner][3][50]++;
          if(raid.levelTier >= KATANA_TIER)
             weaponsToMint[raiderOwner][4][50]++;
        }
      }
      //3rd
      if(o == 2){
        //3rd place blood reward is raid revenue * 3rd place base pct
        raidTickets[o].winnings = raid.revenue * 5 / 100;

        if(TEST_PRINTS) console.log("3rd winnings", raidTickets[o].winnings);
        if(TEST_PRINTS) console.log("entry fee", raidTickets[o].entryFee);
        //weapon rewards (if over a certain size tier)
        if(raid.sizeTier > 3) {
          if(raid.levelTier >= KNUCKLES_TIER && raid.levelTier < CHAINS_TIER)
             weaponsToMint[raiderOwner][0][20]++;
          if(raid.levelTier >= CHAINS_TIER && raid.levelTier < SWITCHBLADE_TIER)
             weaponsToMint[raiderOwner][1][20]++;
          if(raid.levelTier >= SWITCHBLADE_TIER && raid.levelTier < MACHETE_TIER)
             weaponsToMint[raiderOwner][2][20]++;
          if(raid.levelTier >= MACHETE_TIER && raid.levelTier < KATANA_TIER)
             weaponsToMint[raiderOwner][3][20]++;
          if(raid.levelTier >= KATANA_TIER)
             weaponsToMint[raiderOwner][4][20]++;
        }
      }
      //4th
      if(o == 3){
        //4th place blood reward is raid revenue * 4th place base pct
        if(raidTickets[o].sizeTier > 1) raidTickets[o].winnings = raid.revenue * 3 / 100;
        if(TEST_PRINTS) console.log("4th winnings", raidTickets[o].winnings);
        if(TEST_PRINTS) console.log("entry fee", raidTickets[o].entryFee);
      }
      //5th
      if(o == 4){
        //5th place blood reward is raid revenue * 5th place base pct
        if(raidTickets[o].sizeTier > 3) raidTickets[o].winnings = raid.revenue * 2 / 100;
        if(TEST_PRINTS) console.log("5th winnings", raidTickets[o].winnings);
        if(TEST_PRINTS) console.log("entry fee", raidTickets[o].entryFee);
      }

      //scars if not kicked out of yakuzaa round
      if (scores[o] > 0) raidTickets[o].scars += uint16(o + 1);

      //WRITE RESULTS PERMANENTLY TO FIGHTERS
      //--------------------------------
      IUGNFTs.RaidStats memory raidStat;
      raidStat.knuckles = raidTickets[o].knuckles;
      raidStat.chains = raidTickets[o].chains;
      raidStat.switchblade = raidTickets[o].switchblade;
      raidStat.machete = raidTickets[o].machete;
      raidStat.katana = raidTickets[o].katana;
      raidStat.scars = raidTickets[o].scars;
      raidStat.fighterId = raidTickets[o].fighterId;
     // raidStats[o] = raidStat;  
      raidStatsPacked[o] = packTicket(raidTickets[o]);

      //pay out blood rewards
      raiderOwnerBloodRewards[raiderOwner] += raidTickets[o].winnings;
    }
    //write to fighters
    //ugNFT.setRaidTraits( raidStats);
    ugNFT.setRaidTraitsFromPacked( raidStatsPacked);
    return (raidTickets, yakShareStolen);
  }

  function claimRaiderBloodRewards() external nonReentrant {
    uint256 payout =  raiderOwnerBloodRewards[_msgSender()];
    delete raiderOwnerBloodRewards[_msgSender()];
    uBlood.mint(_msgSender(), payout * 1 ether);
  }

  function claimFightClubBloodRewards() external nonReentrant {
    uint256 payout =  fightClubOwnerBloodRewards[_msgSender()];
    delete fightClubOwnerBloodRewards[_msgSender()];
    uBlood.mint(_msgSender(), payout * 1 ether);
  }

  function viewRaiderOwnerBloodRewards(address user) external view returns (uint256) {
    return  raiderOwnerBloodRewards[user];
  }

  function viewFightClubOwnerBloodRewards(address user) external view returns (uint256) {
    return fightClubOwnerBloodRewards[user];
    
  }

  function _assignRaidersToRaid(Raid memory raid, uint8 yakuzaFamilyWinner) private returns (RaidEntryTicket[] memory, Raid memory) {
    uint256 _raidSize = raid.sizeTier * 5;
    RaidEntryTicket[] memory tickets = new RaidEntryTicket[](_raidSize);
    uint8 _yakScore;

    for(uint i; i < _raidSize; i++){
     tickets[i] = getTicketInQueue(raid.levelTier,raid.sizeTier);
      //mark that fighter has been removed from que if it hasnt already been marked as removed
      if(_viewIfRaiderIsInQueue(tickets[i].fighterId) == 1) _updateIfRaiderIsInQueue(tickets[i].fighterId, Operations.Sub);
      if(yakuzaRoundActive){
        if(TEST_PRINTS) console.log("+-----+");
        if(TEST_PRINTS) console.log("fighter id:",tickets[i].fighterId);
        //returns 0 if lost yakuza intimidation round, 1 if survived, 100 if gets boost
        _yakScore = getYakuzaRoundScore(tickets[i].yakuzaFamily, yakuzaFamilyWinner);
        if(_yakScore ==0){
          if(TEST_PRINTS) console.log("lost yakuza intimidation Round, courage check...");
          uint roll = getSeeds(raid.id, tickets[i].fighterId, 1)[0]%100;
          if(roll < tickets[i].courage ) _yakScore = 1;
          if(TEST_PRINTS) if(_yakScore == 0) {
            console.log("...courage check failed");
            console.log("courage score",tickets[i].courage);
            console.log("rolled a",roll);
          }
        }
        //TEST PRINTS
        if(TEST_PRINTS){
          if(_yakScore == 1) console.log("survives yakuza round");
          if(_yakScore == 100) console.log("gets boost in yakuza round!");
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
    uint256 queuelength = _getQueueLength(fightClubQueue[levelTier][_raidSizeTier]);
    uint256 fclubId;
    
    //loop through fight clubs to find next eligible
    for(uint i; i < queuelength; i++){
      //packed id with size 
      fclubId = getFightClubInQueueAndRecycle( levelTier, _raidSizeTier) ;
      raid.fightClubSize = uint8(fclubId>>11);
      fclubId = fclubId%2 ** 11;
      //if we find an elible one, break out of for loop
      if(fclubId > 0) break;
    }

    //if no eligible fight clubs are in queue
    if(fclubId == 0) {
      //get house/dev fight club to hold raid
      fclubId = devFightClubId - FIGHT_CLUB;
    }
    
    raid.levelTier = levelTier;
    raid.sizeTier = _raidSizeTier; 
    raid.id = uint32(++ttlRaids);
    raid.fightClubId = uint16(fclubId + FIGHT_CLUB);
    raid.timestamp = uint32(block.timestamp);
    raid.fightClubLevel = ugNFT.getForgeFightClub(raid.fightClubId).level;

    emit RaidCreated(raid.id, raid);
  
    return raid;
  }

   //returns 0 if token is no longer eligible for que (did not level up/ maintain or not staked)
  function getFightClubInQueueAndRecycle( uint256 _levelTier, uint256 _raidSizeTier) private returns (uint256) {
    //get packed value: id with fightclub size
    uint256 id = removeFromQueue(fightClubQueue[_levelTier][_raidSizeTier], IDS_BITS_SIZE);
    uint256 unpackedId = id%2 ** 11;
    //do not re-enter queue if has been unstaked since getting in queue
    if(stakedFightclubOwners[unpackedId + FIGHT_CLUB] == address(0)) return 0;
    IUGNFTs.ForgeFightClub memory fightclub = ugNFT.getForgeFightClub(unpackedId + FIGHT_CLUB);
    //and is right level and size, do not re-enter queue if fails this check
    if(fightclub.size/5 < _raidSizeTier || (fightclub.level -1 )/3 + 1 < _levelTier) return 0;
    //if fight club has not been leveled up at least once in last week + 1 day auto unstake fightclub
    if(fightclub.lastLevelUpgradeTime + 8 days < block.timestamp) {
      //auto unstake if hasnt been already
      _autoUnstakeFightClub(unpackedId + FIGHT_CLUB);
      return 0;
    }

    //add back to queue with current size
    unpackedId |= fightclub.size<<11;
    addToQueue(fightClubQueue[_levelTier][_raidSizeTier], unpackedId, IDS_BITS_SIZE);
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
      if(ticket.fighterId > 0 && ierc1155.balanceOf(address(ugArena),ticket.fighterId) == 1) return ticket;
    }
    //if we fail to find one send an empty
    ticket = RaidEntryTicket(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    return ticket;
  }

  function getRaiderIdFromFighterId(uint256 fighterId) private pure returns (uint16 raiderId){
    raiderId = uint16(fighterId - FIGHTER);
  }

  function getFighterIdFromRaiderId(uint256 raiderId) private pure returns (uint32 fighterId){
    fighterId = uint32(raiderId + FIGHTER);
  }

  //player function for entering Raids, enter fighter id, size raid to enter, sweat to allocate, yakuza pick
    function enterRaid(uint256[] calldata tokenIds, RaiderEntry[] calldata raiderEntries) external onlyEOA nonReentrant returns(uint256 ttlBloodEntryFee){
        uint256 ttlSweat;
        uint256 bloodEntryFee;
        //make sure tokens staked in arena by sender
        if(!ugArena.verifyAllStakedByUser(_msgSender(), tokenIds)) revert InvalidTokenId();
        if(tokenIds.length != raiderEntries.length) revert MismatchArrays();
        
        //get fighters
        uint256[] memory packedFighters = ugNFT.getPackedFighters(tokenIds);
        uint256[] memory packedTickets = new uint256[](packedFighters.length);
        for(uint i; i<packedFighters.length;i++){
            //make sure its a fighter not yakuza
            if(!unPackFighter(packedFighters[i]).isFighter) continue;
            //make sure raider not already in queue
            if(_viewIfRaiderIsInQueue(tokenIds[i]) == 1) revert AlreadyInQueue();
            ttlSweat += raiderEntries[i].sweat;
            if(raiderEntries[i].size/5 == 0) revert InvalidSize({size: raiderEntries[i].size, sweat: raiderEntries[i].sweat, yak: raiderEntries[i].yakFamily, i: i });
            (packedTickets[i], bloodEntryFee) = packTicketForEntry(unPackFighter(packedFighters[i]), raiderEntries[i].size/5, raiderEntries[i].sweat, tokenIds[i], raiderEntries[i].yakFamily);
            _updateIfRaiderIsInQueue(tokenIds[i], Operations.Add);
            ttlBloodEntryFee += bloodEntryFee;
        }
       
        //burn blood entry fee
        burnBlood(_msgSender(), ttlBloodEntryFee);

        //add raid tickets to Raid Que
        addTicketsToRaiderQueue(packedTickets);
    }

    function packTicketForEntry(
        IUGNFTs.FighterYakuza memory fighter, 
        uint256 sizeTier, 
        uint256 sweat, 
        uint256 tokenId,
        uint256 yakFamily
    ) private view returns (uint256, uint256 bloodEntryFee){
        uint256 ticket = sizeTier;
        uint256 nextVal = fighter.level;
        ticket |= nextVal<<8;
        nextVal = yakFamily;
        ticket |= nextVal<<16;
        nextVal = fighter.courage;
        ticket |= nextVal<<24;
        nextVal =  fighter.brutality;
        ticket |= nextVal<<32;
        nextVal =  fighter.cunning;
        ticket |= nextVal<<40;
        nextVal =  fighter.knuckles;
        ticket |= nextVal<<48;
        nextVal =  fighter.chains;
        ticket |= nextVal<<56;
        nextVal =  fighter.switchblade;
        ticket |= nextVal<<64;
        nextVal =  fighter.machete;
        ticket |= nextVal<<72;
        nextVal =  fighter.katana;
        ticket |= nextVal<<80;
        nextVal =  fighter.scars;
        ticket |= nextVal<<96;
        nextVal = sweat;
        ticket |= nextVal<<128;
        //fighterId
        nextVal = tokenId;
        ticket |= nextVal<<160;
        //entryFee
        nextVal = getRaidCost((fighter.level - 1) /3 + 1,  sizeTier);
        bloodEntryFee = nextVal;
        ticket |= nextVal<<192;

        return (ticket, bloodEntryFee) ;
  }

  function unPackFighter(uint256 packedFighter) private pure returns (IUGNFTs.FighterYakuza memory) {
    IUGNFTs.FighterYakuza memory fighter;   
    fighter.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
    fighter.isGen0 = uint8(packedFighter>>1)%2 == 1 ? true : false;
    fighter.level = uint8(packedFighter>>2);
    fighter.rank = uint8(packedFighter>>10);
    fighter.courage = uint8(packedFighter>>18);
    fighter.cunning = uint8(packedFighter>>26);
    fighter.brutality = uint8(packedFighter>>34);
    fighter.knuckles = uint8(packedFighter>>42);
    fighter.chains = uint8(packedFighter>>50);
    fighter.switchblade = uint8(packedFighter>>58);
    fighter.machete = uint8(packedFighter>>66);
    fighter.katana = uint8(packedFighter>>74);
    fighter.scars = uint16(packedFighter>>90);
    fighter.imageId = uint16(packedFighter>>106);
    fighter.lastLevelUpgradeTime = uint32(packedFighter>>138);
    fighter.lastRankUpgradeTime = uint32(packedFighter>>170);
    fighter.lastRaidTime = uint32(packedFighter>>202);
    
    return fighter;
  }

  function addTicketsToRaiderQueue(uint256[] memory packedTickets) private {
    uint256 levelTier;
    for(uint i; i < packedTickets.length; i++){
      levelTier = getLevelTier(uint8(packedTickets[i]>>8));
      //add to queue and convert fighterid to raider id to use a smaller storage slot
      addToQueueFullUint(RaiderQueue[levelTier][uint8(packedTickets[i])], packedTickets[i]);
      maxRaiderQueueLevelTier = levelTier  > maxRaiderQueueLevelTier ? levelTier  : maxRaiderQueueLevelTier;    
    }
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
      nextVal = _ticket.switchblade;
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
      _ticket.switchblade = uint8(packedTicket>>64);
      _ticket.machete = uint8(packedTicket>>72);
      _ticket.katana = uint8(packedTicket>>80);
      _ticket.scars = uint16(packedTicket>>96);
      _ticket.sweat = uint32(packedTicket>>128);
      _ticket.fighterId = uint32(packedTicket>>160);
      _ticket.entryFee = uint32(packedTicket>>192);
      return _ticket;
  }
  
  //might not be able to send the struct unless admin only can call, might have to make an external call to get the fightclubs
  function stakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
     IUGNFTs.ForgeFightClub[] memory fightclubs = ugNFT.getForgeFightClubs(tokenIds);
    if(tokenIds.length != fightclubs.length) revert MismatchArrays();
    //make sure is owned by sender
    if(!ugNFT.checkUserBatchBalance(_msgSender(), tokenIds)) revert InvalidTokenId();    
   
    _stakeFightclubs(_msgSender(), tokenIds, fightclubs);
  }

  function _stakeFightclubs(address account, uint256[] calldata tokenIds, IUGNFTs.ForgeFightClub[] memory fightclubs) private whenNotPaused {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    for(uint i; i < tokenIds.length; i++){
      //make sure it has been unstaked for 48 hours to clear the fightclub que 
      //so fclub owner cant game by continually staking and unstaking
      if(fightclubs[i].lastUnstakeTime > 0 && fightclubs[i].lastUnstakeTime + UNSTAKE_COOLDOWN > block.timestamp) revert StillUnstakeCoolDown();
      
    //  _updateIDStakedBalance(account, tokenIds[i], 1, Operations.Add);
      stakedFightclubOwners[tokenIds[i]] = account;
      amounts[i] = 1;
      //add fightclub to queue, use (1 , 1) for (startSizeTier, startlevelTier)
       _addFightClubToQueues(tokenIds[i], 1, 1, fightclubs[i]);
       //set unstake time to 0
      ugNFT.setFightClubUnstakeTime(tokenIds[i], false);
    }
    _totalFightClubsStaked += tokenIds.length;
    ownerTotalStakedFightClubs[account] += tokenIds.length;

    ierc1155.safeBatchTransferFrom(account, address(this), tokenIds, amounts, "");
    //emit TokenStaked(account, tokenId);
  }

  function addFightClubToQueueAfterLevelSizeUp(
    uint256 tokenId, 
    uint8 sizeTiersToUpgrade, 
    uint8 levelTiersToUpgrade, 
    IUGNFTs.ForgeFightClub calldata fightclub
  ) external onlyAdmin nonReentrant {

    if(levelTiersToUpgrade > 0){
      _addFightClubToQueues(tokenId,  1,  getLevelTier(fightclub.level) - levelTiersToUpgrade + 1, fightclub);
    }

    if(sizeTiersToUpgrade > 0){
      _addFightClubToQueues(tokenId,  getSizeTier(fightclub.size) - sizeTiersToUpgrade + 1,  1, fightclub);
    }
  }

  function _addFightClubToQueues(uint256 tokenId, uint8 startSizeTier, uint8 startLevelTier, IUGNFTs.ForgeFightClub memory fightclub) private {
    //check to see fight club has been leveled up at least once in last week
    if(fightclub.lastLevelUpgradeTime + 7 days > block.timestamp) 
    {
      uint8 maxLevelTier = getLevelTier(fightclub.level);  
      uint8 maxSizeTier = getSizeTier(fightclub.size); 
      //pack this uint with token id and fightclub size so we can calculate fightclub share later
      //max fightclub id is 2000 so only 11 bits needed
      uint packedValue = tokenId - FIGHT_CLUB;
      uint size = fightclub.size;
      packedValue |= size<<11;
      for(uint8 j=startLevelTier; j <= maxLevelTier; j++){
        for(uint8 k=startSizeTier; k <= maxSizeTier; k++){
          addToQueue(fightClubQueue[j][k], packedValue, IDS_BITS_SIZE);
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
    //_updateIDStakedBalance(account, tokenId, 1, Operations.Sub);
    _totalFightClubsStaked--;
    ownerTotalStakedFightClubs[account]--;
    ierc1155.safeTransferFrom(address(this), account, tokenId, 1, "");
  }

  function unstakeFightclubs(uint256[] calldata tokenIds) external nonReentrant {
    uint256[] memory amounts = new uint256[](tokenIds.length);
    for(uint i; i < tokenIds.length;i++){
      //make sure sender is ringowner
      if(stakedFightclubOwners[tokenIds[i]] != _msgSender()) revert InvalidTokens({tokenId: tokenIds[i]});
      //Update unstake time
      ugNFT.setFightClubUnstakeTime(tokenIds[i], true);
     // _updateIDStakedBalance(_msgSender(), tokenIds[i], 1, Operations.Sub);
      delete stakedFightclubOwners[tokenIds[i]];
      amounts[i] = 1;
    }

    _totalFightClubsStaked -= tokenIds.length;
    ownerTotalStakedFightClubs[_msgSender()] -= tokenIds.length;

    ierc1155.safeBatchTransferFrom(address(this), _msgSender(), tokenIds, amounts, "");
    //emit TokenUnStaked(_msgSender(), tokenIds);
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

  function getSizeTier(uint8 size) private pure returns (uint8) {
    return size/5;
  }

  //levelTiers 1 = (1-3), 2 = (4-6), 3 = (7-9), maxLevel at each tier = levelTier * 3
  function getLevelTier(uint8 level) private pure returns (uint8) {
    if(level == 0) return 0;
    return (level-1)/3 + 1;
  }
  
  function getRaidCost(uint256 levelTier, uint256 sizeTier) public view returns (uint256 price) {
      return (BASE_RAID_FEE * (2 + sizeTier-1) * levelTier * 3);
  }

  function getRaiderQueueLength(uint8 level, uint8 sizeTier) public view returns (uint8){
   return _getQueueLength(RaiderQueue[level][sizeTier]);
  }

  function _getQueueLength(Queue storage queue) private view returns (uint8){
    return uint8(queue.end - queue.start);
  }

   function getFightClubIdInQueuePosition(uint8 levelTier, uint8 sizeTier, uint pos) public view returns (uint256){
    uint256 fclubId = getIdFromQueuePosition(fightClubQueue[levelTier][sizeTier], IDS_BITS_SIZE, pos);
    fclubId = fclubId%2 ** 11;
    return fclubId + FIGHT_CLUB;
  }

  function getRaiderIdInQueuePosition(uint8 levelTier, uint8 sizeTier, uint pos) public view returns (uint256){
    uint256 raiderId = getIdFromQueuePosition(RaiderQueue[levelTier][sizeTier], IDS_BITS_SIZE, pos);
    return raiderId;
  }

  function burnBlood(address account, uint256 amount) private {
    uBlood.burn(account , amount * 1 ether);
    //allocate 10% of all burned blood to dev wallet for continued development
    uBlood.mint(devWallet, amount * 1 ether /10);
  }

  //gets id without removing from queue -- pos is position from next in line, 0=next in line, 1 = second in line
  function getIdFromQueuePosition(Queue storage queue, uint256 bitSize, uint256 pos) private view returns (uint256) {
    //check for end of queue
    if(queue.start + pos > queue.end) return 0;
    
    uint256 bin;
    uint256 index;

    // Get bin and index
    (bin, index) = getIDBinIndex(queue.start + pos);
    
    return getValueInBin(queue.ids[bin], bitSize, index);
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

  function getSeeds(uint256 rand1, uint256 rand2, uint256 numRands) private view returns (uint256[] memory) {
      uint256[] memory randNums = new uint256[](numRands);
      for(uint i; i < numRands; i++){
        randNums[i] = uint256(
                        keccak256(
                            abi.encodePacked(
                                // solhint-disable-next-line
                                block.timestamp,
                                msg.sender,
                                blockhash(block.number-1),
                                rand1+i,
                                rand2+i
                            )
                        )
        );
      }
    return randNums;
  }

  /** OWNER ONLY FUNCTIONS */

  function setContracts(/*address _ugGame, */address _ugArena, address _ugNFT, address _uBlood/*,address _uGold*/) external onlyOwner {
    ugNFT = IUGNFTs(_ugNFT);
    uBlood = IUBlood(_uBlood);
    ugArena = IUGArena(_ugArena);
  }

  function setUnstakeCoolDownPeriod(uint amount) external onlyOwner {
    UNSTAKE_COOLDOWN = amount;
  }

  function addAdmin(address addr) external onlyOwner {
    _admins[addr] = true;
  }

  function removeAdmin(address addr) external onlyOwner {
    delete _admins[addr];
  }

  function setWeaponsRound(bool active) external onlyOwner {
    if(active) weaponsRoundActive = true;
    else weaponsRoundActive = false;
  }

  function setYakuzaRound(bool active) external onlyOwner {
    if(active) yakuzaRoundActive = true;
    else yakuzaRoundActive = false;
  }
  
  function setSweatRound(bool active) external onlyOwner {
    if(active) sweatRoundActive = true;
    else sweatRoundActive = false;
  }

  function setDevWallet(address newWallet) external onlyOwner {
    if(newWallet == address(0)) revert InvalidAddress();
    stakedFightclubOwners[devFightClubId] = newWallet;
    devWallet = newWallet;
  }

  function setDevFightClubId(uint256 id) external onlyOwner {
    address _devWallet = stakedFightclubOwners[devFightClubId];
    delete stakedFightclubOwners[devFightClubId];
    stakedFightclubOwners[id] = _devWallet;
    devFightClubId = id;
  }

  function setKnucklesTier(uint8 newTier) external onlyOwner {
    KNUCKLES_TIER = newTier;
  }

  function setChainsTier(uint8 newTier) external onlyOwner {
    CHAINS_TIER = newTier;
  }

  function setSwitchBladeTier(uint8 newTier) external onlyOwner {
    SWITCHBLADE_TIER = newTier;
  }

  function setMacheteTier(uint8 newTier) external onlyOwner {
    MACHETE_TIER = newTier;
  }

  function setKatanaTier(uint8 newTier) external onlyOwner {
    KATANA_TIER = newTier;
  }

  function setBrutalityWeight(uint256 newWeight) external onlyOwner {
    BRUTALITY_WEIGHT = newWeight;
  }

  function setScarsWeight(uint256 newWeight) external onlyOwner {
    SCARS_WEIGHT = newWeight;
  }

  function setSweatWeight(uint256 newWeight) external onlyOwner {
    SWEAT_WEIGHT = newWeight;
  }

  function setWeaponsWeight(uint256 newWeight) external onlyOwner {
    WEAPONS_WEIGHT = newWeight;
  }

  function setYakuzaIntWeight(uint256 newWeight) external onlyOwner {
    YAKUZA_INTIMIDATION_WEIGHT = newWeight;
  }

  function setFightClubBasePct(uint256 pct) external onlyOwner {
    FIGHT_CLUB_BASE_CUT_PCT = pct;
  }

  function setUnstakeCooldownPeriod(uint256 period) external onlyOwner {
    UNSTAKE_COOLDOWN = period;
  }

  function setYakuzaBasePct(uint256 pct) external onlyOwner {
    YAKUZA_BASE_CUT_PCT = pct;
  }

  function setRefereeBasePct(uint256 pct) external onlyOwner {
    REFEREE_BASE_CUT_PCT = pct;
  }
  
  function setBaseRaidFee(uint256 newBaseFee) external onlyOwner {
    require(newBaseFee >0);
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

  function _viewIfRaiderIsInQueue( uint256 tokenId) internal view returns(uint256) {
    uint id = tokenId;
    // Get bin and index of _id
    uint256 bin = id / 256;
    uint256 index = id % 256;
    // return balance
    return getValueInBin(raiderInQue[bin], 1, index);
  }

  function _updateIfRaiderIsInQueue( uint256 tokenId, Operations _operation) internal view returns(uint256) {
    uint id = tokenId;
    // Get bin and index of _id
    uint256 bin = id / 256;
    uint256 index = id % 256;
    // return balance
    return _viewUpdateBinValue(raiderInQue[bin], 1, index, 1, _operation);
  }

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