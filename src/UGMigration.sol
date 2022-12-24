// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "./ERC1155/utils/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IUGNFTs.sol";
import "./interfaces/IUGNFT.sol";
import "./interfaces/IUGFYakuza.sol";
import "./interfaces/IUBlood.sol";
import "./interfaces/IUGArena.sol";
import "./interfaces/IUGRaid.sol";


interface IUArena {
  struct Stake {
    uint256 tokenId;
    uint256 bloodPerRank;
    uint256 stakeTimestamp;
    address owner;
  }
  function getStake(uint256 tokenId) external view returns (Stake memory);
}

interface IUGame {
  function getFyTokenTraits(uint256 tokenId) external view returns (IUNFT.FighterYakuza memory);
}

interface IUNFT is IERC721Enumerable {
    struct FighterYakuza {
        bool isRevealed;
        bool isFighter;
        bool isGen0;
        uint16 level;
        uint256 lastLevelUpgradeTime;
        uint8 rank;
        uint256 lastRankUpgradeTime;
        uint8 courage;
        uint8 cunning;
        uint8 brutality;
        uint64 mintedBlockNumber;
    }
    function burn(uint256 tokenId) external; // onlyAdmin
    function getTokenTraits(uint256 tokenId) external view returns (FighterYakuza memory); // onlyAdmin  
}

interface IURing is IERC721Enumerable {
  struct Ring {
      uint256 mintedTimestamp;
      uint256 mintedBlockNumber;
      uint256 lastTransferTimestamp;
  }
  function burn(uint256 tokenId) external; // onlyAdmin
  function getTokenTraits(uint256 tokenId) external view returns (Ring memory); // onlyAdmin
}

interface IUAmulet is IERC721Enumerable {
  struct Amulet {
      uint256 mintedTimestamp;
      uint256 mintedBlockNumber;
      uint256 lastTransferTimestamp;
  }    
  function burn(uint256 tokenId) external; // onlyAdmin
  function getTokenTraits(uint256 tokenId) external view returns (Amulet memory); // onlyAdmin
}


contract Migrations is ReentrancyGuard, Ownable, Pausable {
  /** CONTRACTS */
  IUNFT private uNft;
  IUGNFTs private ugNFT;
  IUGNFT private UGNFTnew;
  IUGFYakuza private ugFYakuza;
  IUBlood private uBlood;
  IURing private uRing;
  IUAmulet private uAmulet;
  IUArena private uArena;
  IUGame private uGame;
  IUGArena private ugArena;
  IUGRaid private ugRaid;

  constructor(
    address _ugNFT, 
    address _ugNFTnew, 
    address _ugFYakuza, 
    address _unft, 
    address _ublood, 
    address _uring, 
    address _uamulet,
    address _uArena,
    address _uGame,
    address _ugArena,
    address _ugRaid,
    address _devWallet
  ){
    ugNFT = IUGNFTs(_ugNFT);
    UGNFTnew = IUGNFT(_ugNFTnew);
    ugFYakuza = IUGFYakuza(_ugFYakuza);
    uBlood = IUBlood(_ublood);
    uRing = IURing(_uring);
    uAmulet = IUAmulet(_uamulet);
    uNft = IUNFT(_unft);
    uArena = IUArena(_uArena);
    uGame = IUGame(_uGame);
    ugArena = IUGArena(_ugArena);
    ugRaid = IUGRaid(_ugRaid);
    devWallet = _devWallet;
  }

  //Errors
  error InvalidOwner();
  error InvalidAmount();
  error InvalidAccount();
  error NotEnough();

  uint256 public mergePrice = 5000000;
  address private devWallet;

  //send in old fighter ids, maybe include gold stat upgrades here
  function migrateFighters(uint256[] calldata v1TokenIds) external nonReentrant whenNotPaused {
    //format v1Fighter to v2 format
    IUNFT.FighterYakuza memory _oldFighter;
    IUGFYakuza.FighterYakuza[] memory v1Fighters = new IUGFYakuza.FighterYakuza[](v1TokenIds.length);
    
    for(uint i = 0; i< v1TokenIds.length; i++){
      //verify ownership of oldfighter to msgSender
      if(uNft.ownerOf(v1TokenIds[i]) != _msgSender() && uArena.getStake(v1TokenIds[i]).owner != _msgSender()) revert InvalidOwner();
        _oldFighter = uGame.getFyTokenTraits(v1TokenIds[i]);
        v1Fighters[i].isFighter = _oldFighter.isFighter;
        //change gen0 from bool to uint which can only hold 0 or 1
        v1Fighters[i].Gen = _oldFighter.isGen0 ? 0: 1;
        v1Fighters[i].level = uint8(_oldFighter.level);
        v1Fighters[i].rank = _oldFighter.rank;
        v1Fighters[i].courage = _oldFighter.courage;
        v1Fighters[i].cunning = _oldFighter.cunning;
        v1Fighters[i].brutality = _oldFighter.brutality;
        v1Fighters[i].knuckles = 0;
        v1Fighters[i].chains = 0;
        v1Fighters[i].butterfly = 0;
        v1Fighters[i].machete = 0;
        v1Fighters[i].katana = 0;
        v1Fighters[i].scars = 0;
        v1Fighters[i].imageId = 0;
        v1Fighters[i].lastLevelUpgradeTime = 0;
        v1Fighters[i].lastRankUpgradeTime = 0;
        v1Fighters[i].lastRaidTime = 0;

        uNft.burn(v1TokenIds[i]);
    }
    
    ugFYakuza.batchMigrateFYakuza(_msgSender(), v1TokenIds, v1Fighters);
    
  }

  function migrateV2Fighters(uint256[] calldata v2TokenIds, bool isStaked) external nonReentrant whenNotPaused {
    if((!isStaked && !ugNFT.checkUserBatchBalance(_msgSender(), v2TokenIds)) ||
        (isStaked && !ugArena.verifyAllStakedByUser(_msgSender(), v2TokenIds)) ) revert InvalidOwner();
    //format v1Fighter to v2 format
    IUGNFTs.FighterYakuza memory _oldFighter;
    IUGFYakuza.FighterYakuza[] memory v2Fighters = new IUGFYakuza.FighterYakuza[](v2TokenIds.length);
    uint256[] memory packedFighters = ugNFT.getPackedFighters(v2TokenIds);
    uint256[] memory amounts = new uint256[](v2TokenIds.length);
    uint256[] memory migrateIds = new uint256[](v2TokenIds.length);
    for(uint i = 0; i< v2TokenIds.length; i++){
      //verify ownership of oldfighter to msgSender
      
      
        _oldFighter = unPackFighter(packedFighters[i]);
        require(_oldFighter.imageId > 0, "Already Migrated");
        v2Fighters[i].isFighter = _oldFighter.isFighter;
        //change gen0 from bool to uint which can only hold 0 or 1
        v2Fighters[i].Gen = _oldFighter.scars >= 100 ? 0: 1;
        v2Fighters[i].level = uint8(_oldFighter.level);
        v2Fighters[i].rank = _oldFighter.rank;
        v2Fighters[i].courage = _oldFighter.courage;
        v2Fighters[i].cunning = _oldFighter.cunning;
        v2Fighters[i].brutality = _oldFighter.brutality;
        v2Fighters[i].knuckles = 0;
        v2Fighters[i].chains = 0;
        v2Fighters[i].butterfly = 0;
        v2Fighters[i].machete = 0;
        v2Fighters[i].katana = 0;
        v2Fighters[i].scars = 0;
        v2Fighters[i].imageId = 0;
        v2Fighters[i].lastLevelUpgradeTime = 0;
        v2Fighters[i].lastRankUpgradeTime = 0;
        v2Fighters[i].lastRaidTime = 0;

        migrateIds[i] = _oldFighter.imageId;

        //set old fighters stats to 0 if staked in arena
        if(isStaked){
          _oldFighter.Gen = 0;
          _oldFighter.imageId = 0;
          _oldFighter.level = 0;
          _oldFighter.rank = 0;
          _oldFighter.courage = 0;
          _oldFighter.cunning = 0;
          _oldFighter.scars = 0;
          _oldFighter.brutality = 0;
          _oldFighter.lastLevelUpgradeTime = 0;
          _oldFighter.lastRankUpgradeTime = 0;
          _oldFighter.lastRaidTime = 0;

          ugNFT.setFighter(v2TokenIds[i], _oldFighter);
        } else amounts[i] = 1;

    }
    if(!isStaked) ugNFT.safeBatchTransferFrom(_msgSender(), address(this), v2TokenIds, amounts, "");
    
    ugFYakuza.batchMigrateFYakuza(_msgSender(), migrateIds, v2Fighters);
    
  }

  function unPackFighter(uint256 packedFighter) private pure returns (IUGNFTs.FighterYakuza memory) {
    IUGNFTs.FighterYakuza memory fighter;   
    fighter.isFighter = uint8(packedFighter)%2 == 1 ? true : false;
    fighter.Gen = uint8(packedFighter>>1)%2;
    fighter.level = uint8(packedFighter>>2);
    fighter.rank = uint8(packedFighter>>10);
    fighter.courage = uint8(packedFighter>>18);
    fighter.cunning = uint8(packedFighter>>26);
    fighter.brutality = uint8(packedFighter>>34);
    fighter.knuckles = uint8(packedFighter>>42);
    fighter.chains = uint8(packedFighter>>50);
    fighter.butterfly = uint8(packedFighter>>58);
    fighter.machete = uint8(packedFighter>>66);
    fighter.katana = uint8(packedFighter>>74);
    fighter.scars = uint16(packedFighter>>90);
    fighter.imageId = uint16(packedFighter>>106);
    fighter.lastLevelUpgradeTime = uint32(packedFighter>>138);
    fighter.lastRankUpgradeTime = uint32(packedFighter>>170);
    fighter.lastRaidTime = uint32(packedFighter>>202);
    return fighter;
  }


   function mergeFighters(uint256 v1TokenId1, uint256 v1TokenId2) external nonReentrant whenNotPaused {
    //format v1Fighter to v2 format
    IUNFT.FighterYakuza memory _oldFighter1;
    IUNFT.FighterYakuza memory _oldFighter2;
    IUGFYakuza.FighterYakuza[] memory v1Fighter = new IUGFYakuza.FighterYakuza[](1);
    
      //verify ownership of oldfighter to msgSender
      if((uNft.ownerOf(v1TokenId1) != _msgSender() && uArena.getStake(v1TokenId1).owner != _msgSender()) ||
         (uNft.ownerOf(v1TokenId2) != _msgSender() && uArena.getStake(v1TokenId2).owner != _msgSender())) revert InvalidOwner();
      _oldFighter1 = uGame.getFyTokenTraits(v1TokenId1);
      _oldFighter2 = uGame.getFyTokenTraits(v1TokenId2);
      v1Fighter[0].isFighter = true;
      //change gen0 from bool to uint which can only hold 0 or 1
      v1Fighter[0].Gen = 0;
      v1Fighter[0].level = 1;
      v1Fighter[0].rank = 0;
      v1Fighter[0].courage = _oldFighter1.courage > _oldFighter2.courage ? _oldFighter1.courage : _oldFighter2.courage;
      v1Fighter[0].cunning = _oldFighter1.cunning > _oldFighter2.cunning ? _oldFighter1.cunning : _oldFighter2.cunning;
      v1Fighter[0].brutality = _oldFighter1.brutality > _oldFighter2.brutality ? _oldFighter1.brutality : _oldFighter2.brutality;
      v1Fighter[0].knuckles = 0;
      v1Fighter[0].chains = 0;
      v1Fighter[0].butterfly = 0;
      v1Fighter[0].machete = 0;
      v1Fighter[0].katana = 0;
      v1Fighter[0].scars = 0;
      v1Fighter[0].imageId = uint16(v1TokenId1);
      v1Fighter[0].lastLevelUpgradeTime = 0;
      v1Fighter[0].lastRankUpgradeTime = 0;
      v1Fighter[0].lastRaidTime = 0;

      burnBlood(_msgSender(), mergePrice);
      uNft.burn(v1TokenId1);
      uNft.burn(v1TokenId2);

      uint256[] memory _ids = new uint256[](1);
      _ids[0] = v1TokenId1;    
    
    ugFYakuza.batchMigrateFYakuza(_msgSender(), _ids, v1Fighter);    
  }

  function migrateRingAmulet(uint256[] calldata tokenIds, bool isRing) external whenNotPaused nonReentrant  {
    if(tokenIds.length < 10) revert NotEnough();
    //conversion from v1 rings to v2 rings
    uint256 level = tokenIds.length/10;
    uint256 v1RingsToBurn = level*10;
    
    for(uint i; i<v1RingsToBurn; i++){
      if(isRing){      
        if(uRing.ownerOf(tokenIds[i]) != _msgSender()) revert InvalidOwner();   
        uRing.burn(tokenIds[i]); 
      } else {// if amulet     
        if(uAmulet.ownerOf(tokenIds[i]) != _msgSender()) revert InvalidOwner();
        uAmulet.burn(tokenIds[i]);
      }    
    }
     
    UGNFTnew.mintRingAmulet(_msgSender(), level, isRing );
  }  

  function migrateV2RingAmulet(uint256 tokenId, bool isRing) external whenNotPaused nonReentrant  {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    require(
        tokenId == ugArena.getStakedRingIDForUser(_msgSender()) || 
        tokenId == ugArena.getStakedAmuletIDForUser(_msgSender()) ||
        ugNFT.checkUserBatchBalance(_msgSender(), tokenIds),
        'Invalid Token'        
    );
    if (isRing) require(tokenId > 5000 && tokenId <= 5000 + ugNFT.ttlRings(), "Invalid Token");    
    if (!isRing) require(tokenId > 10000 && tokenId <= 10000 + ugNFT.ttlAmulets(), "Invalid Token");

    IUGNFTs.RingAmulet memory ringAmulet = ugNFT.getRingAmulet(tokenId);   
    require (ringAmulet.level > 0,'Invalid Ring Amulet');
    ugNFT.levelUpRingAmulets(tokenId, 0); 
    //mint new ringAmulet  
    if(ugNFT.checkUserBatchBalance(_msgSender(), tokenIds)) ugNFT.safeTransferFrom(_msgSender(),address(this),tokenId, 1, "");
    UGNFTnew.mintRingAmulet(_msgSender(), ringAmulet.level, isRing );
  }  

  function migrateV2ForgeFightClubs(uint256[] memory tokenIds, bool isFightClub) external whenNotPaused nonReentrant {
    require(ugNFT.checkUserBatchBalance(_msgSender(), tokenIds),'Invalid Token');
    uint256[] memory _amounts = new uint256[](tokenIds.length);
    IUGNFTs.ForgeFightClub[] memory forgeFightClubs = ugNFT.getForgeFightClubs(tokenIds); 
    for(uint i; i<tokenIds.length;i++){
      if (isFightClub) require(tokenIds[i] > 20000 && tokenIds[i] <= 20000 + ugNFT.ttlFightClubs(), "Invalid Token");    
      if (!isFightClub) require(tokenIds[i] > 15000 && tokenIds[i] <= 15000 + ugNFT.ttlForges(), "Invalid Token");
      require (forgeFightClubs[i].size <= 5, 'Already Migrated');    
      require (forgeFightClubs[i].level <= 35, 'Already Migrated'); 
      //mint new forge fight club  
      UGNFTnew.mintFightClubForge(_msgSender(), "", forgeFightClubs[i].size, forgeFightClubs[i].level, isFightClub );
      _amounts[i] = 1;
    }
    ugNFT.safeBatchTransferFrom(_msgSender(), address(this), tokenIds, _amounts, "");
   
  } 

  function migrateV2StakedFightClubs() external whenNotPaused nonReentrant {
    uint256[] memory tokenIds = ugRaid.getStakedFightClubIDsForUser(_msgSender());  
    require(tokenIds.length > 0, "No Staked Tokens"); 
    uint256[] memory sizes = new uint256[](tokenIds.length);   
    uint256[] memory levels = new uint256[](tokenIds.length);   
    IUGNFTs.ForgeFightClub[] memory forgeFightClubs = ugNFT.getForgeFightClubs(tokenIds);    
    for(uint i; i<tokenIds.length;i++){   
      require (forgeFightClubs[i].size <= 4, 'Already Migrated');    
      require (forgeFightClubs[i].level <= 34, 'Already Migrated');    
      sizes[i] = 100;
      levels[i] = 100;
      
      //mint new ringAmulet  
      UGNFTnew.mintFightClubForge(_msgSender(), "", forgeFightClubs[i].size, forgeFightClubs[i].level, true );
    }
    ugNFT.levelUpFightClubsForges(tokenIds, sizes, levels); 
   
  }   

  function burnBlood(address account, uint256 amount) private {
    if(account == address(0x00)) revert InvalidAccount();
    if(amount == 0) revert InvalidAmount();
    uBlood.burn(account , amount * 1 ether);
    uBlood.mint(devWallet, amount * 1 ether /10);
  }

  function setMergePrice(uint256 amount) external onlyOwner {
    mergePrice = amount;
  }

  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }  

  function setDevWallet(address newWallet) external onlyOwner {
    require(newWallet != address(0x00), "Must not be 0 address");
    devWallet = newWallet;
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